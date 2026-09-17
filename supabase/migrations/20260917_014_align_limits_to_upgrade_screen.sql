-- 20260917_014_align_limits_to_upgrade_screen.sql
--
-- upgrade_screen.dart is confirmed as the source of truth for what
-- Basic and Pro actually promise; product_limit()/ai_credit_allotment()
-- were out of sync with it (Basic showed 200 products/50 credits,
-- Pro showed 100 credits -- DB only granted 30/30/90 respectively).
-- Free and Starter were already correct and are unchanged.

create or replace function product_limit(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'free' then 5
    when 'starter' then 50
    when 'basic' then 200   -- was 30
    else null               -- pro stays unlimited
  end;
$$;

create or replace function ai_credit_allotment(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'free' then 10
    when 'starter' then 30
    when 'basic' then 50    -- was 30
    when 'pro' then 100     -- was 90
    else 0
  end;
$$;

-- Sanity check after running:
-- select product_limit('basic'), ai_credit_allotment('basic'), ai_credit_allotment('pro');
-- expect 200, 50, 100

-- NOTE: this only changes what the function computes going forward.
-- Any store already on Basic/Pro that was granted ai_credits_remaining
-- under the old allotment (30 or 90) this cycle won't be bumped to
-- 50/100 until their next monthly reset. If you want existing
-- subscribers topped up immediately instead of waiting for their
-- reset date, run this after the migration above:
--
-- update stores
-- set ai_credits_remaining = ai_credit_allotment(plan)
-- where plan in ('basic', 'pro');
