/**
 * sync-subscription Edge Function
 *
 * Receives RevenueCat webhook events and updates profiles.subscription_status
 * in real-time. This closes the "refund + uninstall" gap where the client SDK
 * never fires because the app was deleted.
 *
 * RevenueCat webhook docs:
 *   https://www.revenuecat.com/docs/integrations/webhooks
 *
 * Supported event types:
 *   INITIAL_PURCHASE, RENEWAL, PRODUCT_CHANGE  → re-evaluate entitlements
 *   CANCELLATION, EXPIRATION, BILLING_ISSUE_DETECTED → re-evaluate
 *   SUBSCRIBER_ALIAS                            → ignored (no status change)
 *   NON_RENEWING_PURCHASE                       → re-evaluate (lifetime)
 *   UNCANCELLATION                              → re-evaluate
 *   REFUND (RevenueCat custom, via EXPIRATION with cancel_reason)
 *
 * Auth: Webhook is authenticated via a shared secret in the Authorization
 * header. RevenueCat sends: "Bearer <REVENUECAT_WEBHOOK_SECRET>".
 *
 * Required Supabase secrets:
 *   REVENUECAT_WEBHOOK_SECRET  – shared secret configured in RC dashboard
 *   REVENUECAT_API_SECRET      – RC secret API key (sk_...) for subscriber lookup
 *   REVENUECAT_ENTITLEMENT_ID  – e.g. "AfterWord Pro" (optional, defaults)
 *
 * Already available in Edge Functions:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */

export {};

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve: (handler: (req: Request) => Response | Promise<Response>) => void;
};

const OUTBOUND_TIMEOUT_MS = 10_000;

interface RevenueCatWebhookEvent {
  api_version: string;
  event: {
    type: string;
    app_user_id: string;
    aliases?: string[];
    original_app_user_id?: string;
    product_id?: string;
    entitlement_ids?: string[];
    period_type?: string;
    purchased_at_ms?: number;
    expiration_at_ms?: number;
    environment?: string;
    store?: string;
    cancel_reason?: string;
    is_trial_conversion?: boolean;
  };
}

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

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Determine subscription status by querying RevenueCat REST API.
 * This is the same logic as verify-subscription but without JWT auth
 * (since this is a server-to-server webhook, not a client call).
 */
async function resolveSubscriptionStatus(
  rcSecret: string,
  entitlementId: string,
  appUserId: string,
): Promise<string> {
  const rcRes = await fetchWithTimeout(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
    {
      headers: {
        Authorization: `Bearer ${rcSecret}`,
        "Content-Type": "application/json",
      },
    },
  );

  if (!rcRes.ok) {
    const text = await rcRes.text();
    throw new Error(`RevenueCat API ${rcRes.status}: ${text}`);
  }

  const rcData = (await rcRes.json()) as RevenueCatSubscriber;
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

  const hasEntitlement = activeEntitlements.some(([key]) => key === entitlementId);

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

  if (isLifetime) return "lifetime";
  if (hasEntitlement) return "pro";
  return "free";
}

/**
 * Update the user's subscription_status in Supabase via service_role RPC.
 */
async function updateSubscriptionStatus(
  supabaseUrl: string,
  serviceRoleKey: string,
  userId: string,
  newStatus: string,
): Promise<void> {
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
        new_status: newStatus,
      }),
    },
  );

  if (!rpcRes.ok) {
    const detail = await rpcRes.text();
    throw new Error(`Supabase RPC ${rpcRes.status}: ${detail}`);
  }
}

// Event types that don't require a status re-evaluation
const IGNORED_EVENTS = new Set([
  "SUBSCRIBER_ALIAS",
  "TRANSFER",
  "TEST",
]);

Deno.serve(async (req: Request) => {
  // Only accept POST
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── 1. Read secrets ──
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") || "";
  const rcSecret = Deno.env.get("REVENUECAT_API_SECRET") || "";
  const entitlementId = Deno.env.get("REVENUECAT_ENTITLEMENT_ID") || "AfterWord Pro";

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Supabase secrets not configured" }, 500);
  }
  if (!webhookSecret) {
    return jsonResponse({ error: "REVENUECAT_WEBHOOK_SECRET not configured" }, 500);
  }
  if (!rcSecret) {
    return jsonResponse({ error: "REVENUECAT_API_SECRET not configured" }, 500);
  }

  // ── 2. Verify webhook authorization ──
  // RevenueCat sends: Authorization: Bearer <secret>
  const authHeader = req.headers.get("authorization") || "";
  const providedSecret = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : authHeader.trim();

  if (!providedSecret || providedSecret !== webhookSecret) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  // ── 3. Parse webhook payload ──
  let payload: RevenueCatWebhookEvent;
  try {
    payload = (await req.json()) as RevenueCatWebhookEvent;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const event = payload?.event;
  if (!event || !event.type || !event.app_user_id) {
    return jsonResponse({ error: "Missing event data" }, 400);
  }

  const eventType = event.type;
  const appUserId = event.app_user_id;

  // ── 4. Skip events that don't affect subscription status ──
  if (IGNORED_EVENTS.has(eventType)) {
    return jsonResponse({ status: "ignored", event_type: eventType });
  }

  // ── 5. Resolve current subscription status from RevenueCat ──
  // We ALWAYS re-query RevenueCat rather than trusting the webhook payload,
  // because the webhook may arrive out of order or be replayed.
  // The GET /subscribers endpoint gives us the authoritative current state.
  let newStatus: string;
  try {
    newStatus = await resolveSubscriptionStatus(rcSecret, entitlementId, appUserId);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    console.error(`[sync-subscription] RC lookup failed for ${appUserId}: ${msg}`);
    return jsonResponse({ error: "RevenueCat lookup failed", detail: msg }, 502);
  }

  // ── 6. Update Supabase ──
  try {
    await updateSubscriptionStatus(supabaseUrl, serviceRoleKey, appUserId, newStatus);
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    console.error(`[sync-subscription] DB update failed for ${appUserId}: ${msg}`);
    return jsonResponse({ error: "Database update failed", detail: msg }, 500);
  }

  console.log(
    `[sync-subscription] ${eventType} → ${appUserId} → ${newStatus}`,
  );

  // ── 7. Return success ──
  // RevenueCat expects a 200 response to consider the webhook delivered.
  return jsonResponse({
    status: newStatus,
    event_type: eventType,
    app_user_id: appUserId,
  });
});
