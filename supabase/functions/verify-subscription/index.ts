/**
 * verify-subscription Edge Function
 *
 * Server-side subscription verification via RevenueCat REST API.
 * The client calls this instead of the old sync_my_subscription_status RPC,
 * so a modded app cannot lie about its subscription tier.
 *
 * Flow:
 *   1. Gateway JWT verification disabled (verify_jwt = false in config.toml)
 *      to match the metadata-crypto pattern. Auth is checked manually below.
 *   2. Extract user_id from the JWT
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

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

function extractUserIdFromJwt(authHeader: string): string | null {
  try {
    const token = authHeader.replace(/^bearer\s+/i, "");
    const payloadB64 = token.split(".")[1];
    if (!payloadB64) return null;
    const payload = JSON.parse(atob(payloadB64));
    return payload.sub || null;
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

  // ── 1. Extract user ID from JWT ────────────────────────────────────
  const authHeader = req.headers.get("authorization") || "";
  const userId = extractUserIdFromJwt(authHeader);
  if (!userId) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      headers,
      status: 401,
    });
  }

  // ── 2. Read secrets ────────────────────────────────────────────────
  const rcSecret = Deno.env.get("REVENUECAT_API_SECRET") || "";
  if (!rcSecret) {
    return new Response(
      JSON.stringify({ error: "REVENUECAT_API_SECRET not configured" }),
      { headers, status: 500 }
    );
  }
  const entitlementId =
    Deno.env.get("REVENUECAT_ENTITLEMENT_ID") || "AfterWord Pro";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

  // ── 3. Call RevenueCat REST API ────────────────────────────────────
  let rcData: RevenueCatSubscriber;
  try {
    const rcRes = await fetch(
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
        error: "Failed to reach RevenueCat",
        detail: err instanceof Error ? err.message : String(err),
      }),
      { headers, status: 502 }
    );
  }

  // ── 4. Determine subscription status ───────────────────────────────
  const subscriber = rcData.subscriber;
  const activeEntitlements = Object.entries(subscriber.entitlements).filter(
    ([, ent]) => {
      if (!ent.expires_date) return true; // lifetime / non-expiring
      return new Date(ent.expires_date) > new Date();
    }
  );

  const hasEntitlement = activeEntitlements.some(
    ([key]) => key === entitlementId
  );

  // Check for lifetime product ONLY in active entitlements.
  // Do NOT check non_subscriptions — it includes refunded purchases,
  // so a user who bought lifetime and got a refund would still match.
  const isLifetime = activeEntitlements.some(([, ent]) =>
    ent.product_identifier.toLowerCase().includes("lifetime")
  );

  let status: string;
  if (isLifetime) {
    status = "lifetime";
  } else if (hasEntitlement) {
    status = "pro";
  } else {
    status = "free";
  }

  // ── 5. Update profiles via service_role using Supabase JS client ───
  // Using createClient with service_role key ensures the JWT role GUC
  // is set correctly, so the guard_subscription_status trigger passes.
  try {
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { error: rpcError } = await supabaseAdmin.rpc(
      "edge_set_subscription_status",
      { target_user_id: userId, new_status: status }
    );
    if (rpcError) {
      return new Response(
        JSON.stringify({ error: "Profile update failed", detail: rpcError }),
        { headers, status: 500 }
      );
    }
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: "Profile update error",
        detail: err instanceof Error ? err.message : String(err),
      }),
      { headers, status: 500 }
    );
  }

  // ── 6. Return verified status ──────────────────────────────────────
  return new Response(JSON.stringify({ status }), { headers, status: 200 });
});
