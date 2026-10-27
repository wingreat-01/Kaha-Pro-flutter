-- 027_barcode_scanner.sql
-- Optional barcode scanning for Retail stores.
-- RUN THIS BEFORE shipping the new Dart code: StoreProvider.loadFromSupabase()
-- now selects stores.barcode_scanner_enabled, so the store would fail to load
-- if the column doesn't exist yet.

-- 1) Per-store switch (Settings -> Barcode Scanner). Off by default.
alter table public.stores
  add column if not exists barcode_scanner_enabled boolean not null default false;

-- 2) Optional barcode on each product.
alter table public.products
  add column if not exists barcode text;

-- 3) A barcode can belong to only one product within a store
--    (many products can have no barcode at all).
create unique index if not exists products_store_barcode_key
  on public.products (store_id, barcode)
  where barcode is not null;

-- 4) Only needed if your stores table uses column-level grants
--    (StoreProvider._updateStoreRow mentions column-grant failures).
--    Harmless if you grant at table level.
grant select (barcode_scanner_enabled) on public.stores to authenticated;
grant update (barcode_scanner_enabled) on public.stores to authenticated;
