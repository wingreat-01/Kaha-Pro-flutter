// supabase/functions/_shared/google-play.ts
//
// Shared between verify-purchase (called from the app right after a
// purchase) and rtdn-webhook (called by Play's Pub/Sub push later, on
// renewal/cancel/expiry). Both need the same three things: an
// authenticated call to Google's subscriptionsv2 API, a decision on
// whether the resulting state means "this store keeps access," and a
// single writer that applies that decision to the database so the two
// callers can never disagree about how a given Google response gets
// turned into stores.plan / ai credits / logs.

import { SignJWT, importPKCS8 } from "npm:jose@5";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";

// Real Play Console product IDs (created directly under these names,
// no rename needed) mapped to the plan values stores.plan actually
// uses.
export const PRODUCT_ID_TO_PLAN: Record<string, string> = {
  merq_starter: "starter",
  merq_basic: "basic",
  merq_pro: "pro",
};

export type SubscriptionState =
  | "SUBSCRIPTION_STATE_ACTIVE"
  | "SUBSCRIPTION_STATE_CANCELED"
  | "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
  | "SUBSCRIPTION_STATE_ON_HOLD"
  | "SUBSCRIPTION_STATE_PAUSED"
  | "SUBSCRIPTION_STATE_EXPIRED"
  | "SUBSCRIPTION_STATE_PENDING"
  | string;

export interface SubscriptionPurchaseV2 {
  subscriptionState: SubscriptionState;
  acknowledgementState?: "ACKNOWLEDGEMENT_STATE_PENDING" | "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
  latestOrderId?: string;
  // Set when this purchase replaced an earlier one inside Play (e.g.
  // Starter -> Pro): Play issues a NEW token for the new plan and
  // points back at the old one here.
  linkedPurchaseToken?: string;
  testPurchase?: Record<string, unknown>;
  lineItems?: Array<{
    productId: string;
    expiryTime?: string;
  }>;
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

/**
 * Exchanges the service account credentials (GOOGLE_SERVICE_ACCOUNT_JSON
 * secret) for a short-lived OAuth access token scoped to the Android
 * Publisher API, via the standard JWT-bearer grant. Cached in-memory
 * for the life of the isolate since Google's tokens are valid ~1hr and
 * a fresh signed JWT round-trip on every call is wasted latency.
 */
async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt - 60 > now) {
    return cachedAccessToken.token;
  }

  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("GOOGLE_SERVICE_ACCOUNT_JSON secret is not set");
  const creds = JSON.parse(raw) as { client_email: string; private_key: string };

  const privateKey = await importPKCS8(creds.private_key, "RS256");

  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/androidpublisher",
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(creds.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    throw new Error(`Google OAuth token exchange failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json() as { access_token: string; expires_in: number };
  cachedAccessToken = { token: data.access_token, expiresAt: now + data.expires_in };
  return data.access_token;
}

function packageName(): string {
  const pkg = Deno.env.get("ANDROID_PACKAGE_NAME");
  if (!pkg) throw new Error("ANDROID_PACKAGE_NAME secret is not set");
  return pkg;
}

/** Fetches the current state of a subscription purchase from Google. */
export async function getSubscription(purchaseToken: string): Promise<SubscriptionPurchaseV2> {
  const token = await getAccessToken();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName()}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) {
    throw new Error(`subscriptionsv2.get failed: ${res.status} ${await res.text()}`);
  }
  return await res.json() as SubscriptionPurchaseV2;
}

/**
 * Acknowledges a purchase so Play doesn't auto-refund it after 3 days.
 * Per Google's May 2025 change, the acknowledge endpoint no longer
 * takes subscriptionId in the path -- only the token, under
 * subscriptionsv2.
 */
export async function acknowledgeSubscription(purchaseToken: string): Promise<void> {
  const token = await getAccessToken();
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName()}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`subscriptionsv2 acknowledge failed: ${res.status} ${await res.text()}`);
  }
}

/**
 * Whether this state means the store should currently have paid
 * access. Design decisions:
 * - on_hold is NOT entitled (access withdrawn -- Google couldn't
 *   collect payment).
 * - grace_period IS entitled (access kept while Google keeps
 *   retrying).
 * - canceled IS entitled until [expiryTime]. In Google's model,
 *   CANCELED means the customer turned off renewal but has already
 *   paid through the end of the current period -- cutting access the
 *   moment they cancel would take away time they paid for. Access
 *   ends when the period does: Play then sends an EXPIRED
 *   notification, and this also returns false for a CANCELED
 *   subscription whose expiry has passed, so a late or missed
 *   notification can't leave someone on a paid plan forever. A
 *   missing/unparseable expiry is treated as already expired (fail
 *   closed).
 */
export function isEntitled(state: SubscriptionState, expiryTime?: string): boolean {
  if (
    state === "SUBSCRIPTION_STATE_ACTIVE" ||
    state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
  ) {
    return true;
  }
  if (state === "SUBSCRIPTION_STATE_CANCELED") {
    const expiresAt = expiryTime ? Date.parse(expiryTime) : NaN;
    return Number.isFinite(expiresAt) && expiresAt > Date.now();
  }
  return false;
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return encodeHex(new Uint8Array(digest));
}

async function findTokenOwner(
  supabase: SupabaseClient,
  purchaseToken: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("store_subscriptions")
    .select("store_id")
    .eq("purchase_token_hash", await sha256Hex(purchaseToken))
    .maybeSingle();
  if (error) throw new Error(`store_subscriptions owner lookup failed: ${error.message}`);
  return data?.store_id ?? null;
}

/**
 * Whether [storeId] is allowed to claim this Play purchase.
 *
 * A Play subscription belongs to a Google account, not to a MERQ
 * store, so a valid token proves only that *someone* paid -- not that
 * the store presenting it is the one that paid. Without this check,
 * applySubscriptionState's upsert (keyed on purchase_token_hash)
 * silently re-pointed the token at whichever store called last and
 * granted that store the paid plan.
 *
 * - Token already linked to a store: only that store may use it.
 * - Token unseen, but Play says it replaced an earlier token (a plan
 *   switch): the earlier token's owner decides. Without this, a
 *   legitimate Starter -> Pro upgrade would look like a brand-new
 *   token and be refused or, worse, claimable by another store.
 * - Token completely unseen: first store to present it claims it.
 *   In the normal flow that is the store that just bought it, since
 *   the app verifies immediately after the purchase sheet closes.
 */
export async function canStoreClaimPurchase(
  supabase: SupabaseClient,
  storeId: string,
  purchaseToken: string,
  purchase: SubscriptionPurchaseV2,
): Promise<boolean> {
  const owner = await findTokenOwner(supabase, purchaseToken);
  if (owner) return owner === storeId;

  if (purchase.linkedPurchaseToken) {
    const linkedOwner = await findTokenOwner(supabase, purchase.linkedPurchaseToken);
    if (linkedOwner) return linkedOwner === storeId;
  }
  return true;
}

/**
 * The single writer both verify-purchase and rtdn-webhook call once
 * they have a fresh SubscriptionPurchaseV2 from Google. Keeping this
 * in one place is what guarantees the "immediate purchase" path and
 * the "later webhook" path can never disagree about how a Google
 * response becomes stores.plan / credits / logs.
 *
 * - Upserts store_subscriptions (by purchase_token_hash) with the
 *   latest known state.
 * - If entitled: sets stores.plan to the mapped plan and calls
 *   grant_plan_credits to top up credits immediately.
 * - If not entitled and the store's plan currently matches this
 *   product's plan: downgrades the store back to 'free' so access is
 *   actually withdrawn (a cancellation/expiry notification is exactly
 *   what should trigger this).
 * - Always logs the event to purchase_verifications, tagged
 *   is_test_purchase from Google's own testPurchase field.
 */
export async function applySubscriptionState(
  supabase: SupabaseClient,
  storeId: string,
  purchaseToken: string,
  purchase: SubscriptionPurchaseV2,
): Promise<void> {
  const lineItem = purchase.lineItems?.[0];
  const productId = lineItem?.productId ?? "unknown";
  const plan = PRODUCT_ID_TO_PLAN[productId] ?? "free";
  const entitled = isEntitled(purchase.subscriptionState, lineItem?.expiryTime);
  const tokenHash = await sha256Hex(purchaseToken);
  const isTest = purchase.testPurchase !== undefined;

  const { error: upsertError } = await supabase
    .from("store_subscriptions")
    .upsert(
      {
        store_id: storeId,
        purchase_token_hash: tokenHash,
        product_id: productId,
        plan,
        subscription_state: purchase.subscriptionState,
        latest_order_id: purchase.latestOrderId ?? null,
        expiry_time: lineItem?.expiryTime ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "purchase_token_hash" },
    );
  if (upsertError) {
    throw new Error(`store_subscriptions upsert failed: ${upsertError.message}`);
  }

  if (entitled) {
    const { error: planError } = await supabase
      .from("stores")
      .update({ plan })
      .eq("id", storeId);
    if (planError) throw new Error(`stores.plan update failed: ${planError.message}`);

    // A CANCELED (but still paid-through) subscription keeps its plan
    // but must not trigger a credit top-up: the cancellation
    // notification would otherwise refill credits to the full
    // allotment every time, for a customer who isn't renewing.
    if (purchase.subscriptionState !== "SUBSCRIPTION_STATE_CANCELED") {
      const { error: creditsError } = await supabase.rpc("grant_plan_credits", {
        p_store_id: storeId,
      });
      if (creditsError) throw new Error(`grant_plan_credits failed: ${creditsError.message}`);
    }
  } else {
    // Only downgrade if this product's plan is the one currently
    // active -- avoids a stale/duplicate notification for an old
    // token clobbering a store that has since upgraded again.
    const { data: store, error: fetchError } = await supabase
      .from("stores")
      .select("plan")
      .eq("id", storeId)
      .single();
    if (fetchError) throw new Error(`stores fetch failed: ${fetchError.message}`);

    if (store?.plan === plan) {
      const { error: downgradeError } = await supabase
        .from("stores")
        .update({ plan: "free" })
        .eq("id", storeId);
      if (downgradeError) throw new Error(`stores downgrade failed: ${downgradeError.message}`);
    }
  }

  const { error: logError } = await supabase.from("purchase_verifications").insert({
    store_id: storeId,
    product_id: productId,
    plan,
    subscription_state: purchase.subscriptionState,
    is_test_purchase: isTest,
    order_id: purchase.latestOrderId ?? null,
    purchase_token_hash: tokenHash,
  });
  if (logError) throw new Error(`purchase_verifications insert failed: ${logError.message}`);
}

export function serviceRoleClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}
