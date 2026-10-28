-- 20261028_030_qr_ordering_food_beverage_only.sql
--
-- QR Ordering (tables, customer QR menu, incoming orders) is for
-- Food & Beverage stores only. Retail / Hardware and General stores no
-- longer see it in the app (Store.supportsQrOrdering), and this makes the
-- server agree: the single gate function used by both the order-insert
-- trigger and get_menu_for_qr() now also requires
-- business_type = 'food_beverage'. Without this, a retail store that had
-- already printed table QR codes would keep receiving orders it can no
-- longer see in the app — instead the customer page now reports that
-- ordering is unavailable.
--
-- Run AFTER 20261019_023_lifetime_limits_and_qr_gate.sql. The plan rules
-- below are unchanged from 023; only the business-type check is new.
-- Existing tables/orders rows for non-F&B stores are left in place (not
-- deleted), so switching a store to Food & Beverage restores everything.

create or replace function public.store_has_qr_ordering(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when s.business_type is distinct from 'food_beverage' then false
      when s.plan = 'expired' then false
      when s.plan_expires_at is not null and s.plan_expires_at < now() then false
      when s.plan in ('pro', 'lifetime') then true
      when s.plan = 'free' then s.plan_expires_at is not null
      else false
    end
    from public.stores s
    where s.id = p_store_id
  ), false);
$$;

revoke execute on function public.store_has_qr_ordering(uuid) from public, anon, authenticated;

create or replace function public.enforce_qr_ordering_plan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.store_has_qr_ordering(new.store_id) then
    raise exception 'qr_ordering_not_available'
      using hint = 'QR Ordering is for Food & Beverage stores on the Pro or Lifetime plan.';
  end if;
  return new;
end;
$$;
