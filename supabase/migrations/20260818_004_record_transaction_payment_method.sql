-- =============================================================
-- KahaPro: record_transaction — add payment_method_id param
-- Adds an optional p_payment_method_id param (default null, so any
-- existing caller that doesn't pass it keeps working unchanged) and
-- writes it into the new transactions.payment_method_id column.
-- Everything else in the function is untouched — same insert shape,
-- same line-items logic.
-- =============================================================

CREATE OR REPLACE FUNCTION public.record_transaction(
  p_total numeric,
  p_cash_tendered numeric,
  p_change_amount numeric,
  p_cashier_name text,
  p_items jsonb,
  p_payment_method_id uuid DEFAULT NULL
)
 RETURNS transactions
 LANGUAGE plpgsql
AS $function$
declare
  v_transaction transactions;
begin
  insert into transactions (total, cash_tendered, change_amount, cashier_name, payment_method_id)
  values (p_total, p_cash_tendered, p_change_amount, p_cashier_name, p_payment_method_id)
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
$function$
