-- Lifetime plan, server side:
--   1. QR ordering becomes Pro + Lifetime only (Basic no longer allowed).
--   2. Lifetime gets Pro's AI credit allotment.
-- product_limit() and staff_limit() already return NULL (unlimited) for any
-- plan they don't list, so 'lifetime' is unlimited there without changes.

-- 1) QR ordering gate ---------------------------------------------------------
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
      when s.plan in ('pro', 'lifetime') then true
      when s.plan = 'free' then s.plan_expires_at is not null
      else false
    end
    from public.stores s
    where s.id = p_store_id
  ), false);
$$;

-- Same trigger function as 027, only the hint text changes.
create or replace function public.enforce_qr_ordering_plan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.store_has_qr_ordering(new.store_id) then
    raise exception 'qr_ordering_not_available'
      using hint = 'QR Ordering requires the Pro or Lifetime plan.';
  end if;
  return new;
end;
$$;

-- 2) AI credits ---------------------------------------------------------------
create or replace function public.ai_credit_allotment(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'free' then 10
    when 'starter' then 30
    when 'basic' then 50
    when 'pro' then 100
    when 'lifetime' then 100
    else 0
  end;
$$;
