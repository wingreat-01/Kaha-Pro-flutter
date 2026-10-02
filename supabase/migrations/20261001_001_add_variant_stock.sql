-- Optional per-size (variant) stock for MERQ.
-- Run in the Supabase SQL editor BEFORE using the new app build.
-- Safe to re-run.

-- null = this size has no count of its own and shares the product's stock
-- (exactly how every existing size behaves, so existing data is unchanged).
alter table public.product_variants
  add column if not exists stock_qty integer;

alter table public.product_variants
  drop constraint if exists product_variants_stock_qty_check;
alter table public.product_variants
  add constraint product_variants_stock_qty_check
  check (stock_qty is null or stock_qty >= 0);

-- Lets the Inventory Movements log say which size a manual change was for.
alter table public.product_stock_movements
  add column if not exists variant_name text;
