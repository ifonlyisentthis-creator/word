/**
 * verify-subscription Edge Function
 *
 * Server-side subscription verification via RevenueCat REST API.
 * The client calls this instead of the old sync_my_subscription_status RPC,
 * so a modded app cannot lie about its subscription tier.
 *
 * Flow:
 *   1. Gateway JWT verification disabled (verify_jwt = false in config.toml)
 *      to match the metadata-crypto pattern. Auth is verified server-side
 *      via Supabase /auth/v1/user (signature-checked, not just decoded).
 *   2. Verify JWT and extract user_id via Supabase Auth API
 *   3. Call RevenueCat GET /v1/subscribers/{user_id}
 *   4. Determine status from entitlements + product IDs
 *   5. Update profiles.subscription_status via service_role
 *   6. Return { status } to the client
 *
 * Required Supabase secrets:
 *   REVENUECAT_API_SECRET  – RevenueCat secret API key (sk_...)
 *   REVENUECAT_ENTITLEMENT_ID – e.g. "AfterWord Pro" (optional, defaults to "AfterWord Pro")
 *
 * Already available in Edge Functions:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
 */

export {};

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
};

interface RevenueCatSubscriber {
  subscriber: {
    entitlements: Record<
      string,
      { expires_date: string | null; product_identifier: string }
    >;
    subscriptions: Record<string, unknown>;
    non_subscriptions: Record<string, unknown[]>;
  };
}

const OUTBOUND_TIMEOUT_MS = 10_000;

function isTimeoutError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return error.name === "AbortError";
}

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
  timeoutMs = OUTBOUND_TIMEOUT_MS,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function corsHeaders(): Headers {
  const h = new Headers({ "Content-Type": "application/json" });
  h.set("Access-Control-Allow-Origin", "*");
  h.set(
    "Access-Control-Allow-Headers",
    "authorization, x-client-info, apikey, content-type"
  );
  h.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  return h;
}

/**
 * Verify the JWT by calling Supabase Auth server-side.
 * This ensures the token signature is valid — a forged JWT will be rejected.
 */
async function getVerifiedUserId(
  supabaseUrl: string,
  supabaseAnonKey: string,
  authHeader: string,
): Promise<string | null> {
  try {
    const response = await fetchWithTimeout(`${supabaseUrl}/auth/v1/user`, {
      method: "GET",
      headers: {
        apikey: supabaseAnonKey,
        Authorization: authHeader,
      },
    });
    if (!response.ok) return null;
    const data = await response.json();
    if (data && typeof data.id === "string" && data.id.length > 0) {
      return data.id;
    }
    return null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  const headers = corsHeaders();

  if (req.method === "OPTIONS") {
    return new Response(null, { headers, status: 204 });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      headers,
      status: 405,
    });
  }

  // ── 1. Read secrets ──────────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: "Supabase edge function secrets are not configured" }),
      { headers, status: 500 }
    );
  }
  const rcSecret = Deno.env.get("REVENUECAT_API_SECRET") || "";
  if (!rcSecret) {
    return new Response(
      JSON.stringify({ error: "REVENUECAT_API_SECRET not configured" }),
      { headers, status: 500 }
    );
  }
  const entitlementId =
    Deno.env.get("REVENUECAT_ENTITLEMENT_ID") || "AfterWord Pro";

  // ── 2. Verify JWT server-side (prevents forged-token attacks) ────
  const authHeader = req.headers.get("authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers,
      status: 401,
    });
  }
  const userId = await getVerifiedUserId(supabaseUrl, supabaseAnonKey, authHeader);
  if (!userId) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers,
      status: 401,
    });
  }

  // ── 3. Call RevenueCat REST API ────────────────────────────────────
  let rcData: RevenueCatSubscriber;
  try {
    const rcRes = await fetchWithTimeout(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
      {
        headers: {
          Authorization: `Bearer ${rcSecret}`,
          "Content-Type": "application/json",
        },
      }
    );
    if (!rcRes.ok) {
      const text = await rcRes.text();
      return new Response(
        JSON.stringify({
          error: "RevenueCat API error",
          detail: text,
          rc_status: rcRes.status,
        }),
        { headers, status: 502 }
      );
    }
    rcData = (await rcRes.json()) as RevenueCatSubscriber;
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: isTimeoutError(err)
          ? "RevenueCat request timed out"
          : "Failed to reach RevenueCat",
      }),
      { headers, status: 502 }
    );
  }

  // ── 4. Determine subscription status ───────────────────────────────
  const subscriber = rcData.subscriber;
  const entitlementsRaw =
    subscriber && typeof subscriber.entitlements === "object" && subscriber.entitlements
      ? subscriber.entitlements
      : {};
  const activeEntitlements = Object.entries(entitlementsRaw).filter(([, ent]) => {
    if (!ent || typeof ent !== "object") return false;
    const expiresDate =
      "expires_date" in ent && typeof ent.expires_date === "string"
        ? ent.expires_date
        : null;
    if (!expiresDate) return true; // lifetime / non-expiring
    return new Date(expiresDate) > new Date();
  });

  const hasEntitlement = activeEntitlements.some(
    ([key]) => key === entitlementId
  );

  // Check for lifetime product ONLY in active entitlements.
  // Do NOT check non_subscriptions — it includes refunded purchases,
  // so a user who bought lifetime and got a refund would still match.
  const isLifetime = activeEntitlements.some(([, ent]) => {
    const productId =
      ent &&
      typeof ent === "object" &&
      "product_identifier" in ent &&
      typeof ent.product_identifier === "string"
        ? ent.product_identifier
        : "";
    return productId.toLowerCase().includes("lifetime");
  });

  let status: string;
  if (isLifetime) {
    status = "lifetime";
  } else if (hasEntitlement) {
    status = "pro";
  } else {
    status = "free";
  }

  // ── 5. Update profiles via service_role through Supabase RPC REST ───
  try {
    const rpcRes = await fetchWithTimeout(
      `${supabaseUrl}/rest/v1/rpc/edge_set_subscription_status`,
      {
        method: "POST",
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          target_user_id: userId,
          new_status: status,
        }),
      },
    );

    if (!rpcRes.ok) {
      const detailText = await rpcRes.text();
      return new Response(
        JSON.stringify({
          error: "Profile update failed",
          detail: detailText,
          supabase_status: rpcRes.status,
        }),
        { headers, status: 500 },
      );
    }
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: isTimeoutError(err)
          ? "Profile update request timed out"
          : "Profile update error",
      }),
      { headers, status: 500 }
    );
  }

  // ── 6. Return verified status ──────────────────────────────────────
  return new Response(JSON.stringify({ status }), { headers, status: 200 });
});
