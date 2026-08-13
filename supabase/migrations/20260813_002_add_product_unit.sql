-- Step 1 of the Inventory/Raw Materials plan (kahapro-inventory-recipes-plan.md):
-- gives every product its own unit of measure instead of assuming
-- everything is counted in whole pieces. Backward-compatible — every
-- existing row defaults to 'pc', so nothing about current behavior
-- changes until an owner picks a different unit for a product.

alter table products
  add column unit text not null default 'pc',
  add column unit_label text; -- only meaningful when unit = 'custom'
                               -- (e.g. "roll", "bundle", "meter")

-- Optional but recommended: constrain to the known set so a bad
-- client-side value can't silently land in the column. Extend this
-- list here (and in product.dart's kProductUnits) together if a new
-- unit is ever needed.
alter table products
  add constraint products_unit_check
  check (unit in ('pc', 'g', 'kg', 'ml', 'L', 'pack', 'sack', 'custom'));
