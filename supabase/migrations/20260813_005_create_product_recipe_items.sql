-- 005_create_product_recipe_items.sql
--
-- The bridge from kahapro-inventory-recipes-plan.md Step 3/4: connects
-- a sellable Product (+ optional ProductVariant, e.g. "Large" using
-- more milk than "Medium") to the Ingredient rows it consumes, and how
-- much of each. A product with no rows here behaves exactly as today
-- (flat Product.unit/stock_quantity deduction, or none at all) --
-- recipe deduction is opt-in per product, not a schema-wide switch.
--
-- No store_id column here (unlike ingredients) -- this table's scope
-- is inherited entirely through product_id -> products.store_id, so
-- RLS checks that join instead of a direct column, same reasoning as
-- product_variants presumably already does.

create table if not exists product_recipe_items (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  variant_id uuid references product_variants(id) on delete cascade,
  ingredient_id uuid not null references ingredients(id) on delete restrict,
  quantity_used numeric not null check (quantity_used > 0),
  created_at timestamptz not null default now()
);

-- ON DELETE RESTRICT on ingredient_id is deliberate: silently letting
-- an ingredient disappear out from under a live recipe would leave a
-- product that looks configured but quietly stops deducting anything
-- for that line at checkout. Deleting an ingredient still in use
-- should fail loudly (the delete call in ingredient_provider.dart
-- will surface that error) rather than orphan the recipe.

create index if not exists product_recipe_items_product_id_idx on product_recipe_items(product_id);
create index if not exists product_recipe_items_ingredient_id_idx on product_recipe_items(ingredient_id);

alter table product_recipe_items enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'product_recipe_items' and policyname = 'store scoped access via product'
  ) then
    create policy "store scoped access via product" on product_recipe_items
      for all
      using (
        exists (
          select 1 from products p
          where p.id = product_recipe_items.product_id
          and p.store_id = current_store_id()
        )
      )
      with check (
        exists (
          select 1 from products p
          where p.id = product_recipe_items.product_id
          and p.store_id = current_store_id()
        )
      );
  end if;
end $$;
