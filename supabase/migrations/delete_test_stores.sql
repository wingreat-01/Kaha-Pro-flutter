-- delete_test_stores.sql
--
-- Wipes EVERY store and everything that hangs off a store (products,
-- transactions, staff, subscriptions, etc.), plus the Supabase Auth
-- users that owned them, so the same test emails can sign up again.
-- Irreversible.
--
-- Uses TRUNCATE ... CASCADE on stores instead of calling
-- delete_account_cascade(): that function currently references a
-- table (public.ai_usage_log) that does not exist in this database,
-- so it fails on the first store. TRUNCATE follows the actual foreign
-- keys, so it doesn't depend on a hand-written table list.
--
-- PREVIEW (run alone first): which tables the cascade will empty.
--   select distinct conrelid::regclass as table_that_will_be_emptied
--   from pg_constraint
--   where contype = 'f' and confrelid = 'public.stores'::regclass;
-- (tables that reference those tables get emptied too)

do $$
declare
  doomed_users uuid[];
begin
  -- Capture owners first: once store_members is emptied there is no
  -- way to tell which auth users belonged to the stores.
  select array_agg(distinct auth_user_id) into doomed_users
  from public.store_members;

  truncate table public.stores cascade;

  if doomed_users is not null then
    delete from auth.users where id = any(doomed_users);
  end if;

  raise notice 'Wiped all stores and deleted % auth users.',
    coalesce(array_length(doomed_users, 1), 0);
end $$;
