-- 003_add_store_business_type.sql
--
-- Adds business_type to stores. Drives the Inventory screen's label
-- ("Ingredients" / "Supplies" / "Raw Materials") and new-product
-- defaults -- a one-line label swap read from this column, never a
-- schema or logic fork (see kahapro-inventory-recipes-plan.md Step 0).
--
-- Backward-compatible: existing rows get 'general' (the safe default
-- label "Raw Materials"), matching today's behavior exactly.

alter table stores
  add column business_type text not null default 'general';

alter table stores
  add constraint stores_business_type_check
  check (business_type in ('food_beverage', 'retail_hardware', 'general'));

-- handle_new_user() now also reads business_type out of signup
-- metadata, same pattern as store_name. Defaults to 'general' if the
-- picker wasn't shown/selected for some reason (e.g. an older client
-- build), so this never blocks store creation.
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
