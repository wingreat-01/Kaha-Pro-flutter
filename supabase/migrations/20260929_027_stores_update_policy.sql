-- 027: let store members UPDATE their own `stores` row, but only the
-- settings columns the Flutter app writes.
--
-- Why: `stores` only had a SELECT policy ("member can view own store"),
-- so every client-side UPDATE matched zero rows and failed silently
-- (Store Details, Senior/PWD toggle, receipt printing, QR payments).
--
-- Plan / trial / AI-credit columns are deliberately NOT granted, so a
-- signed-in user can't edit them from the client. Those must be changed
-- server-side (service role, edge function or security-definer RPC).

-- 1. Row-level: only the caller's own store row
drop policy if exists "member can update own store" on public.stores;

create policy "member can update own store"
on public.stores
for update
to authenticated
using (id = current_store_id())
with check (id = current_store_id());

-- 2. Column-level: restrict which columns can be written from the client
revoke update on public.stores from anon, authenticated;

grant update (
  name,
  address,
  receipt_footer,
  tin,
  contact_number,
  permit_number,
  senior_pwd_discount_enabled,
  receipt_printing_enabled,
  qr_pay_counter_enabled,
  qr_pay_online_enabled,
  online_payment_qr_url,
  online_payment_instructions
) on public.stores to authenticated;

-- 3. Verify (run separately):
--   select policyname, cmd, roles, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'stores';
--
--   select grantee, column_name, privilege_type
--   from information_schema.column_privileges
--   where table_schema = 'public' and table_name = 'stores'
--     and privilege_type = 'UPDATE' and grantee = 'authenticated'
--   order by column_name;
