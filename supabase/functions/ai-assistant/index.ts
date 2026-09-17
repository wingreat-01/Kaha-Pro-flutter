// supabase/functions/verify-purchase/index.ts
//
// Server-side counterpart to lib/state/billing_provider.dart's
// _verifyAndActivate() stub. The client only knows Google's SDK said
// "purchased" -- that's not proof by itself (a compromised or
// modified client could fake the same call), so this function
// re-checks the purchase token directly against the Play Developer
// API before touching stores.plan at all. Same trust boundary
// reasoning as delete-account/index.ts using the service-role key
// instead of trusting the client's word for who owns what.
//
// SETUP REQUIRED BEFORE THIS CAN WORK (none of this is code -- all
// Play Console / Google Cloud console steps):
//   1. Play Console > Setup > API access -- link a Google Cloud
//      project to this app if not already linked.
//   2. In that Google Cloud project, create a service account (IAM &
//      Admin > Service Accounts), then in Play Console > API access,
//      grant that service account "View app information" +
//      "View financial data" permissions at minimum (financial data
//      is required to read subscription purchase state).
//   3. Create a JSON key for that service account, then set its
//      entire contents as a Supabase secret:
//        supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='<paste the whole JSON file>'
//   4. Set the app's package name (e.g. com.prohubapps.kahapro_flutter
//      -- check android/app/build.gradle's applicationId) as:
//        supabase secrets set ANDROID_PACKAGE_NAME='...'
//   5. Product IDs below (PRODUCT_ID_TO_PLAN) must match exactly
//      what's created in Play Console under Monetize > Subscriptions,
//      and match kStarterSubscriptionId/etc in billing_provider.dart.
//
// None of steps 1-4 need product IDs to exist yet -- they're account/
// permission setup, independent of any specific subscription. Step 5
// is the only place actual product IDs matter, and this function will
// simply return "unknown product" for any ID not yet in this map,
// which is safe (no accidental plan changes) rather than a crash.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { GoogleAuth } from 'npm:google-auth-library@9';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Maps Play Console subscription product IDs -> stores.plan values.
// Must stay in sync with billing_provider.dart's kStarterSubscriptionId/
// kBasicSubscriptionId/kProSubscriptionId constants on the client side.
const PRODUCT_ID_TO_PLAN: Record<string, string> = {
  merq_starter: 'starter',
  merq_basic: 'basic',
  merq_pro: 'pro',
};

// Subscription states that mean "the user should have access right
// now." ON_HOLD/PAUSED/CANCELED/EXPIRED are deliberately excluded --
// CANCELED still means "access until expiry" in Play's model, but
// treating it as active here would let a store keep upgraded access
// indefinitely after cancellation if this function were ever called
// again for the same token; the real cancellation handling (letting
// access run out at expiryTime, not revoking immediately) belongs in
// Real-time Developer Notifications handling, not here. This function
// answers one question only: "is this token good for granting the
// plan right now."
const ACTIVE_STATES = new Set(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD']);

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Purchase tokens are long-lived credentials, not safe to store in
// plain text in a log table -- this is only for idempotency / lookup
// purposes (see purchase_verifications' comment), not for re-verifying
// the purchase later, so a one-way hash is enough.
async function hashToken(token: string): Promise<string> {
  const data = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

let cachedAuth: GoogleAuth | null = null;
function getGoogleAuth(): GoogleAuth {
  if (!cachedAuth) {
    const credentialsJson = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
    if (!credentialsJson) {
      throw new Error('GOOGLE_SERVICE_ACCOUNT_JSON secret is not set.');
    }
    cachedAuth = new GoogleAuth({
      credentials: JSON.parse(credentialsJson),
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });
  }
  return cachedAuth;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Missing Authorization header.' }, 401);
  }

  // Caller's own JWT -- used only to identify which store this
  // purchase belongs to (via store_members, same pattern as
  // delete-account/index.ts). RLS is not relied on for the actual
  // stores.plan write below -- that write uses the service-role
  // client further down, since it must succeed regardless of what
  // policies exist on stores for authenticated users.
  const callerClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: 'Invalid or expired session.' }, 401);
  }

  let productId: string;
  let purchaseToken: string;
  try {
    const body = await req.json();
    if (typeof body.productId !== 'string' || typeof body.purchaseToken !== 'string') {
      return jsonResponse({ error: 'productId and purchaseToken are required.' }, 400);
    }
    productId = body.productId;
    purchaseToken = body.purchaseToken;
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }

  const targetPlan = PRODUCT_ID_TO_PLAN[productId];
  if (!targetPlan) {
    // Not a crash -- just means this productId isn't one of ours
    // (typo, stale client, or a product removed from Play Console).
    return jsonResponse({ error: `Unknown product ID: ${productId}` }, 400);
  }

  // store_members links this auth user to their store -- same lookup
  // delete-account/index.ts already relies on, using the service-role
  // client since RLS-scoped queries as the caller would work equally
  // well here, but the service-role client is needed a few lines down
  // anyway for the actual stores update, so one client covers both.
  const serviceClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: membership, error: membershipError } = await serviceClient
    .from('store_members')
    .select('store_id')
    .eq('auth_user_id', userData.user.id)
    .single();

  if (membershipError || !membership) {
    console.error('Could not find store_members row for caller:', membershipError);
    return jsonResponse({ error: 'Could not determine which store this purchase belongs to.' }, 404);
  }

  const storeId = membership.store_id as string;
  const packageName = Deno.env.get('ANDROID_PACKAGE_NAME');
  if (!packageName) {
    console.error('ANDROID_PACKAGE_NAME secret is not set.');
    return jsonResponse({ error: 'Server is not configured for purchase verification yet.' }, 500);
  }

  // --- Verify the token against Google, not the client's say-so ---
  let accessToken: string | null | undefined;
  try {
    const auth = getGoogleAuth();
    const client = await auth.getClient();
    const tokenResponse = await client.getAccessToken();
    accessToken = tokenResponse.token;
  } catch (err) {
    console.error('Failed to obtain Google access token:', err);
    return jsonResponse({ error: 'Could not authenticate with Google Play.' }, 500);
  }

  const verifyUrl =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;

  let purchase: any;
  try {
    const res = await fetch(verifyUrl, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) {
      const errBody = await res.text();
      console.error(`Play Developer API returned ${res.status}:`, errBody);
      return jsonResponse({ error: 'Could not verify purchase with Google Play.' }, 502);
    }
    purchase = await res.json();
  } catch (err) {
    console.error('Network error calling Play Developer API:', err);
    return jsonResponse({ error: 'Could not reach Google Play to verify purchase.' }, 502);
  }

  // lineItems[0] is the only entry for a plain single-product
  // subscription (not using subscription-with-add-ons); if that
  // changes later this line needs to search the array instead of
  // trusting index 0.
  const lineItem = purchase.lineItems?.[0];
  if (!lineItem || lineItem.productId !== productId) {
    console.error('Purchase token productId mismatch:', { expected: productId, got: lineItem?.productId });
    return jsonResponse({ error: 'Purchase token does not match the requested plan.' }, 400);
  }

  if (!ACTIVE_STATES.has(purchase.subscriptionState)) {
    return jsonResponse(
      { error: `Subscription is not active (state: ${purchase.subscriptionState}).` },
      402,
    );
  }

  // Google's subscriptionsv2.get response sets testPurchase to a
  // (usually empty) object for License Tester / sandbox purchases,
  // and leaves it null/absent for a real paying customer -- this is
  // the only signal that distinguishes the two, since everything else
  // about a test purchase (subscriptionState, lineItems, etc.) looks
  // identical to a real one. Per the earlier decision, this does NOT
  // change how the purchase is handled (testers get the same
  // plan/credits as real customers) -- it's recorded purely so the
  // owner can tell them apart later in purchase_verifications, not
  // used to branch any logic above or below this line.
  const isTestPurchase = purchase.testPurchase != null;
  console.log(
    `[verify-purchase] ${isTestPurchase ? 'TEST' : 'real'} purchase verified — ` +
      `store=${storeId} product=${productId} state=${purchase.subscriptionState}`,
  );

  // Acknowledge within 3 days of the initial purchase is required by
  // Play policy or the purchase is automatically refunded --
  // subscriptionId is omitted per Google's May 2025 change (no longer
  // required, and not recommended when add-ons might be involved
  // later). Only acknowledges if not already acknowledged, since
  // acknowledging twice is unnecessary and this function may run more
  // than once for the same token (e.g. client retry after a network
  // blip on the first response).
  if (purchase.acknowledgementState !== 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED') {
    try {
      const ackUrl =
        `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
        `${encodeURIComponent(packageName)}/purchases/subscriptions/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
      const ackRes = await fetch(ackUrl, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      if (!ackRes.ok) {
        // Non-fatal -- the subscription is still valid and the plan
        // still gets granted below. An un-acknowledged purchase risks
        // Play auto-refunding it after 3 days if this never succeeds,
        // so this is logged loudly rather than silently ignored.
        console.error('Failed to acknowledge purchase (non-fatal, will retry next verify call):', await ackRes.text());
      }
    } catch (err) {
      console.error('Network error acknowledging purchase (non-fatal):', err);
    }
  }

  // --- Verified. Now actually grant the plan. ---
  const { error: updateError } = await serviceClient
    .from('stores')
    .update({
      plan: targetPlan,
      // Paid plans don't use plan_expires_at the way the free trial
      // does (see Store.isExpired / enforce_product_limit()) -- Play
      // itself owns renewal/cancellation timing, so this is left null
      // here rather than mirroring purchase.lineItems[0].expiryTime.
      // Open question for later: if you want a "grace period" UI
      // state before Real-time Developer Notifications are wired up,
      // that's a reason to start storing expiryTime here too -- not
      // done now since nothing reads it yet.
      ai_credits_remaining: 0, // reset below via the RPC that already exists
    })
    .eq('id', storeId);

  if (updateError) {
    console.error('Failed to update stores.plan after verified purchase:', updateError);
    return jsonResponse({ error: 'Purchase verified but could not be applied to your account.' }, 500);
  }

  // Top up credits to the new plan's allotment immediately rather
  // than waiting for whatever monthly reset job exists -- someone
  // who just paid for Pro shouldn't see 0 AI credits until an
  // unrelated cron job runs. ai_credit_allotment() is the same
  // function product_limit()'s sibling from the migrations already
  // applied (20260917_014_align_limits_to_upgrade_screen.sql).
  const { error: creditError } = await serviceClient.rpc('grant_plan_credits', { p_store_id: storeId });
  if (creditError) {
    // Non-fatal to the response -- the plan itself is already
    // upgraded and correct; credits will still catch up on the next
    // scheduled reset even if this immediate top-up failed.
    console.error('Failed to top up credits after plan upgrade (non-fatal):', creditError);
  }

  // Log this verification -- purely for the owner to monitor testers
  // vs real subscribers later (see purchase_verifications' comment);
  // never read back or acted on anywhere else in this function, so a
  // failure here doesn't affect the response.
  const tokenHash = await hashToken(purchaseToken);
  const { error: logError } = await serviceClient.from('purchase_verifications').insert({
    store_id: storeId,
    product_id: productId,
    plan: targetPlan,
    subscription_state: purchase.subscriptionState,
    is_test_purchase: isTestPurchase,
    order_id: purchase.latestOrderId ?? null,
    purchase_token_hash: tokenHash,
  });
  if (logError) {
    console.error('Failed to write purchase_verifications row (non-fatal):', logError);
  }

  return jsonResponse({ ok: true, plan: targetPlan }, 200);
});
