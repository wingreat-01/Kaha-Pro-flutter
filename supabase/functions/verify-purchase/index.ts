// supabase/functions/verify-purchase/index.ts
//
// Called by the app (billing_provider.dart's _verifyAndActivate) right
// after Play's purchase sheet reports success. Client-side purchase
// success is never trusted on its own -- this verifies the purchase
// against Google's own records before anything in the database
// changes, then delegates the actual state application to the shared
// applySubscriptionState() writer so this path and the later RTDN
// webhook path can never disagree about what a given Google response
// means for the store.
import { serviceRoleClient, getSubscription, acknowledgeSubscription, applySubscriptionState, canStoreClaimPurchase } from "../_shared/google-play.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) {
      return new Response(JSON.stringify({ error: "Missing auth token" }), { status: 401 });
    }

    const { purchaseToken } = await req.json() as { purchaseToken?: string };
    if (!purchaseToken) {
      return new Response(JSON.stringify({ error: "Missing purchaseToken" }), { status: 400 });
    }

    const supabase = serviceRoleClient();

    // Verify the caller, same pattern as delete-account: resolve the
    // Supabase Auth user from the bearer token, then look up their
    // store via store_members (the real auth_user_id -> store_id
    // link -- stores has no owner_id column).
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Invalid auth token" }), { status: 401 });
    }

    const { data: membership, error: membershipError } = await supabase
      .from("store_members")
      .select("store_id")
      .eq("auth_user_id", userData.user.id)
      .maybeSingle();

    if (membershipError) {
      console.error("verify-purchase store_members lookup error:", membershipError.message);
      return new Response(JSON.stringify({ error: "Could not resolve store for user" }), { status: 500 });
    }
    if (!membership) {
      return new Response(JSON.stringify({ error: "No store found for user" }), { status: 404 });
    }

    // Source of truth: ask Google directly rather than trusting
    // anything the client sent about plan/state.
    const purchase = await getSubscription(purchaseToken);

    // A valid Google token only proves someone paid, not that THIS
    // store did -- see canStoreClaimPurchase. Checked before
    // acknowledging or writing anything so a refused claim changes
    // nothing.
    const mayClaim = await canStoreClaimPurchase(
      supabase,
      membership.store_id,
      purchaseToken,
      purchase,
    );
    if (!mayClaim) {
      return new Response(
        JSON.stringify({ error: "This subscription is already linked to another store." }),
        { status: 409, headers: { "Content-Type": "application/json" } },
      );
    }

    if (purchase.acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING") {
      // Must acknowledge within 3 days or Play auto-refunds. Doing
      // this here (not in rtdn-webhook) since verify-purchase is the
      // very first time we see a brand-new purchase.
      await acknowledgeSubscription(purchaseToken);
    }

    await applySubscriptionState(supabase, membership.store_id, purchaseToken, purchase);

    return new Response(
      JSON.stringify({ success: true, subscriptionState: purchase.subscriptionState }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("verify-purchase unhandled exception:", err instanceof Error ? err.stack : err);
    return new Response(
      JSON.stringify({ error: "verify-purchase failed", detail: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
