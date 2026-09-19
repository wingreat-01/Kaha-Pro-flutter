-- Optional cost per unit for products (what one unit costs the store),
-- set from Settings -> Products (Inventory). Run once in the Supabase
-- SQL editor; rename with your next migration number if you keep them
-- numbered.
alter table products
  add column if not exists cost_per_unit numeric
  check (cost_per_unit is null or cost_per_unit >= 0);
