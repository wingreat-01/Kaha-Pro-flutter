-- ============================================================================
-- MERQ QR Ordering -- payment choice (pay at counter / pay online, manual)
-- Suggested filename: supabase/migrations/20260929_026_qr_order_payments.sql
--
-- Step 1 is the MANUAL online flow: the store uploads its own payment QR
-- (GCash / Maya / bank QR Ph), the customer pays in their own e-wallet and
-- types the reference number, and the cashier verifies it before accepting.
-- No payment gateway involved, so the page can never prove a payment was
-- made -- that is what payment_status = 'unverified' means.
--
--   payment_method : 'counter' | 'online'
--   payment_status : 'unpaid'      counter order, nothing collected yet
--                    'unverified'  online order, customer typed a reference,
--                                  cashier has not confirmed it yet
--                    'paid'        cashier confirmed the money arrived
--
-- orders.status is NOT changed (still pending / accepted / rejected).
-- Safe to re-run.
-- ============================================================================

alter table public.stores
  add column if not exists qr_pay_counter_enabled boolean not null default true,
  add column if not exists qr_pay_online_enabled boolean not null default false,
  add column if not exists online_payment_qr_url text,
  add column if not exists online_payment_instructions text;

alter table public.orders
  add column if not exists payment_method text not null default 'counter',
  add column if not exists payment_status text not null default 'unpaid',
  add column if not exists payment_reference text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'orders_payment_method_check') then
    alter table public.orders
      add constraint orders_payment_method_check
      check (payment_method in ('counter', 'online'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_payment_status_check') then
    alter table public.orders
      add constraint orders_payment_status_check
      check (payment_status in ('unpaid', 'unverified', 'paid'));
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- get_menu_for_qr -- same as 025, plus a "payment" object the page uses to
-- decide which options to show. Online only counts as available when the
-- store has switched it on AND uploaded a QR image. If a store somehow has
-- nothing available, counter is forced on so customers can still order.
-- ----------------------------------------------------------------------------
create or replace function public.get_menu_for_qr(p_qr_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table record;
  v_products jsonb;
  v_online boolean;
  v_counter boolean;
begin
  select t.id, t.store_id, t.label, s.name as store_name,
         s.qr_pay_counter_enabled, s.qr_pay_online_enabled,
         s.online_payment_qr_url, s.online_payment_instructions
  into v_table
  from public.tables t
  join public.stores s on s.id = t.store_id
  where t.qr_token = p_qr_token
    and t.is_active = true;

  if not found then
    raise exception 'invalid_or_inactive_table';
  end if;

  v_online := v_table.qr_pay_online_enabled
              and coalesce(v_table.online_payment_qr_url, '') <> '';
  v_counter := v_table.qr_pay_counter_enabled or not v_online;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'name', p.name,
           'price', coalesce(
             (select min(v.price) from public.product_variants v where v.product_id = p.id),
             p.price
           ),
           'category_id', p.category_id,
           'category', to_jsonb(c)->>'name',
           'emoji', p.emoji,
           'image_url', p.image_url,
           'variants', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'id', v.id,
                      'name', v.name,
                      'price', v.price
                    ) order by v.sort_order, v.created_at)
             from public.product_variants v
             where v.product_id = p.id
           ), '[]'::jsonb)
         ) order by to_jsonb(c)->>'name', p.name), '[]'::jsonb)
  into v_products
  from public.products p
  left join public.categories c on c.id = p.category_id
  where p.store_id = v_table.store_id
    and p.show_on_qr_menu = true
    and (p.track_stock = false or p.stock_qty > 0);

  return jsonb_build_object(
    'store_id', v_table.store_id,
    'store_name', v_table.store_name,
    'table_id', v_table.id,
    'table_label', v_table.label,
    'payment', jsonb_build_object(
      'counter', v_counter,
      'online', v_online,
      'qr_url', case when v_online then v_table.online_payment_qr_url else null end,
      'instructions', case when v_online then v_table.online_payment_instructions else null end
    ),
    'products', v_products
  );
end;
$$;

grant execute on function public.get_menu_for_qr(uuid) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- submit_qr_order -- adds p_payment_method / p_payment_reference.
-- The old 3-argument version is dropped first: two overloads that differ
-- only by defaulted arguments make PostgREST calls ambiguous.
-- ----------------------------------------------------------------------------
drop function if exists public.submit_qr_order(uuid, text, jsonb);

create or replace function public.submit_qr_order(
  p_qr_token uuid,
  p_customer_name text,
  p_items jsonb,
  p_payment_method text default 'counter',
  p_payment_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table record;
  v_order_id uuid;
  v_total numeric(12, 2) := 0;
  v_item jsonb;
  v_product record;
  v_variant record;
  v_variant_id uuid;
  v_qty integer;
  v_unit_price numeric(12, 2);
  v_online boolean;
  v_counter boolean;
  v_method text := coalesce(nullif(trim(p_payment_method), ''), 'counter');
  v_ref text := left(nullif(trim(p_payment_reference), ''), 60);
begin
  if jsonb_array_length(p_items) = 0 then
    raise exception 'empty_order';
  end if;

  select t.id, t.store_id,
         s.qr_pay_counter_enabled, s.qr_pay_online_enabled, s.online_payment_qr_url
  into v_table
  from public.tables t
  join public.stores s on s.id = t.store_id
  where t.qr_token = p_qr_token
    and t.is_active = true;

  if not found then
    raise exception 'invalid_or_inactive_table';
  end if;

  -- Same availability rules get_menu_for_qr uses, re-checked here because
  -- the page's choice can't be trusted.
  v_online := v_table.qr_pay_online_enabled
              and coalesce(v_table.online_payment_qr_url, '') <> '';
  v_counter := v_table.qr_pay_counter_enabled or not v_online;

  if v_method not in ('counter', 'online') then
    raise exception 'invalid_payment_method';
  end if;
  if (v_method = 'online' and not v_online) or (v_method = 'counter' and not v_counter) then
    raise exception 'payment_method_unavailable';
  end if;
  if v_method = 'online' and (v_ref is null or length(v_ref) < 4) then
    raise exception 'payment_reference_required';
  end if;
  if v_method = 'counter' then
    v_ref := null;
  end if;

  insert into public.orders (
    store_id, table_id, customer_name, status, total,
    payment_method, payment_status, payment_reference
  )
  values (
    v_table.store_id, v_table.id, nullif(trim(p_customer_name), ''), 'pending', 0,
    v_method,
    case when v_method = 'online' then 'unverified' else 'unpaid' end,
    v_ref
  )
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item ->> 'quantity')::integer;
    v_variant_id := nullif(v_item ->> 'variant_id', '')::uuid;

    select id, price into v_product
    from public.products
    where id = (v_item ->> 'product_id')::uuid
      and store_id = v_table.store_id;

    if not found then
      raise exception 'invalid_product: %', v_item ->> 'product_id';
    end if;

    v_unit_price := v_product.price;
    v_variant := null;

    if v_variant_id is not null then
      select id, name, price into v_variant
      from public.product_variants
      where id = v_variant_id
        and product_id = v_product.id
        and store_id = v_table.store_id;

      if not found then
        raise exception 'invalid_variant: %', v_variant_id;
      end if;

      v_unit_price := v_variant.price;
    elsif exists (select 1 from public.product_variants where product_id = v_product.id) then
      raise exception 'variant_required: %', v_product.id;
    end if;

    v_total := v_total + v_unit_price * v_qty;

    insert into public.order_items (order_id, product_id, variant_id, variant_name, quantity, price)
    values (v_order_id, v_product.id, v_variant.id, v_variant.name, v_qty, v_unit_price);
  end loop;

  update public.orders set total = v_total, updated_at = now() where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function public.submit_qr_order(uuid, text, jsonb, text, text) to anon;
