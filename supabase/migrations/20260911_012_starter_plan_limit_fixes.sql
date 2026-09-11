-- Two fixes for the Starter plan, matching the current plan copy in
-- upgrade_screen.dart / index.html:
--   1. product_limit(): Starter 10 -> 50 (copy update, per
--      20260911_011_add_starter_product_limit.sql)
--   2. ai_credit_allotment(): Starter was MISSING from the CASE
--      entirely (see 20260911_010_ai_credit_free_plan_reduction.sql --
--      only free/basic/pro are handled), so any store on plan='starter'
--      fell through to `else 0` and got zero AI credits regardless of
--      what the app advertises. This is a real bug fix, not just a
--      number bump -- Starter should get 30 credits/month, same as
--      what upgrade_screen.dart has always shown.

create or replace function product_limit(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'free' then 5
    when 'starter' then 50
    when 'basic' then 30
    else null
  end;
$$;

create or replace function ai_credit_allotment(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'starter' then 30
    when 'basic' then 30
    when 'pro' then 90
    when 'free' then 10
    else 0
  end;
$$;

-- Sanity check after running:
-- select product_limit('starter'), ai_credit_allotment('starter');
-- expect 50, 30
