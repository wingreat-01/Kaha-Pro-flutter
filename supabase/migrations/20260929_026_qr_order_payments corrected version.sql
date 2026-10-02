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
           'description', to_jsonb(p)->>'description',
           'price', coalesce(
             (select min(v.price) from public.product_variants v where v.product_id = p.id),
             p.price
           ),
           'category_id', p.category_id,
           'category', to_jsonb(c)->>'name',
           'emoji', p.emoji,
           'image_url', p.image_url,
           'track_stock', p.track_stock,
           'stock_qty', p.stock_qty,
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