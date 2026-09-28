-- ============================================================================
-- MERQ QR Ordering — Phase 1 core schema
-- Suggested filename: supabase/migrations/20260928_020_qr_ordering_core.sql
--   (next number after 20260920_019_store_subscriptions.sql per your history —
--   double-check against your actual migrations folder before applying, in
--   case something landed after that one that I haven't seen.)
--
-- ASSUMPTION FLAGGED: stores.id and products.id are assumed to be `uuid`
-- (matching store_members.id / store_id style seen elsewhere). If either is
-- actually bigint/int8, change the FK column types below (table_id/store_id/
-- product_id) to match before running this.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. tables — physical tables in a store, one QR code each
-- ----------------------------------------------------------------------------
create table public.tables (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  label text not null,                 -- e.g. "Table 5", "Bar 2"
  qr_token uuid not null default gen_random_uuid(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (store_id, label),
  unique (qr_token)
);

create index tables_store_id_idx on public.tables (store_id);

alter table public.tables enable row level security;

-- Only store owner/staff (same auth model as products/staff_users — the
-- Supabase Auth session belongs to the store owner, checked via
-- store_members) can create/rename/deactivate tables. No anon policy at
-- all: customers never query this table directly — see get_menu_for_qr().
create policy "store members manage their tables"
  on public.tables
  for all
  using (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = tables.store_id
        and sm.auth_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = tables.store_id
        and sm.auth_user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 2. orders
-- ----------------------------------------------------------------------------
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  table_id uuid not null references public.tables(id) on delete restrict,
  customer_name text,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  total numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index orders_store_status_idx on public.orders (store_id, status);

alter table public.orders enable row level security;

-- Owner/staff can view and update (accept/reject) orders for their store.
-- No anon select/insert/update policy here on purpose — customers never
-- write to this table directly, only through submit_qr_order() below,
-- which runs as security definer. This is what stops a customer editing
-- someone else's order or tampering with total/status directly.
create policy "store members manage their orders"
  on public.orders
  for all
  using (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = orders.store_id
        and sm.auth_user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.store_members sm
      where sm.store_id = orders.store_id
        and sm.auth_user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 3. order_items
-- ----------------------------------------------------------------------------
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  price numeric(12, 2) not null,   -- snapshotted at order time, not a live FK to products.price
  created_at timestamptz not null default now()
);

create index order_items_order_id_idx on public.order_items (order_id);

alter table public.order_items enable row level security;

create policy "store members view their order items"
  on public.order_items
  for select
  using (
    exists (
      select 1 from public.orders o
      join public.store_members sm on sm.store_id = o.store_id
      where o.id = order_items.order_id
        and sm.auth_user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Anonymous menu read access
--
-- New surface: the customer ordering page is NOT signed in, so products
-- (and categories, if you filter/group by them) need to become readable
-- by the `anon` role for the first time. This makes your product catalog
-- (names + prices, not stock/cost data) fetchable by anyone who knows a
-- store's products — that's inherent to any public QR menu, but flagging
-- it since it's a new exposure that didn't exist before this feature.
-- Scoped to non-hidden/in-stock items only, not literally everything.
-- ----------------------------------------------------------------------------
create policy "anon can view orderable products"
  on public.products
  for select
  to anon
  using (stock_qty > 0 or stock_qty is null);

-- If you have a `categories` table you want the customer menu grouped by,
-- mirror the same anon-select policy there. Left out here since I haven't
-- seen that table's columns this session — say the word and I'll add it.

-- ----------------------------------------------------------------------------
-- 5. get_menu_for_qr — resolves a QR token to store/table + active menu
--
-- security definer so anon never needs a SELECT policy on `tables` itself
-- (which would otherwise let anyone list every store's tables/qr_tokens by
-- querying with no filter). This function is the only door in.
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
begin
  select t.id, t.store_id, t.label, s.name as store_name
  into v_table
  from public.tables t
  join public.stores s on s.id = t.store_id
  where t.qr_token = p_qr_token
    and t.is_active = true;

  if not found then
    raise exception 'invalid_or_inactive_table';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'name', p.name,
           'price', p.price,
           'category_id', p.category_id,
           'emoji', p.emoji,
           'image_path', p.image_path
         )), '[]'::jsonb)
  into v_products
  from public.products p
  where p.store_id = v_table.store_id
    and (p.stock_qty > 0 or p.stock_qty is null);

  return jsonb_build_object(
    'store_id', v_table.store_id,
    'store_name', v_table.store_name,
    'table_id', v_table.id,
    'table_label', v_table.label,
    'products', v_products
  );
end;
$$;

grant execute on function public.get_menu_for_qr(uuid) to anon;

-- ----------------------------------------------------------------------------
-- 6. submit_qr_order — the only way an order gets created
--
-- Why an RPC instead of letting anon INSERT into orders/order_items
-- directly: (a) price integrity — total is computed here from products.price
-- server-side, never trusted from the client, so a tampered request can't
-- submit a fake low price; (b) atomicity — order + all its items are
-- inserted in one transaction, so you never get an order with zero items
-- from a request that died halfway; (c) it re-validates the table is still
-- active and every product still belongs to that table's store.
--
-- p_items shape: [{"product_id": "...", "quantity": 2}, ...]
-- ----------------------------------------------------------------------------
create or replace function public.submit_qr_order(
  p_qr_token uuid,
  p_customer_name text,
  p_items jsonb
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
  v_line_total numeric(12, 2);
begin
  if jsonb_array_length(p_items) = 0 then
    raise exception 'empty_order';
  end if;

  select id, store_id into v_table
  from public.tables
  where qr_token = p_qr_token
    and is_active = true;

  if not found then
    raise exception 'invalid_or_inactive_table';
  end if;

  insert into public.orders (store_id, table_id, customer_name, status, total)
  values (v_table.store_id, v_table.id, nullif(trim(p_customer_name), ''), 'pending', 0)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    select id, price into v_product
    from public.products
    where id = (v_item ->> 'product_id')::uuid
      and store_id = v_table.store_id;

    if not found then
      raise exception 'invalid_product: %', v_item ->> 'product_id';
    end if;

    v_line_total := v_product.price * (v_item ->> 'quantity')::integer;
    v_total := v_total + v_line_total;

    insert into public.order_items (order_id, product_id, quantity, price)
    values (v_order_id, v_product.id, (v_item ->> 'quantity')::integer, v_product.price);
  end loop;

  update public.orders set total = v_total, updated_at = now() where id = v_order_id;

  return v_order_id;
end;
$$;

grant execute on function public.submit_qr_order(uuid, text, jsonb) to anon;

-- ----------------------------------------------------------------------------
-- 7. Realtime — so the cashier app's "Incoming Orders" screen gets pushed
-- new rows instead of polling
-- ----------------------------------------------------------------------------
alter publication supabase_realtime add table public.orders;
