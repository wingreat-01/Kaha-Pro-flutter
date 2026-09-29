-- ============================================================================
-- MERQ QR Ordering -- sizes / variants
-- Suggested filename: supabase/migrations/20260929_025_qr_order_variants.sql
--
-- 1. order_items gets variant_id + variant_name (name is snapshotted so the
--    order line stays correct if the size is renamed or deleted later).
-- 2. get_menu_for_qr now returns each product's sizes as
--    variants: [{id, name, price}], ordered by sort_order. For a product that
--    has sizes, `price` is the lowest size price (the page shows "From ...").
--    Everything from 024 is kept: category, show_on_qr_menu + stock filters.
-- 3. submit_qr_order accepts an optional variant_id per item, validates it
--    belongs to that product/store, and prices the line from the database.
--    A product that has sizes now REQUIRES a variant_id.
--
-- Safe to re-run: columns use IF NOT EXISTS, functions use CREATE OR REPLACE.
-- ============================================================================

alter table public.order_items
  add column if not exists variant_id uuid references public.product_variants(id) on delete set null,
  add column if not exists variant_name text;

-- ----------------------------------------------------------------------------
-- get_menu_for_qr
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
    'products', v_products
  );
end;
$$;

grant execute on function public.get_menu_for_qr(uuid) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- submit_qr_order
-- p_items shape: [{"product_id": "...", "variant_id": "..." | null, "quantity": 2}, ...]
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
  v_variant record;
  v_variant_id uuid;
  v_qty integer;
  v_unit_price numeric(12, 2);
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

grant execute on function public.submit_qr_order(uuid, text, jsonb) to anon;
