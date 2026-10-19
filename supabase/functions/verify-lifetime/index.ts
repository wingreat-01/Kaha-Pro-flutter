// verify-lifetime: verifies a one-time "Lifetime" Google Play purchase and
// sets stores.plan = 'lifetime'. Separate from verify-purchase (subscriptions).
//
// Secrets (same as verify-purchase): GOOGLE_SERVICE_ACCOUNT_JSON, ANDROID_PACKAGE_NAME
// Optional: LIFETIME_PRODUCT_ID (default "merq_lifetime")
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const LIFETIME_PRODUCT_ID = Deno.env.get("LIFETIME_PRODUCT_ID") ?? "merq_lifetime";
const PACKAGE_NAME = Deno.env.get("ANDROID_PACKAGE_NAME") ?? "";
const SERVICE_ACCOUNT_JSON = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? "";
const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

async function googleAccessToken(): Promise<string> {
  const sa = JSON.parse(SERVICE_ACCOUNT_JSON);
  const key = await importPKCS8(sa.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/androidpublisher" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(data)}`);
  }
  return data.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    if (!PACKAGE_NAME || !SERVICE_ACCOUNT_JSON) {
      console.error("verify-lifetime: missing ANDROID_PACKAGE_NAME or GOOGLE_SERVICE_ACCOUNT_JSON");
      return json({ error: "Server is not configured for purchases yet." }, 500);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1) Who is calling?
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not signed in." }, 401);
    const user = userData.user;

    // 2) What are they claiming?
    const body = await req.json().catch(() => ({}));
    const productId = String(body.productId ?? "");
    const purchaseToken = String(body.purchaseToken ?? "");
    if (!purchaseToken) return json({ error: "Missing purchaseToken." }, 400);
    if (productId !== LIFETIME_PRODUCT_ID) return json({ error: "Unknown product." }, 400);

    // 3) Which store? Only the owner can buy for it.
    const { data: members, error: memErr } = await admin
      .from("store_members")
      .select("store_id, role")
      .eq("auth_user_id", user.id);
    if (memErr) {
      console.error("verify-lifetime: store_members lookup failed", memErr);
      return json({ error: "Could not find your store." }, 500);
    }
    const owner = (members ?? []).find((m) => m.role === "owner");
    if (!owner) return json({ error: "Only the store owner can buy Lifetime." }, 403);
    const storeId = owner.store_id as string;

    // 4) Ask Google whether this purchase is real.
    const accessToken = await googleAccessToken();
    const auth = { Authorization: `Bearer ${accessToken}` };
    const getRes = await fetch(
      `${API}/${PACKAGE_NAME}/purchases/productsv2/tokens/${encodeURIComponent(purchaseToken)}`,
      { headers: auth },
    );
    const purchase = await getRes.json();
    if (!getRes.ok) {
      console.error("verify-lifetime: productsv2.get failed", getRes.status, purchase);
      return json({ error: "Google could not confirm this purchase." }, 400);
    }

    const state = purchase?.purchaseStateContext?.purchaseState;
    if (state !== "PURCHASED") {
      return json({ error: state === "PENDING" ? "Payment is still pending." : "Purchase is not active." }, 400);
    }
    const hasProduct = (purchase?.productLineItem ?? []).some(
      (li: { productId?: string }) => li.productId === LIFETIME_PRODUCT_ID,
    );
    if (!hasProduct) return json({ error: "Purchase is for a different product." }, 400);

    // 5) Acknowledge within 3 days or Google refunds it. The app may have
    //    already acknowledged client-side, in which case this is skipped.
    if (purchase.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") {
      const ackRes = await fetch(
        `${API}/${PACKAGE_NAME}/purchases/products/${LIFETIME_PRODUCT_ID}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`,
        { method: "POST", headers: { ...auth, "Content-Type": "application/json" }, body: "{}" },
      );
      if (!ackRes.ok) {
        console.error("verify-lifetime: acknowledge failed", ackRes.status, await ackRes.text());
        return json({ error: "Could not finalize the purchase. Please try again." }, 502);
      }
    }

    // 6) One purchase token may only ever unlock one store.
    const { data: existing } = await admin
      .from("lifetime_purchases")
      .select("store_id, refunded_at")
      .eq("purchase_token", purchaseToken)
      .maybeSingle();
    if (existing?.refunded_at) {
      return json({ error: "This purchase was refunded." }, 400);
    }
    if (existing && existing.store_id !== storeId) {
      return json({ error: "This purchase is already linked to another store." }, 409);
    }
    if (!existing) {
      const { error: insErr } = await admin.from("lifetime_purchases").insert({
        purchase_token: purchaseToken,
        store_id: storeId,
        auth_user_id: user.id,
        product_id: LIFETIME_PRODUCT_ID,
        is_test: purchase?.testPurchaseContext != null,
      });
      if (insErr) {
        console.error("verify-lifetime: insert lifetime_purchases failed", insErr);
        return json({ error: "Could not record the purchase." }, 500);
      }
    }

    // 7) Unlock.
    const { error: updErr } = await admin
      .from("stores")
      .update({ plan: "lifetime", plan_expires_at: null })
      .eq("id", storeId);
    if (updErr) {
      console.error("verify-lifetime: stores update failed", updErr);
      return json({ error: "Purchase verified but the plan could not be updated. Contact support." }, 500);
    }

    // Give the new plan's AI credits right away (ai_credit_allotment knows
    // 'lifetime' after migration 023). Not fatal: the plan is already
    // unlocked, so a failure here is logged instead of failing the purchase.
    const { error: creditsErr } = await admin.rpc("grant_plan_credits", { p_store_id: storeId });
    if (creditsErr) {
      console.error("verify-lifetime: grant_plan_credits failed", creditsErr);
    }

    return json({ ok: true, plan: "lifetime" });
  } catch (err) {
    console.error("verify-lifetime unhandled exception", err instanceof Error ? err.stack : err);
    return json({ error: "Something went wrong verifying your purchase." }, 500);
  }
});
