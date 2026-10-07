-- ============================================================================
-- MERQ QR Ordering — server-side plan gate (Basic / Pro only)
-- Suggested filename: supabase/migrations/20261007_027_qr_ordering_plan_gate.sql
--   (027 assumes 026_qr_order_payments.sql is your latest — double-check.)
--
-- Mirrors Store.canUseQrOrdering in the Flutter app:
--   plan = 'expired'                       -> locked
--   plan_expires_at in the past            -> locked (trial/plan lapsed)
--   plan in ('basic', 'pro')               -> allowed
--   plan = 'free' with an unexpired trial  -> allowed (trial mirrors Pro)
--   anything else ('starter', unknown)     -> locked
--
-- Deliberately does NOT redefine submit_qr_order(): later migrations (e.g.
-- 026 payments) may have changed it, and replacing it from the 020 copy
-- would silently undo that. Instead:
--   1. a BEFORE INSERT trigger on orders blocks new orders for locked stores
--      (every order, however created, goes through that insert), and
--   2. get_menu_for_qr() is wrapped, so the customer page also finds out
--      up front that ordering is unavailable instead of failing at submit.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Single source of truth for "does this store's plan include QR ordering"
-- ----------------------------------------------------------------------------
create or replace function public.store_has_qr_ordering(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when s.plan = 'expired' then false
      when s.plan_expires_at is not null and s.plan_expires_at < now() then false
      when s.plan in ('basic', 'pro') then true
      when s.plan = 'free' then s.plan_expires_at is not null
      else false
    end
    from public.stores s
    where s.id = p_store_id
  ), false);
$$;

-- Only called from the definer functions below; no reason to expose it.
revoke execute on function public.store_has_qr_ordering(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. Block new orders for stores without QR ordering
-- ----------------------------------------------------------------------------
create or replace function public.enforce_qr_ordering_plan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.store_has_qr_ordering(new.store_id) then
    raise exception 'qr_ordering_not_available'
      using hint = 'QR Ordering requires the Basic or Pro plan.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_qr_ordering_plan on public.orders;
create trigger trg_enforce_qr_ordering_plan
  before insert on public.orders
  for each row execute function public.enforce_qr_ordering_plan();

-- ----------------------------------------------------------------------------
-- 3. Gate the menu lookup without touching its body: rename the existing
--    function and put a checking wrapper under the original name (so the
--    customer page keeps calling get_menu_for_qr unchanged). Guarded so
--    re-running this migration doesn't rename the wrapper over the original.
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.get_menu_for_qr_inner(uuid)') is null then
    alter function public.get_menu_for_qr(uuid) rename to get_menu_for_qr_inner;
    revoke execute on function public.get_menu_for_qr_inner(uuid)
      from public, anon, authenticated;
  end if;
end $$;

create or replace function public.get_menu_for_qr(p_qr_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  select store_id into v_store_id
  from public.tables
  where qr_token = p_qr_token
    and is_active = true;

  -- Unknown/inactive token: fall through so the original function raises
  -- its usual invalid_or_inactive_table error.
  if v_store_id is not null and not public.store_has_qr_ordering(v_store_id) then
    raise exception 'qr_ordering_not_available';
  end if;

  return public.get_menu_for_qr_inner(p_qr_token);
end;
$$;

grant execute on function public.get_menu_for_qr(uuid) to anon;
