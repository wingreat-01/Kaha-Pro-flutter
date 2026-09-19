-- Support for Settings -> Inventory -> Inventory Movements.
-- Run once in the Supabase SQL editor. Rename with your next
-- migration number if you keep them numbered.

-- 1) A reference on the existing ingredient log -- the transaction
--    number ("#00012") for sale-driven rows; null for manual changes.
alter table ingredient_stock_movements
  add column if not exists reference text;

-- Store-wide date-range reads (the per-ingredient index from 007
-- doesn't help those).
create index if not exists idx_ingredient_stock_movements_created
  on ingredient_stock_movements (created_at desc);

-- 2) Audit log for MANUAL product stock changes (+/- buttons and the
--    stock-count dialog in Inventory). Sales are not written here --
--    they're read from transactions.
--
-- product_name / unit are snapshots so history still reads correctly
-- after a product is renamed or deleted; product_id goes null on
-- delete instead of removing the history.
create table if not exists product_stock_movements (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id(),
  product_id uuid references products(id) on delete set null,
  product_name text not null,
  unit text not null default 'pc',
  delta numeric not null, -- positive = added, negative = deducted
  reason text not null,
  note text,
  staff_name text,
  created_at timestamptz not null default now()
);

create index if not exists idx_product_stock_movements_created
  on product_stock_movements (created_at desc);

alter table product_stock_movements enable row level security;

drop policy if exists "store scoped access" on product_stock_movements;
create policy "store scoped access" on product_stock_movements
  for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());
