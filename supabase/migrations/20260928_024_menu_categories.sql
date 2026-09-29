-- Adds the category name to each product returned by get_menu_for_qr,
-- so the QR order page can show the same category tabs as the MERQ app.
-- Safe to re-run (CREATE OR REPLACE). Keeps the same signature/behaviour.

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
           -- to_jsonb avoids a hard failure if the column isn't literally "name"
           'category', to_jsonb(c)->>'name',
           'emoji', p.emoji,
           'image_url', p.image_url
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
