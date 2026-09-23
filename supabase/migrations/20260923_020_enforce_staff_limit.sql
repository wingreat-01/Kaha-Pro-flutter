-- 20260923_020_enforce_staff_limit.sql
--
-- Staff-account caps were advertised in upgrade_screen.dart ('2 staff
-- accounts' on Starter, '5 staff accounts' on Basic, 'Unlimited' on
-- Pro/Free Trial) but never actually enforced anywhere -- no trigger on
-- staff_users, no client-side check. This adds the real gate, mirroring
-- product_limit()/enforce_product_limit() (see 20260818_007) exactly:
--
--   staff_limit(p_plan): free 1 / starter 2 / basic 5 / pro unlimited
--   enforce_staff_limit(): BEFORE INSERT trigger on staff_users, with
--     the same free-trial-is-unlimited treatment as products (now() <
--     stores.plan_expires_at on a 'free' plan counts as Pro-level).
--
-- Only ACTIVE staff count against the cap -- is_active=false rows are
-- the soft-deleted staff from UserProvider.deleteUser(), and those
-- shouldn't block adding a replacement.
--
-- NOTE on staff_limit('free') = 1: the blueprint only specified
-- Starter/Basic/Pro numbers. This mirrors product_limit('free') = 5
-- sitting below starter's cap -- i.e. a minimal fallback for a 'free'
-- store outside its trial window (trial-active free stores are
-- unlimited via the trial check below, same as products). Adjust if
-- you want a different post-trial free-tier number.
--
-- This fires regardless of whether the insert comes through the
-- add_staff_user() RPC or a direct table write, since it's a normal
-- BEFORE INSERT trigger on the table itself -- same as how
-- enforce_product_limit protects products no matter how a row gets
-- inserted.

create or replace function staff_limit(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'free' then 1
    when 'starter' then 2
    when 'basic' then 5
    else null              -- pro (and anything unmatched) stays unlimited
  end;
$$;

create or replace function enforce_staff_limit()
returns trigger
language plpgsql
as $function$
declare
  v_plan text;
  v_expires_at timestamptz;
  v_effective_plan text;
  v_limit int;
  v_count int;
begin
  select plan, plan_expires_at into v_plan, v_expires_at from stores where id = new.store_id;

  v_effective_plan := v_plan;
  if v_plan = 'free' and v_expires_at is not null and now() < v_expires_at then
    v_effective_plan := 'pro'; -- trial window: same cap as Pro (unlimited)
  end if;

  v_limit := staff_limit(v_effective_plan);
  if v_limit is not null then
    select count(*) into v_count
    from staff_users
    where store_id = new.store_id and is_active = true;

    if v_count >= v_limit then
      raise exception 'Staff limit reached for % plan (% max). Upgrade to add more staff accounts.',
        v_plan, v_limit
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_enforce_staff_limit on public.staff_users;
create trigger trg_enforce_staff_limit
before insert on public.staff_users
for each row execute function enforce_staff_limit();

-- Sanity check after running:
-- select staff_limit('starter'), staff_limit('basic'), staff_limit('pro');
-- expect 2, 5, NULL
