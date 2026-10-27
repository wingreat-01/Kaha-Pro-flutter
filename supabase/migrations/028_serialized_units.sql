-- 028_serialized_units.sql
-- Batch-add products where every physical unit has its own barcode
-- (e.g. 10 x "Ingco Wireless Drill", each with a different serial barcode).
-- Run AFTER 027_barcode_scanner.sql. The app tolerates this table being
-- missing (unit scanning just stays empty), but products.track_units is
-- read on every product load, so run the whole file before shipping.
--
-- ASSUMPTION: your helper current_store_id() (used by your other RLS
-- policies) exists, and products/etc. get store_id the same way.

alter table public.products
  add column if not exists track_units boolean not null default false;

create table if not exists public.product_units (
  id          uuid primary key default gen_random_uuid(),
  store_id    uuid not null default public.current_store_id()
              references public.stores(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  barcode     text not null check (length(barcode) between 1 and 64),
  status      text not null default 'in_stock' check (status in ('in_stock', 'sold')),
  created_at  timestamptz not null default now(),
  sold_at     timestamptz
);

-- A unit barcode is unique within a store.
create unique index if not exists product_units_store_barcode_key
  on public.product_units (store_id, barcode);
create index if not exists product_units_product_idx
  on public.product_units (product_id, status);

alter table public.product_units enable row level security;

drop policy if exists "store scoped access" on public.product_units;
create policy "store scoped access" on public.product_units
  for all
  using (store_id = public.current_store_id())
  with check (store_id = public.current_store_id());

grant select, insert, update, delete on public.product_units to authenticated;
