-- ============================================================================
-- Follow-up to 20260928_020 / 021 / 022
-- Suggested filename: supabase/migrations/20260928_023_fix_menu_image_column.sql
--
-- Bug fix: get_menu_for_qr referenced p.image_path, but the real
-- column (confirmed from product_provider.dart) is image_url. That
-- mismatch made the function throw "column p.image_path does not
-- exist" on every call, which order.html surfaced as its generic
-- "Can't load this menu / Something went wrong" error.
-- ============================================================================

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
           'image_url', p.image_url
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
