-- Fixes enforce_product_limit() to respect the free-plan trial window
-- introduced in 20260814_006_add_trial_expiry.sql. That migration set
-- plan_expires_at on 'free' stores (15 days from creation) but never
-- taught the product-limit trigger about it -- so a store still inside
-- its trial (marketed everywhere as "Free Trial: unlimited products,
-- everything in Pro") was silently capped at the real free-tier limit
-- of 5 the whole time.
--
-- Behavior: plan = 'free' AND now() < plan_expires_at is treated as
-- unlimited (Pro-level), matching the "Free Trial" plan card's stated
-- benefits. Once the trial expires (or for a store that was never on
-- trial -- plan_expires_at null on a free plan), product_limit('free')
-- applies as before. Paid plans (basic/pro) and the manual 'expired'
-- testing value are untouched, since neither passes plan = 'free'.
create or replace function enforce_product_limit()
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

  v_limit := product_limit(v_effective_plan);
  if v_limit is not null then
    select count(*) into v_count from products where store_id = new.store_id;
    if v_count >= v_limit then
      raise exception 'Product limit reached for % plan (% max). Upgrade to add more products.',
        v_plan, v_limit
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$function$;
