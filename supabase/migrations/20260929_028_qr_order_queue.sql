-- 028: QR order queue + status tracking
--
-- Adds:
--   * a short per-store, per-day order number (#1, #2, ... resets daily,
--     Asia/Manila time) shown to the customer and the cashier
--   * new order statuses: preparing, ready, completed
--     ('accepted' stays allowed so the current app build keeps working;
--     the customer page treats it as 'preparing')
--   * orders.transaction_id, linking a completed order to its sale
--   * get_order_status(order_id): lets the customer page (anon) follow
--     its own order. The order's random uuid acts as the tracking token.
--   * drops the old 3-argument submit_qr_order, which skipped the
--     payment rules and could still be called directly.
--
-- Run AFTER 025, 026 and 027.

-- 1. Columns ---------------------------------------------------------------
alter table public.orders
  add column if not exists order_number integer,
  add column if not exists queue_date date,
  add column if not exists transaction_id uuid
    references public.transactions(id) on delete set null;

update public.orders
set queue_date = (created_at at time zone 'Asia/Manila')::date
where queue_date is null;

create index if not exists orders_store_queue_idx
  on public.orders (store_id, queue_date, order_number);

create unique index if not exists orders_transaction_id_key
  on public.orders (transaction_id)
  where transaction_id is not null;

-- 2. Statuses --------------------------------------------------------------
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders
  add constraint orders_status_check
  check (status = any (array[
    'pending', 'accepted', 'preparing', 'ready', 'completed', 'rejected'
  ]));

-- Keep updated_at honest on every change (the customer page's
-- "now serving" number is based on it).
create or replace function public.touch_orders_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_orders_touch_updated_at on public.orders;
create trigger trg_orders_touch_updated_at
before update on public.orders
for each row execute function public.touch_orders_updated_at();

-- 3. Daily counter ---------------------------------------------------------
create table if not exists public.order_counters (
  store_id uuid not null references public.stores(id) on delete cascade,
  day date not null,
  last_number integer not null default 0,
  primary key (store_id, day)
);

-- No policies on purpose: only security-definer functions touch it.
alter table public.order_counters enable row level security;

create or replace function public.next_order_number(p_store_id uuid, p_day date)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_num integer;
begin
  insert into public.order_counters (store_id, day, last_number)
  values (p_store_id, p_day, 1)
  on conflict (store_id, day)
  do update set last_number = public.order_counters.last_number + 1
  returning last_number into v_num;

  return v_num;
end;
$$;

revoke all on function public.next_order_number(uuid, date) from public, anon, authenticated;

-- 4. submit_qr_order: same rules as before + queue number ------------------
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
set search_path to 'public'
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
  v_day date := (now() at time zone 'Asia/Manila')::date;
  v_number integer;
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

  v_number := public.next_order_number(v_table.store_id, v_day);

  insert into public.orders (
    store_id, table_id, customer_name, status, total,
    payment_method, payment_status, payment_reference,
    order_number, queue_date
  )
  values (
    v_table.store_id, v_table.id, nullif(trim(p_customer_name), ''), 'pending', 0,
    v_method,
    case when v_method = 'online' then 'unverified' else 'unpaid' end,
    v_ref,
    v_number, v_day
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

  update public.orders set total = v_total where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function public.submit_qr_order(uuid, text, jsonb, text, text)
  to anon, authenticated;

-- 5. get_order_status: what the customer page polls -------------------------
create or replace function public.get_order_status(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_o record;
  v_ahead integer := 0;
  v_serving integer;
  v_items jsonb;
begin
  select id, store_id, order_number, queue_date, status,
         payment_method, payment_status, total, created_at
  into v_o
  from public.orders
  where id = p_order_id;

  if not found then
    return null;
  end if;

  if v_o.order_number is not null then
    select count(*) into v_ahead
    from public.orders
    where store_id = v_o.store_id
      and queue_date = v_o.queue_date
      and order_number < v_o.order_number
      and status in ('pending', 'accepted', 'preparing');
  end if;

  select order_number into v_serving
  from public.orders
  where store_id = v_o.store_id
    and queue_date = v_o.queue_date
    and order_number is not null
    and status in ('ready', 'completed')
  order by updated_at desc
  limit 1;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'name', p.name,
               'variant_name', oi.variant_name,
               'quantity', oi.quantity
             )
             order by oi.created_at
           ),
           '[]'::jsonb
         )
  into v_items
  from public.order_items oi
  left join public.products p on p.id = oi.product_id
  where oi.order_id = v_o.id;

  return jsonb_build_object(
    'order_number', v_o.order_number,
    'status', v_o.status,
    'payment_method', v_o.payment_method,
    'payment_status', v_o.payment_status,
    'total', v_o.total,
    'created_at', v_o.created_at,
    'ahead', v_ahead,
    'now_serving', v_serving,
    'items', v_items
  );
end;
$$;

revoke all on function public.get_order_status(uuid) from public;
grant execute on function public.get_order_status(uuid) to anon, authenticated;

-- 6. Sanity checks (run separately) ------------------------------------------
--   select proname, oidvectortypes(proargtypes) from pg_proc
--   where proname in ('submit_qr_order', 'get_order_status');
--   -- expect ONE submit_qr_order (uuid, text, jsonb, text, text)
--
--   select policyname, cmd from pg_policies
--   where schemaname = 'public' and tablename = 'orders';
--   -- the cashier app needs an UPDATE (or ALL) policy on orders
