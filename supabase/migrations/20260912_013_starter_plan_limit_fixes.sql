-- delete_account_cascade(p_store_id)
--
-- Single-transaction teardown of everything belonging to one store, for
-- account deletion. Called ONLY from the delete-account Edge Function via
-- the service-role client -- never exposed to authenticated/anon roles.
--
-- Why explicit deletes for every table, even the ones that already cascade
-- (product_variants, ingredients, payment_methods): if a future migration
-- ever drops or changes one of those ON DELETE CASCADE clauses, this
-- function keeps working correctly instead of silently leaving orphaned
-- rows. An explicit delete on a row already removed by cascade is just a
-- no-op, so this is strictly safer than relying on cascade alone.
--
-- Order matters and is NOT arbitrary -- see the comments per table below.
-- If you add a new store_id-scoped table later, add its delete here too,
-- in dependency order (children before the tables they reference).
create or replace function public.delete_account_cascade(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 1. ai_usage_log: no on-delete clause on store_id, and (per its own
  --    RLS comment) zero delete policies for the owning user -- this is
  --    the one table that can ONLY be cleared from here, since this
  --    function runs as its owner (security definer) and bypasses RLS.
  delete from public.ai_usage_log where store_id = p_store_id;

  -- 2. product_recipe_items: must go before ingredients (on delete
  --    restrict there would otherwise abort step 8) and before
  --    product_variants for the same reason, in case a variant delete is
  --    ever changed to restrict too. Cleared via both sides since a
  --    recipe item can be orphaned from either direction.
  delete from public.product_recipe_items
  where ingredient_id in (select id from public.ingredients where store_id = p_store_id)
     or product_variant_id in (select id from public.product_variants where store_id = p_store_id);

  -- 3. transactions: no on-delete clause on payment_method_id -- must be
  --    gone before payment_methods (step 7) or that delete fails.
  delete from public.transactions where store_id = p_store_id;

  -- 4. product_variants: before products, in case product_variants.product_id
  --    isn't cascade (unverified -- this table's CREATE TABLE wasn't seen
  --    directly, only inferred from store_id-scoped RLS comments).
  delete from public.product_variants where store_id = p_store_id;

  -- 5. products: before categories, in case products.category_id isn't cascade.
  delete from public.products where store_id = p_store_id;

  -- 6. categories
  delete from public.categories where store_id = p_store_id;

  -- 7. payment_methods: safe now that transactions (step 3) are gone.
  delete from public.payment_methods where store_id = p_store_id;

  -- 8. ingredients: safe now that product_recipe_items (step 2) are gone.
  delete from public.ingredients where store_id = p_store_id;

  -- 9. staff_users: PIN-based sub-accounts under this store, no known
  --    dependents.
  delete from public.staff_users where store_id = p_store_id;

  -- 10. store_counters: receipt numbering etc.
  delete from public.store_counters where store_id = p_store_id;

  -- 11. stores: the parent row itself, last. Any table that DOES have a
  --     working ON DELETE CASCADE from stores just no-ops above and
  --     finishes cleanly here.
  delete from public.stores where id = p_store_id;
end;
$$;

-- Lock this down: only the service role should ever be able to call this.
revoke all on function public.delete_account_cascade(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_cascade(uuid) to service_role;
