-- ============================================================================
-- Follow-up to 20260928_020_qr_ordering_core.sql / 021
-- Suggested filename: supabase/migrations/20260928_022_qr_menu_visibility.sql
--
-- Replaces the original get_menu_for_qr's stock-based menu filter
-- (`stock_qty > 0 or stock_qty is null`) with an explicit owner-set
-- flag. The old filter wrongly hid untracked items (trackStock=false,
-- e.g. "Chicken Fillet w/ rice") whenever their stock_qty happened to
-- be 0, which is the normal/default state for something nobody counts.
--
-- New behavior: show_on_qr_menu (owner-controlled, defaults true so
-- every existing product shows up automatically) is the primary gate.
-- On top of that, a *tracked*-stock item still gets hidden once its
-- stock_qty hits 0, regardless of the flag, so customers can't order
-- something that's actually sold out — untracked items have no such
-- check, since stock_qty isn't meaningful for them.
-- ============================================================================

alter table public.products
  add column show_on_qr_menu boolean not null default true;

-- Replaces "anon can view orderable products" from the core migration
-- (stock-based) with the same logic get_menu_for_qr now uses.
drop policy if exists "anon can view orderable products" on public.products;

create policy "anon can view qr-menu products"
  on public.products
  for select
  to anon
  using (
    show_on_qr_menu = true
    and (track_stock = false or stock_qty > 0)
  );

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
