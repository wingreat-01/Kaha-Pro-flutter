// supabase/functions/delete-account/index.ts
//
// Deletes the calling user's account: their entire store and everything
// in it (single-owner-per-store model -- there is no "other members keep
// the store" case), then the auth.users row itself.
//
// Order of operations, and why:
//   1. Verify the caller's JWT (never trust a client-supplied user id).
//   2. Look up their store (owner_id = user.id).
//   3. Run delete_account_cascade(store_id) -- one atomic transaction that
//      removes every app-data row. See the migration file for the exact
//      per-table order and reasoning.
//   4. Only once app data is confirmed gone, delete the auth user via the
//      Admin API. Doing it in this order means a failure at step 4 just
//      leaves a login with no data behind it (annoying, retryable) rather
//      than the reverse -- a deleted login with orphaned business data
//      nobody can ever ask to remove again.
//
// Called from delete_account_screen.dart via functions.invoke('delete-account'),
// which attaches the caller's access token as the Authorization header
// automatically.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header." }, 401);
    }

    // Verify the caller using their own token -- this is what proves who
    // is actually asking, independent of anything the client body claims.
    const callerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await callerClient.auth.getUser();

    if (userError || !user) {
      return json({ error: "Could not verify your session. Please sign in again." }, 401);
    }

    // Everything from here runs with the service role: RLS on `stores`
    // would otherwise be fine for the owner's own row, but the RPC
    // itself needs it regardless, so use one privileged client
    // consistently rather than mixing caller-scoped and service-role calls.
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: membership, error: membershipError } = await adminClient
      .from("store_members")
      .select("store_id")
      .eq("auth_user_id", user.id)
      .maybeSingle();

    if (membershipError) {
      console.error("store_members lookup failed:", membershipError);
      return json({ error: "Could not look up your store. Please try again." }, 500);
    }

    // A store-less auth user shouldn't be possible in normal flow, but if
    // it happens (e.g. abandoned onboarding), just fall through to deleting
    // the auth user -- there's no store data to clean up.
    if (membership) {
      const { error: cascadeError } = await adminClient.rpc("delete_account_cascade", {
        p_store_id: membership.store_id,
      });

      if (cascadeError) {
        console.error("delete_account_cascade failed:", cascadeError);
        return json(
          { error: "Could not delete your data. Nothing was removed -- please try again or contact support." },
          500,
        );
      }
    }

    const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(user.id);

    if (deleteUserError) {
      console.error("auth.admin.deleteUser failed after data was already removed:", deleteUserError);
      // Data is already gone at this point -- tell the truth about that
      // rather than implying nothing happened.
      return json(
        {
          error:
            "Your data was deleted, but we couldn't remove your login. Contact support and we'll finish that manually.",
        },
        500,
      );
    }

    return json({ success: true });
  } catch (err) {
    // Anything that throws rather than returning {error} (a genuine JS
    // exception -- bad input, an unexpected null, a network-level
    // failure) previously killed the isolate silently (visible only as
    // an "EarlyDrop" shutdown with no application log line). Catching
    // it here guarantees the real message and stack always show up in
    // the Logs tab instead of leaving a 500 with no explanation.
    console.error("delete-account unhandled exception:", err instanceof Error ? err.stack ?? err.message : err);
    return json({ error: "Something went wrong. Please try again or contact support." }, 500);
  }
});
