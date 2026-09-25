// supabase/functions/confirm-account-deletion/index.ts
// Deploy with: supabase functions deploy confirm-account-deletion --no-verify-jwt
//
// Called from confirm-delete.html when the user presses the confirm button.
// Possession of a valid, unexpired, unused token IS the authentication
// here: that's the whole point of emailing it to the account's own
// address first.
//
// Store data is removed by the delete_account_cascade(store_id) SQL
// function: one atomic transaction that deletes every table in the right
// order (including un-protecting categories so the "protected fallback
// category" trigger doesn't block the delete). If it fails, nothing is
// removed and the token is freed so the link can be retried.
//
// The auth user is deleted only AFTER every store's data is gone. Deleting
// the login first would cascade away store_members and leave the store
// orphaned with no owner.
//
// Deletion wipes the ENTIRE store the account belongs to, regardless of
// whether the account is an owner or staff member. This matches the
// current single-owner setup. If MERQ later supports multiple logins per
// store, revisit this.

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

// Puts the token back into a usable state so the emailed link can be retried.
async function freeToken(requestId: string) {
  const { error } = await supabase
    .from("account_deletion_requests")
    .update({ used_at: null })
    .eq("id", requestId);
  if (error) console.error("Failed to free token for retry", error);
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
    // retry can't trigger this twice. It is freed again below if the
    // deletion fails.
    await supabase
      .from("account_deletion_requests")
      .update({ used_at: new Date().toISOString() })
      .eq("id", request.id);

    const { data: memberRows, error: memberErr } = await supabase
      .from("store_members")
      .select("store_id")
      .eq("auth_user_id", request.user_id);

    if (memberErr) {
      // Abort: deleting the login would cascade away store_members
      // and orphan the store for good.
      console.error("Failed to look up store memberships", memberErr);
      await freeToken(request.id);
      return jsonResponse({ error: "Could not look up your store. Please try again." }, 500);
    }

    const storeIds = [...new Set((memberRows ?? []).map((m: any) => m.store_id))];

    for (const storeId of storeIds) {
      const { error: cascadeError } = await supabase.rpc("delete_account_cascade", {
        p_store_id: storeId,
      });
      if (cascadeError) {
        console.error(`delete_account_cascade failed for store ${storeId}:`, cascadeError);
        await freeToken(request.id);
        return jsonResponse(
          { error: "Could not delete your data. Please try again or contact merq@prohubapps.com." },
          500,
        );
      }
      console.log(`delete_account_cascade OK for store ${storeId}`);
    }

    // Every store's data is gone; now remove the login itself.
    const { error: deleteErr } = await supabase.auth.admin.deleteUser(request.user_id);

    if (deleteErr) {
      console.error("Failed to delete auth user after data was removed", deleteErr);
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
    console.error("confirm-account-deletion unhandled exception:", err instanceof Error ? err.stack ?? err.message : err);
    return jsonResponse({ error: "Something went wrong" }, 500);
  }
});
