-- Drop the Free Trial's AI credit allotment from 20 -> 10, matching
-- the updated plan copy in upgrade_screen.dart. Basic (30) and Pro
-- (90) are unchanged -- only the 'free' branch moves.
create or replace function ai_credit_allotment(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'basic' then 30
    when 'pro' then 90
    when 'free' then 10 -- was 20 as of 20260818_008
    else 0
  end;
$$;
