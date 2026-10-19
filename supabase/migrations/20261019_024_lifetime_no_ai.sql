-- Lifetime plan does not include the AI assistant (it costs per use).
-- Run after 023. Lifetime gets 0 credits; everything else is unchanged.
-- An AI add-on purchase for Lifetime can raise this later.
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
    when 'lifetime' then 0
    else 0
  end;
$$;
