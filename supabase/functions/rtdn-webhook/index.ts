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
  testNotification?: {
    version: string;
  };
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
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

    const sub = notification.subscriptionNotification;
    if (!sub) {
      console.log("rtdn-webhook: notification with no subscriptionNotification payload, ignoring");
      return new Response("OK", { status: 200 });
    }

    const supabase = serviceRoleClient();
    const tokenHash = await sha256Hex(sub.purchaseToken);

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
    const purchase = await getSubscription(sub.purchaseToken);
    await applySubscriptionState(supabase, existing.store_id, sub.purchaseToken, purchase);

    return new Response("OK", { status: 200 });
  } catch (err) {
    console.error("rtdn-webhook unhandled exception:", err instanceof Error ? err.stack : err);
    // Non-200 makes Pub/Sub retry with backoff, which is the right
    // behavior for a transient failure (e.g. Google API hiccup).
    return new Response("Internal error", { status: 500 });
  }
});
