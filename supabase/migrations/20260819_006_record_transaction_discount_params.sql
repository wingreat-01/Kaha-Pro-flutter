-- 006_record_transaction_discount_params.sql
-- Adds Senior/PWD discount params to record_transaction. Run AFTER
-- 005_senior_pwd_discount.sql (needs the transactions columns to exist).
--
-- Drops BOTH existing overloads first rather than using CREATE OR
-- REPLACE — Postgres treats a changed argument list as a distinct
-- overload, not a replacement, which is exactly the ambiguity you
-- just hit with the old 5-arg version. Dropping first guarantees
-- there is only ever one record_transaction function again.

-- Dead pre-migration-004 version (5 args, no payment_method_id) —
-- confirmed nothing in the app still calls this shape.
drop function if exists public.record_transaction(numeric, numeric, numeric, text, jsonb);

-- Current live version (6 args, adds payment_method_id) — being
-- replaced by the 11-arg version below.
drop function if exists public.record_transaction(numeric, numeric, numeric, text, jsonb, uuid);

create or replace function public.record_transaction(
  p_total numeric,
  p_cash_tendered numeric,
  p_change_amount numeric,
  p_cashier_name text,
  p_items jsonb,
  p_payment_method_id uuid default null,
  p_discount_type text default null,
  p_discount_holder_name text default null,
  p_discount_id_number text default null,
  p_discount_amount numeric default 0,
  p_vat_exempt_amount numeric default 0
)
returns transactions
language plpgsql
as $function$
declare
  v_transaction transactions;
begin
  insert into transactions (
    total, cash_tendered, change_amount, cashier_name, payment_method_id,
    discount_type, discount_holder_name, discount_id_number, discount_amount, vat_exempt_amount
  )
  values (
    p_total, p_cash_tendered, p_change_amount, p_cashier_name, p_payment_method_id,
    p_discount_type, p_discount_holder_name, p_discount_id_number, p_discount_amount, p_vat_exempt_amount
  )
  returning * into v_transaction;

  insert into transaction_line_items
    (transaction_id, product_id, product_name, category, unit_price, quantity, line_total, variant_id, variant_name)
  select
    v_transaction.id,
    (item->>'product_id')::uuid,
    item->>'product_name',
    item->>'category',
    (item->>'unit_price')::numeric,
    (item->>'quantity')::int,
    (item->>'line_total')::numeric,
    nullif(item->>'variant_id', '')::uuid,
    item->>'variant_name'
  from jsonb_array_elements(p_items) as item;

  return v_transaction;
end;
$function$;

-- Sanity check after running — should return exactly one row:
-- select p.oid, pg_get_function_identity_arguments(p.oid) as args
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where p.proname = 'record_transaction' and n.nspname = 'public';
