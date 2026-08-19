-- 007_store_details.sql
-- Store Details screen fields — address + a custom receipt footer
-- message. Both nullable/free text, no defaults needed since an
-- empty store detail is a perfectly normal starting state (owner
-- fills these in from the new Settings screen whenever they want).

alter table stores
  add column if not exists address text,
  add column if not exists receipt_footer text;

-- Sanity check after running:
-- select column_name, data_type
-- from information_schema.columns
-- where table_name = 'stores' and column_name in ('address', 'receipt_footer');
