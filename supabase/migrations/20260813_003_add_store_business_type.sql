-- 003_add_store_business_type.sql
--
-- Adds business_type to stores. Drives the Inventory screen's label
-- ("Ingredients" / "Supplies" / "Raw Materials") and new-product
-- defaults -- a one-line label swap read from this column, never a
-- schema or logic fork (see kahapro-inventory-recipes-plan.md Step 0).
--
-- Idempotent -- safe to re-run. The column already exists on this
-- database (added by an earlier partial run), so this version checks
-- before adding it and before adding the constraint, instead of
-- failing outright the way a plain ALTER TABLE ADD COLUMN would.

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'stores' and column_name = 'business_type'
  ) then
    alter table stores
      add column business_type text not null default 'general';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'stores_business_type_check'
  ) then
    alter table stores
      add constraint stores_business_type_check
      check (business_type in ('food_beverage', 'retail_hardware', 'general'));
  end if;
end $$;

-- CREATE OR REPLACE is already idempotent -- safe to re-run regardless
-- of the column/constraint state above.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_store_id uuid;
begin
  insert into stores (name, business_type)
  values (
    coalesce(NEW.raw_user_meta_data->>'store_name', 'My Store'),
    coalesce(NEW.raw_user_meta_data->>'business_type', 'general')
  )
  returning id into new_store_id;

  -- Firing this insert also fires trg_seed_uncategorized above, so the
  -- new store's Uncategorized category exists before anyone logs in.
  insert into store_members (store_id, auth_user_id, role)
  values (new_store_id, NEW.id, 'owner');

  return NEW;
end;
$$;
