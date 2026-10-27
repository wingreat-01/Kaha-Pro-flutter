// supabase/functions/rtdn-webhook/index.ts
//
// Push endpoint for Google Play's Real-time Developer Notifications
// (RTDN), delivered via a Cloud Pub/Sub push subscription. This is
// what catches renewals/cancellations/expiries that happen *after*
// verify-purchase's initial check -- without it, a cancelled-but-not-
// yet-expired subscription looks identical to a never-cancelled one
// until the next time verify-purchase happens to run (which may be
// never again).
//
// Pub/Sub can't attach a Supabase session JWT to its push requests,
// so this function must have verify_jwt = false set for it in
// config.toml, and instead authenticates via a `?token=` query param
// checked against the RTDN_WEBHOOK_SECRET secret -- set that same
// value when creating the push subscription's endpoint URL in Google
// Cloud.
import { serviceRoleClient, getSubscription, applySubscriptionState } from "../_shared/google-play.ts";

interface PubSubPushBody {
  message: {
    data: string; // base64-encoded JSON
    messageId: string;
    publishTime: string;
  };
  subscription: string;
}

interface DeveloperNotification {
  version: string;
  packageName: string;
  eventTimeMillis: string;
  subscriptionNotification?: {
    version: string;
    notificationType: number;
    purchaseToken: string;
    subscriptionId: string;
  };
  // Refunds/chargebacks. productType 1 = subscription, 2 = one-time.
  voidedPurchaseNotification?: {
    purchaseToken: string;
    orderId?: string;
    productType: number;
    refundType?: number;
  };
  // Sent for one-time products (Lifetime). Purchases are unlocked by
  // verify-lifetime from the app, so these are acknowledged and ignored.
  oneTimeProductNotification?: {
    version: string;
    notificationType: number;
    purchaseToken: string;
    sku: string;
  };
  testNotification?: {
    version: string;
  };
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * A Lifetime purchase was refunded or charged back. Marks the purchase
 * refunded and, unless the store has another unrefunded Lifetime
 * purchase, moves it from 'lifetime' to 'free' (same fallback the
 * subscription path uses). Throws on database errors so Pub/Sub retries.
 */
async function revokeLifetime(
  supabase: ReturnType<typeof serviceRoleClient>,
  purchaseToken: string,
): Promise<void> {
  const { data: row, error: lookupError } = await supabase
    .from("lifetime_purchases")
    .select("store_id")
    .eq("purchase_token", purchaseToken)
    .maybeSingle();
  if (lookupError) throw new Error(`lifetime_purchases lookup failed: ${lookupError.message}`);
  if (!row) {
    // Not a Lifetime purchase: it may be an AI credit pack. Take those
    // credits back (never below zero).
    const { data: revoked, error: revokeError } = await supabase.rpc("revoke_ai_credits", {
      p_token_hash: await sha256Hex(purchaseToken),
    });
    if (revokeError) throw new Error(`revoke_ai_credits failed: ${revokeError.message}`);
    if (!revoked) {
      console.error("rtdn-webhook: refunded one-time purchase is not a known Lifetime or AI credit purchase, skipping");
    }
    return;
  }

  const { error: markError } = await supabase
    .from("lifetime_purchases")
    .update({ refunded_at: new Date().toISOString() })
    .eq("purchase_token", purchaseToken);
  if (markError) throw new Error(`lifetime_purchases refund mark failed: ${markError.message}`);

  const { data: stillOwned, error: othersError } = await supabase
    .from("lifetime_purchases")
    .select("purchase_token")
    .eq("store_id", row.store_id)
    .is("refunded_at", null)
    .limit(1);
  if (othersError) throw new Error(`lifetime_purchases check failed: ${othersError.message}`);
  if (stillOwned && stillOwned.length > 0) return;

  const { error: downgradeError } = await supabase
    .from("stores")
    .update({ plan: "free" })
    .eq("id", row.store_id)
    .eq("plan", "lifetime");
  if (downgradeError) throw new Error(`lifetime downgrade failed: ${downgradeError.message}`);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = new URL(req.url);
  const secret = url.searchParams.get("token");
  const expected = Deno.env.get("RTDN_WEBHOOK_SECRET");
  if (!expected || secret !== expected) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const body = await req.json() as PubSubPushBody;
    const decoded = atob(body.message.data);
    const notification = JSON.parse(decoded) as DeveloperNotification;

    if (notification.testNotification) {
      // Google's "Send test notification" button in Play Console --
      // acknowledge with 200 so it doesn't retry, nothing to process.
      console.log("rtdn-webhook: received test notification, no-op");
      return new Response("OK", { status: 200 });
    }

    const supabase = serviceRoleClient();
    const voided = notification.voidedPurchaseNotification;

    // Refunded Lifetime purchase: take the plan away.
    if (voided && voided.productType === 2) {
      await revokeLifetime(supabase, voided.purchaseToken);
      return new Response("OK", { status: 200 });
    }

    // Subscription events, plus refunded subscriptions (re-fetched from
    // Google below like any other change).
    const purchaseToken = notification.subscriptionNotification?.purchaseToken ??
      (voided && voided.productType === 1 ? voided.purchaseToken : undefined);
    if (!purchaseToken) {
      console.log("rtdn-webhook: nothing to process (no subscription or refund payload), ignoring");
      return new Response("OK", { status: 200 });
    }

    const tokenHash = await sha256Hex(purchaseToken);

    const { data: existing, error: lookupError } = await supabase
      .from("store_subscriptions")
      .select("store_id")
      .eq("purchase_token_hash", tokenHash)
      .maybeSingle();

    if (lookupError) {
      console.error("rtdn-webhook store_subscriptions lookup error:", lookupError.message);
      return new Response("Lookup failed", { status: 500 });
    }

    if (!existing) {
      // Token we've never seen via verify-purchase -- can't map it to
      // a store. Ack anyway (200) so Pub/Sub stops retrying; this is
      // logged for investigation rather than treated as fatal, since
      // retrying won't make the mapping appear.
      console.error("rtdn-webhook: no store_subscriptions row for this purchase token, skipping");
      return new Response("OK", { status: 200 });
    }

    // Always re-fetch from Google rather than trusting notificationType
    // alone -- it tells us *something* changed, not the current state,
    // and applySubscriptionState needs the real current state.
    const purchase = await getSubscription(purchaseToken);
    await applySubscriptionState(supabase, existing.store_id, purchaseToken, purchase);

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("rtdn-webhook unhandled exception:", err instanceof Error ? err.stack : err);
    // Non-200 makes Pub/Sub retry with backoff, which is the right
    // behavior for a transient failure (e.g. Google API hiccup).
    return new Response("Internal error", { status: 500 });
  }
});
