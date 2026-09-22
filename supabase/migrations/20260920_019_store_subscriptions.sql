-- 20260920_019_store_subscriptions.sql
--
-- verify-purchase confirms a purchase at the moment the user taps
-- Upgrade, but Play's Real-time Developer Notifications (RTDN) fire
-- later, asynchronously, for renewals/cancellations/expiries -- and
-- the only thing in that webhook payload is a purchase token. There
-- is nowhere else to look up "which store does this token belong to."
--
-- This table is that lookup: purchase_token_hash -> store_id, plus
-- enough of the last-known subscription state that rtdn-webhook can
-- decide whether to re-grant or revoke access without always having
-- to round-trip Google's API first (it still will, for the source of
-- truth, but this gives a fast local read for logging/debugging).
--
-- Same privacy treatment as purchase_verifications (20260917_016):
-- the raw purchase token is a long-lived credential, so only a sha256
-- hash of it is stored, never the token itself.
create table if not exists public.store_subscriptions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  purchase_token_hash text not null unique,
  product_id text not null,
  plan text not null,
  subscription_state text not null,
  latest_order_id text,
  expiry_time timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- rtdn-webhook's first and only lookup key: given a token hash from
-- the notification payload, find the store to act on.
create index if not exists store_subscriptions_token_hash_idx
  on public.store_subscriptions (purchase_token_hash);

create index if not exists store_subscriptions_store_id_idx
  on public.store_subscriptions (store_id);

alter table public.store_subscriptions enable row level security;

-- Store-scoped read access, same pattern as purchase_verifications --
-- an owner can see their own store's subscription record if a future
-- Settings screen surfaces it, even though nothing reads this yet.
create policy "store_subscriptions_select_own_store"
  on public.store_subscriptions for select
  using (store_id = current_store_id());

-- No insert/update/delete policies for authenticated users -- only
-- ever written by verify-purchase / rtdn-webhook via the shared
-- applySubscriptionState() writer, which uses the service role key
-- and bypasses RLS entirely, same as purchase_verifications.

-- Account deletion: this table has no cascade from stores (same
-- reasoning as ai_usage_log and purchase_verifications), so it must
-- be cleared explicitly. Re-running CREATE OR REPLACE on the existing
-- function -- joining the ordered teardown list from 20260917_016.
create or replace function public.delete_account_cascade(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.ai_usage_log where store_id = p_store_id;
  delete from public.purchase_verifications where store_id = p_store_id;
  delete from public.store_subscriptions where store_id = p_store_id;

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
