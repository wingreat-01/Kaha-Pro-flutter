-- =============================================================
-- KahaPro: Customizable Payment Methods
-- Migration: create payment_methods table + RLS
-- =============================================================

-- 1. TABLE ------------------------------------------------------
create table if not exists payment_methods (
  id           uuid primary key default gen_random_uuid(),
  store_id     uuid not null references stores(id) on delete cascade,
  name         text not null,
  is_active    boolean not null default true,
  sort_order   int not null default 0,
  created_at   timestamptz not null default now(),

  -- prevent an owner from creating "GCash" twice in the same store
  constraint payment_methods_unique_name_per_store unique (store_id, name)
);

comment on table payment_methods is
  'Store-configurable payment methods (Cash, GCash, Maya, etc.), same role Categories play for products.';

-- helpful index for the checkout-selector query (active methods, ordered)
create index if not exists idx_payment_methods_store_active_sort
  on payment_methods (store_id, is_active, sort_order);


-- 2. LINK TRANSACTIONS TO A PAYMENT METHOD ----------------------
-- Nullable for now so existing rows aren't broken; backfill separately.
alter table transactions
  add column if not exists payment_method_id uuid references payment_methods(id);

create index if not exists idx_transactions_payment_method
  on transactions (payment_method_id);


-- 3. RLS ----------------------------------------------------------
alter table payment_methods enable row level security;

-- READ: any authenticated session (owner or PIN-gated staff sharing the
-- owner's auth session) scoped to their own store can see payment methods.
create policy payment_methods_select
  on payment_methods
  for select
  to authenticated
  using (store_id = current_store_id());

-- INSERT / UPDATE / DELETE: same store scoping.
-- NOTE: if you want this restricted to the owner only (not staff), add
--   and exists (select 1 from stores s where s.id = store_id and s.owner_id = auth.uid())
-- once you confirm the actual owner-vs-staff role check used elsewhere
-- (staff currently share the owner's Auth session per your Phase C model,
-- so store_id scoping is the same boundary Categories/Products already use).
create policy payment_methods_insert
  on payment_methods
  for insert
  to authenticated
  with check (store_id = current_store_id());

create policy payment_methods_update
  on payment_methods
  for update
  to authenticated
  using (store_id = current_store_id())
  with check (store_id = current_store_id());

create policy payment_methods_delete
  on payment_methods
  for delete
  to authenticated
  using (store_id = current_store_id());


-- 4. SEED DEFAULTS ON NEW STORE SIGNUP ----------------------------
-- Add this block into your existing handle_new_user() trigger function
-- (the one that already auto-provisions the store on signup), so every
-- new store starts with sensible PH defaults instead of an empty list.
--
-- Example addition — merge into your real handle_new_user() body,
-- using whatever variable holds the newly-created store's id there:
--
-- insert into payment_methods (store_id, name, sort_order) values
--   (new_store_id, 'Cash', 0),
--   (new_store_id, 'GCash', 1),
--   (new_store_id, 'Maya', 2),
--   (new_store_id, 'Bank Transfer', 3);


-- 5. BACKFILL EXISTING STORES (run once, after deploying) --------
-- Every store that existed before this migration has zero payment
-- methods. This inserts the same defaults for all of them.
insert into payment_methods (store_id, name, sort_order)
select s.id, v.name, v.sort_order
from stores s
cross join (values
  ('Cash', 0),
  ('GCash', 1),
  ('Maya', 2),
  ('Bank Transfer', 3)
) as v(name, sort_order)
where not exists (
  select 1 from payment_methods pm where pm.store_id = s.id
);
