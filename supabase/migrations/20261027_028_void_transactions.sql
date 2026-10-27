-- 20261027_028_void_transactions.sql
--
-- Admin-only "Void sale". Run once in the Supabase SQL editor, AFTER
-- the record_transaction migrations (005/006) and
-- 007_create_ingredient_stock_movements.sql.
--
-- WHY THE CHECK LIVES HERE AND NOT IN THE APP: admins and cashiers are
-- PIN-level users sharing ONE Supabase Auth session per device (the
-- store owner's). auth.uid() can't tell them apart, so hiding the Void
-- button from cashiers is only cosmetic. void_transaction() re-checks
-- an admin's name + PIN through the same verify_staff_login() the login
-- screen uses (so PIN hashing and lockout rules stay in one place), and
-- a trigger rejects any other attempt to change the void columns --
-- e.g. a direct PATCH on /rest/v1/transactions.
--
-- A voided sale is never deleted: it stays in the ledger with who/when/
-- why, and the app leaves it out of totals and reports. Stock is put
-- back by the app right after a successful void (same place sales
-- deduct it -- see ProductProvider.restockForVoid).

-- 1) Void columns on transactions.
alter table public.transactions
  add column if not exists status text not null default 'completed',
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by_staff_id uuid,
  add column if not exists voided_by_name text,
  add column if not exists void_reason text;

do $$
begin
  alter table public.transactions
    add constraint transactions_status_check check (status in ('completed', 'voided'));
exception
  when duplicate_object then null;
end
$$;

-- 2) Ingredient stock put back by a void is logged with source 'void'
--    (the inline CHECK from 007 only allowed 'manual' and 'sale').
alter table public.ingredient_stock_movements
  drop constraint if exists ingredient_stock_movements_source_check;
alter table public.ingredient_stock_movements
  add constraint ingredient_stock_movements_source_check
  check (source in ('manual', 'sale', 'void'));

-- 3) Only void_transaction() may touch the void columns. It sets a
--    transaction-local flag (set_config(..., true)) that this trigger
--    looks for; set_config lives in pg_catalog, which PostgREST doesn't
--    expose, so a client can't set the flag itself.
create or replace function public.guard_transaction_void_columns()
returns trigger
language plpgsql
as $function$
begin
  if (new.status is distinct from old.status
      or new.voided_at is distinct from old.voided_at
      or new.voided_by_staff_id is distinct from old.voided_by_staff_id
      or new.voided_by_name is distinct from old.voided_by_name
      or new.void_reason is distinct from old.void_reason)
     and coalesce(current_setting('merq.void_in_progress', true), '') <> 'on' then
    raise exception 'Sales can only be voided through void_transaction().'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_guard_transaction_void_columns on public.transactions;
create trigger trg_guard_transaction_void_columns
before update on public.transactions
for each row execute function public.guard_transaction_void_columns();

-- 4) The void itself.
--
-- Returns jsonb instead of raising on a wrong PIN / non-admin / already
-- voided: an exception would roll back the whole call, including any
-- failed-attempt counter verify_staff_login() records, which would let
-- someone guess admin PINs through this function without ever tripping
-- the lockout. Real errors (sale not in this store, etc.) still raise.
--
--   { "ok": true,  "transaction": { ...updated transactions row... } }
--   { "ok": false, "error": "<message safe to show the user>" }
--
-- SECURITY INVOKER (the default), like record_transaction: the
-- transactions lookup/update run under the caller's RLS, so a store
-- can only ever void its own sales.
drop function if exists public.void_transaction(uuid, text, text, text);
create or replace function public.void_transaction(
  p_transaction_id uuid,
  p_admin_name text,
  p_pin text,
  p_reason text
)
returns jsonb
language plpgsql
as $function$
declare
  v_admin record;
  v_tx transactions;
  v_reason text := left(trim(coalesce(p_reason, '')), 200);
begin
  if v_reason = '' then
    return jsonb_build_object('ok', false, 'error', 'A reason is required to void a sale.');
  end if;

  select * into v_admin
  from public.verify_staff_login(p_admin_name, p_pin)
  limit 1;
  if not found then
    -- Same message for wrong name, wrong PIN and locked-out account,
    -- matching verify_staff_login's own don't-distinguish policy.
    return jsonb_build_object('ok', false, 'error', 'Invalid admin name or PIN.');
  end if;
  if v_admin.role::text <> 'admin' then
    return jsonb_build_object('ok', false, 'error', 'Only an admin can void a sale.');
  end if;

  select * into v_tx from transactions where id = p_transaction_id for update;
  if not found then
    raise exception 'Sale not found.' using errcode = 'P0002';
  end if;
  if v_tx.status = 'voided' then
    return jsonb_build_object('ok', false, 'error', 'This sale was already voided.');
  end if;

  perform set_config('merq.void_in_progress', 'on', true);
  update transactions
     set status = 'voided',
         voided_at = now(),
         voided_by_staff_id = v_admin.id,
         voided_by_name = v_admin.name,
         void_reason = v_reason
   where id = p_transaction_id
  returning * into v_tx;
  perform set_config('merq.void_in_progress', 'off', true);

  return jsonb_build_object('ok', true, 'transaction', to_jsonb(v_tx));
end;
$function$;

grant execute on function public.void_transaction(uuid, text, text, text) to authenticated;

-- Sanity checks after running:
--   select status, count(*) from transactions group by status;   -- all 'completed'
--   update transactions set status = 'voided' where false;       -- fine (no rows)
--   -- and a real direct update of status should fail with 42501.
