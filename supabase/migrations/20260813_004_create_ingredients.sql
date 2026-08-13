-- 004_create_ingredients.sql
--
-- The Ingredient table from kahapro-inventory-recipes-plan.md Step 3 --
-- a genuinely separate system from Products, never touching the
-- Register grid query. Managed from its own admin screen
-- (ingredients_panel.dart), labeled per Store.business_type via
-- StoreProvider.businessTypeLabel (Ingredients/Supplies/Raw Materials).
--
-- Idempotent-ish: uses IF NOT EXISTS on the table/policy creation so a
-- partial re-run doesn't hard-fail, matching 003's approach after the
-- "column already exists" surprise there.

create table if not exists ingredients (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id() references stores(id) on delete cascade,
  name text not null,
  unit text not null default 'pc'
    check (unit in ('pc', 'g', 'kg', 'ml', 'L', 'pack', 'sack', 'custom')),
  unit_label text, -- only meaningful when unit = 'custom', same pattern as products.unit_label
  stock_quantity numeric not null default 0,
  low_stock_threshold numeric,
  cost_per_unit numeric,
  created_at timestamptz not null default now()
);

create index if not exists ingredients_store_id_idx on ingredients(store_id);

alter table ingredients enable row level security;

-- Same store-scoped ALL-command policy pattern as categories/products/
-- staff_users (see the store_counters RLS note in the project log) --
-- current_store_id() already exists and is used everywhere else.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'ingredients' and policyname = 'store scoped access'
  ) then
    create policy "store scoped access" on ingredients
      for all
      using (store_id = current_store_id())
      with check (store_id = current_store_id());
  end if;
end $$;
