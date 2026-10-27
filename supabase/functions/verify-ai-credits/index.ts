// verify-ai-credits: verifies a one-time "AI credits" pack purchase from
// Google Play, adds the credits to stores.ai_credits_bonus, then consumes
// the purchase at Google so the pack can be bought again.
//
// Secrets (same as verify-lifetime): GOOGLE_SERVICE_ACCOUNT_JSON, ANDROID_PACKAGE_NAME
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Play product ID -> credits per unit. Add more pack sizes here.
const PACK_CREDITS: Record<string, number> = {
  merq_ai_credits_50: 50,
};

const PACKAGE_NAME = Deno.env.get("ANDROID_PACKAGE_NAME") ?? "";
const SERVICE_ACCOUNT_JSON = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON") ?? "";
const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

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
      console.error("verify-ai-credits: missing ANDROID_PACKAGE_NAME or GOOGLE_SERVICE_ACCOUNT_JSON");
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
    const perUnit = PACK_CREDITS[productId];
    if (!perUnit) return json({ error: "Unknown product." }, 400);

    // 3) Which store? Only the owner can buy for it.
    const { data: members, error: memErr } = await admin
      .from("store_members")
      .select("store_id, role")
      .eq("auth_user_id", user.id);
    if (memErr) {
      console.error("verify-ai-credits: store_members lookup failed", memErr);
      return json({ error: "Could not find your store." }, 500);
    }
    const owner = (members ?? []).find((m) => m.role === "owner");
    if (!owner) return json({ error: "Only the store owner can buy AI credits." }, 403);
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
      console.error("verify-ai-credits: productsv2.get failed", getRes.status, purchase);
      return json({ error: "Google could not confirm this purchase." }, 400);
    }

    const state = purchase?.purchaseStateContext?.purchaseState;
    if (state !== "PURCHASED") {
      return json({ error: state === "PENDING" ? "Payment is still pending." : "Purchase is not active." }, 400);
    }
    const lineItem = (purchase?.productLineItem ?? []).find(
      (li: { productId?: string }) => li.productId === productId,
    );
    if (!lineItem) return json({ error: "Purchase is for a different product." }, 400);

    // Credits = pack size x quantity (quantity is 1 unless multi-quantity is
    // turned on for the product in Play Console).
    const quantity = Math.max(1, Number(lineItem?.productOfferDetails?.quantity ?? 1));
    const credits = perUnit * quantity;
    const tokenHash = await sha256Hex(purchaseToken);

    // 5) Grant once. Safe to call again with the same token (returns false).
    const { data: granted, error: grantErr } = await admin.rpc("add_ai_credits", {
      p_store_id: storeId,
      p_token_hash: tokenHash,
      p_product_id: productId,
      p_credits: credits,
      p_is_test: purchase?.testPurchaseContext != null,
    });
    if (grantErr) {
      console.error("verify-ai-credits: add_ai_credits failed", grantErr);
      const linked = String(grantErr.message ?? "").includes("purchase_linked_to_another_store");
      return json(
        { error: linked ? "This purchase is already linked to another store." : "Could not add the credits." },
        linked ? 409 : 500,
      );
    }

    // 6) Consume at Google so the pack can be bought again. Done even when
    //    the credits were granted earlier, to finish a consume that failed
    //    last time. A failure here is not fatal: the credits are already
    //    added, and the next restore/verify retries the consume.
    const consumption = lineItem?.productOfferDetails?.consumptionState;
    if (consumption !== "CONSUMPTION_STATE_CONSUMED") {
      const consumeRes = await fetch(
        `${API}/${PACKAGE_NAME}/purchases/products/${productId}/tokens/${encodeURIComponent(purchaseToken)}:consume`,
        { method: "POST", headers: { ...auth, "Content-Type": "application/json" }, body: "{}" },
      );
      if (!consumeRes.ok) {
        console.error("verify-ai-credits: consume failed", consumeRes.status, await consumeRes.text());
      }
    }

    return json({ ok: true, granted: granted === true, credits_added: granted === true ? credits : 0 });
  } catch (err) {
    console.error("verify-ai-credits unhandled exception", err instanceof Error ? err.stack : err);
    return json({ error: "Something went wrong verifying your purchase." }, 500);
  }
});
