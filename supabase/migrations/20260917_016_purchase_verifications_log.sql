-- 20260917_016_purchase_verifications_log.sql
--
-- Records every purchase verify-purchase successfully processes,
-- tagged is_test_purchase from Google's own testPurchase field on the
-- subscriptionsv2.get response -- lets the owner tell a License
-- Tester's unpaid test purchase apart from a real paying subscriber
-- by querying this table, since stores.plan itself carries no such
-- flag (same value either way, by design -- see the chat decision
-- that testers go through the identical flow).
--
-- Purchase tokens are not stored in plain text -- they're long-lived
-- credentials tied to a real purchase, so this stores only a sha256
-- hash of the token (for idempotency / "have we seen this token
-- before" checks) plus Google's own order_id, which is already
-- visible to the store owner in their Play Console payments dashboard
-- and isn't a secret the way the raw token is.
create table if not exists public.purchase_verifications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  product_id text not null,
  plan text not null,
  subscription_state text not null,
  is_test_purchase boolean not null,
  order_id text,
  purchase_token_hash text not null,
  verified_at timestamptz not null default now()
);

create index if not exists purchase_verifications_store_id_idx
  on public.purchase_verifications (store_id, verified_at desc);

-- Lets a query filter "show me only test purchases" or "only real
-- ones" quickly without scanning the whole table.
create index if not exists purchase_verifications_is_test_idx
  on public.purchase_verifications (is_test_purchase);

alter table public.purchase_verifications enable row level security;

-- Store-scoped read access, same pattern as ai_usage_log -- an owner
-- can see their own store's purchase history if a future Settings
-- screen ever surfaces it, even though nothing reads this yet.
create policy "purchase_verifications_select_own_store"
  on public.purchase_verifications for select
  using (store_id = current_store_id());

-- No insert/update/delete policies for authenticated users -- only
-- ever written by verify-purchase, which uses the service role key
-- and bypasses RLS entirely, same as ai_usage_log.

-- For account deletion: add this table to delete_account_cascade's
-- teardown, same treatment as ai_usage_log (no cascade from stores,
-- must be cleared explicitly). Re-running CREATE OR REPLACE on the
-- existing function -- see 20260912_013's delete_account_cascade for
-- the full ordered list this is joining.
create or replace function public.delete_account_cascade(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.ai_usage_log where store_id = p_store_id;
  delete from public.purchase_verifications where store_id = p_store_id;

  delete from public.product_recipe_items
  where ingredient_id in (select id from public.ingredients where store_id = p_store_id)
     or product_variant_id in (select id from public.product_variants where store_id = p_store_id);

  delete from public.transactions where store_id = p_store_id;
  delete from public.product_variants where store_id = p_store_id;
  delete from public.products where store_id = p_store_id;

  update public.categories set is_protected = false where store_id = p_store_id and is_protected;
  delete from public.categories where store_id = p_store_id;

  delete from public.payment_methods where store_id = p_store_id;
  delete from public.ingredients where store_id = p_store_id;
  delete from public.staff_users where store_id = p_store_id;
  delete from public.store_counters where store_id = p_store_id;
  delete from public.stores where id = p_store_id;
end;
$$;

revoke all on function public.delete_account_cascade(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_cascade(uuid) to service_role;
