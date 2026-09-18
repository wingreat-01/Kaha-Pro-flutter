// Deploy with: supabase functions deploy confirm-account-deletion --no-verify-jwt
//
// Called from confirm-delete.html when the user clicks the emailed link.
// Possession of a valid, unexpired, unused token IS the authentication
// here — that's the whole point of emailing it to the account's own
// address first.
//
// IMPORTANT: this explicitly deletes every table's rows for the user's
// store(s), rather than relying on ON DELETE CASCADE from auth.users.
// That's deliberate — stores.id has no foreign key pointing at
// auth.users (ownership is tracked via store_members instead), so
// deleting the auth user alone never reaches the store, its products,
// its transactions, etc. Confirmed by testing: the auth login was gone
// but the stores row was still sitting there untouched.
//
// Deletion always wipes the ENTIRE store the account belongs to,
// regardless of whether the account is an owner or staff member — this
// matches the current single-owner testing setup. If MERQ later
// supports multiple staff logins per store in production, revisit this:
// you likely don't want one staff member deleting their own account to
// also delete the owner's whole store out from under them.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(supabaseUrl, serviceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// Deletes everything belonging to a single store, in dependency order
// (children before parents), then the store row itself. Each step is
// logged and wrapped so a schema mismatch on one table doesn't abort
// the whole cleanup — better to delete what we can and log the rest
// than leave everything in place on one unexpected error.
async function deleteStoreData(storeId: string) {
  const steps: Array<{ label: string; run: () => Promise<{ error: any }> }> = [
    {
      label: "transaction_line_items (via this store's transactions)",
      run: async () => {
        const { data: txRows } = await supabase
          .from("transactions")
          .select("id")
          .eq("store_id", storeId);
        const txIds = (txRows ?? []).map((t: any) => t.id);
        if (txIds.length === 0) return { error: null };
        return await supabase.from("transaction_line_items").delete().in("transaction_id", txIds);
      },
    },
    { label: "transactions", run: () => supabase.from("transactions").delete().eq("store_id", storeId) },
    {
      label: "ingredient_stock_movements",
      run: () => supabase.from("ingredient_stock_movements").delete().eq("store_id", storeId),
    },
    {
      label: "product_recipe_items (via this store's products)",
      run: async () => {
        const { data: productRows } = await supabase
          .from("products")
          .select("id")
          .eq("store_id", storeId);
        const productIds = (productRows ?? []).map((p: any) => p.id);
        if (productIds.length === 0) return { error: null };
        return await supabase.from("product_recipe_items").delete().in("product_id", productIds);
      },
    },
    {
      label: "product_variants (via this store's products)",
      run: async () => {
        const { data: productRows } = await supabase
          .from("products")
          .select("id")
          .eq("store_id", storeId);
        const productIds = (productRows ?? []).map((p: any) => p.id);
        if (productIds.length === 0) return { error: null };
        return await supabase.from("product_variants").delete().in("product_id", productIds);
      },
    },
    { label: "purchase_verifications", run: () => supabase.from("purchase_verifications").delete().eq("store_id", storeId) },
    { label: "products", run: () => supabase.from("products").delete().eq("store_id", storeId) },
    { label: "ingredients", run: () => supabase.from("ingredients").delete().eq("store_id", storeId) },
    { label: "categories", run: () => supabase.from("categories").delete().eq("store_id", storeId) },
    { label: "payment_methods", run: () => supabase.from("payment_methods").delete().eq("store_id", storeId) },
    { label: "staff_users", run: () => supabase.from("staff_users").delete().eq("store_id", storeId) },
    { label: "store_counters", run: () => supabase.from("store_counters").delete().eq("store_id", storeId) },
    { label: "store_members", run: () => supabase.from("store_members").delete().eq("store_id", storeId) },
    { label: "stores", run: () => supabase.from("stores").delete().eq("id", storeId) },
  ];

  for (const step of steps) {
    try {
      const { error } = await step.run();
      if (error) {
        console.error(`Cleanup step failed [${step.label}] for store ${storeId}:`, error);
      } else {
        console.log(`Cleanup step OK [${step.label}] for store ${storeId}`);
      }
    } catch (err) {
      console.error(`Cleanup step threw [${step.label}] for store ${storeId}:`, err);
    }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const { token } = await req.json();

    if (!token || typeof token !== "string") {
      return jsonResponse({ error: "Missing confirmation token" }, 400);
    }

    const { data: request, error: findErr } = await supabase
      .from("account_deletion_requests")
      .select("*")
      .eq("token", token)
      .is("used_at", null)
      .single();

    if (findErr || !request) {
      return jsonResponse({ error: "This link is invalid or has already been used." }, 400);
    }

    if (new Date(request.expires_at) < new Date()) {
      return jsonResponse({ error: "This link has expired. Please request deletion again." }, 400);
    }

    // Mark used BEFORE deleting anything, so a double-click or network
    // retry can't trigger this twice.
    await supabase
      .from("account_deletion_requests")
      .update({ used_at: new Date().toISOString() })
      .eq("id", request.id);

    // Find every store this account belongs to and wipe each one
    // completely, table by table, before touching the auth user itself.
    const { data: memberRows, error: memberErr } = await supabase
      .from("store_members")
      .select("store_id")
      .eq("auth_user_id", request.user_id);

    if (memberErr) {
      console.error("Failed to look up store memberships", memberErr);
    }

    const storeIds = [...new Set((memberRows ?? []).map((m: any) => m.store_id))];

    for (const storeId of storeIds) {
      await deleteStoreData(storeId);
    }

    // Now delete the auth user itself. Any remaining store_members rows
    // for this user (e.g. if the store lookup above found nothing) are
    // cleaned up here too, if that FK cascade is in place — a harmless
    // no-op otherwise since we already deleted them per-store above.
    const { error: deleteErr } = await supabase.auth.admin.deleteUser(request.user_id);

    if (deleteErr) {
      console.error("Failed to delete auth user", deleteErr);
      return jsonResponse(
        {
          error:
            "Your store data was removed, but something went wrong deleting your login. Please contact merq@prohubapps.com so we can finish this manually.",
        },
        500,
      );
    }

    return jsonResponse(
      { message: "Your MERQ account, store, and all associated data have been permanently deleted." },
      200,
    );
  } catch (err) {
    console.error(err);
    return jsonResponse({ error: "Something went wrong" }, 500);
  }
});
