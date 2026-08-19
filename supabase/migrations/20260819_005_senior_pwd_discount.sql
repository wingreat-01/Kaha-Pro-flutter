-- 005_senior_pwd_discount.sql
-- Senior Citizen / PWD discount (RA 9994 / RA 10754) — store-level
-- on/off toggle + per-transaction discount snapshot columns.
-- Run this in the Supabase SQL editor.

-- 1. Store-level toggle. Defaults to false (off/hidden) so existing
--    stores don't suddenly show new checkout UI until the owner opts in.
alter table stores
  add column if not exists senior_pwd_discount_enabled boolean not null default false;

-- 2. Per-transaction discount snapshot. All nullable/zero-default so
--    every past row (and every future non-discounted sale) is
--    unaffected. Snapshotting the holder's name/ID on the transaction
--    itself (not a separate table) matches how payment_method_name is
--    already snapshotted onto transactions — the record needs to
--    survive independently of anything else changing later.
alter table transactions
  add column if not exists discount_type text
    check (discount_type is null or discount_type in ('senior', 'pwd')),
  add column if not exists discount_holder_name text,
  add column if not exists discount_id_number text,
  add column if not exists discount_amount numeric not null default 0,
  add column if not exists vat_exempt_amount numeric not null default 0;

-- Sanity check after running:
-- select column_name, data_type, column_default
-- from information_schema.columns
-- where table_name in ('stores', 'transactions')
--   and column_name like '%discount%' or column_name = 'vat_exempt_amount';
