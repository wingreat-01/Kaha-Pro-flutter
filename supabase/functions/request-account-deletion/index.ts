// Deploy with: supabase functions deploy request-account-deletion --no-verify-jwt
//
// --no-verify-jwt is required because this is called from a public web
// page with no logged-in Supabase session — there's no user JWT to check.
// Security instead comes from: (1) requiring the token be emailed to the
// account's real address before anything happens, and (2) always
// returning the same generic response so this endpoint can't be used to
// probe which emails have MERQ accounts.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const resendApiKey = Deno.env.get("RESEND_API_KEY")!;
const siteUrl = Deno.env.get("SITE_URL") ?? "https://merq.prohubapps.com";

const supabase = createClient(supabaseUrl, serviceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function genericResponse() {
  return new Response(
    JSON.stringify({
      message: "If that email matches a MERQ account, a confirmation link has been sent.",
    }),
    { status: 200, headers: { "Content-Type": "application/json", ...corsHeaders } },
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const { email, storeName } = await req.json();

    if (!email || typeof email !== "string" || !email.includes("@")) {
      return new Response(JSON.stringify({ error: "A valid email is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    // Look up the user by email. listUsers() is paginated at 50 by
    // default — bump perPage if MERQ's user base ever exceeds that.
    const { data: userList, error: userErr } = await supabase.auth.admin.listUsers({
      perPage: 1000,
    });

    if (userErr) {
      console.error("listUsers error", userErr);
      return genericResponse();
    }

    const user = userList.users.find(
      (u) => u.email?.toLowerCase() === email.toLowerCase(),
    );

    if (!user) {
      return genericResponse(); // don't reveal whether the email exists
    }

    // Optional extra check: if a store name was provided, only proceed
    // if it actually matches a store this user belongs to. Silently
    // falls through to the generic response on mismatch, same as a
    // non-existent email — no hint given either way.
    if (storeName) {
      const { data: memberRows } = await supabase
        .from("store_members")
        .select("stores(name)")
        .eq("auth_user_id", user.id);

      const matches = memberRows?.some(
        (m: any) =>
          m.stores?.name?.toLowerCase().trim() === String(storeName).toLowerCase().trim(),
      );

      if (!matches) {
        return genericResponse();
      }
    }

    const token = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString(); // 1 hour

    const { error: insertErr } = await supabase.from("account_deletion_requests").insert({
      user_id: user.id,
      email: user.email,
      token,
      expires_at: expiresAt,
    });

    if (insertErr) {
      console.error("insert error", insertErr);
      return genericResponse();
    }

    const confirmUrl = `${siteUrl}/confirm-delete.html?token=${token}`;

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "MERQ POS <noreply@merq.prohubapps.com>",
        to: user.email,
        subject: "Confirm your MERQ account deletion",
        html: `
          <p>We received a request to permanently delete your MERQ account and all associated store data (products, staff accounts, transaction history).</p>
          <p><a href="${confirmUrl}">Click here to confirm deletion</a></p>
          <p>This link expires in 1 hour and can only be used once. If you didn't request this, you can safely ignore this email — nothing will happen without you clicking the link.</p>
        `,
      }),
    });

    if (!emailRes.ok) {
      console.error("Resend send failed", await emailRes.text());
      // Still return the generic success response — we don't want to
      // leak send failures to the caller either.
    }

    return genericResponse();
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: "Something went wrong" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
