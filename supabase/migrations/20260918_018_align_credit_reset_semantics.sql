-- 20260918_018_align_credit_reset_semantics.sql
--
-- Bug: two different "what does ai_credits_reset_at mean" conventions
-- were living on the same column. has_ai_credit()/consume_ai_credit()
-- (20260818_008) treat it as "the last time credits were reset,"
-- compared against date_trunc('month', now()) -- a calendar-month
-- lazy reset that doesn't care what day of the month it lands on.
-- grant_plan_credits() (20260917_015) instead set it to
-- now() + interval '30 days', a rolling 30-day window -- a different
-- meaning for the same value.
--
-- In practice this meant a store's reset cadence silently depended on
-- which function last touched the column: sign up and go stale ->
-- calendar-month reset (via consume_ai_credit); make a purchase ->
-- suddenly on a rolling 30-day cycle instead, until the next calendar-
-- month check overwrites it again. Not a data-loss bug, but an
-- inconsistent and unpredictable one.
--
-- Fix: grant_plan_credits() now sets ai_credits_reset_at = now(), the
-- same "mark this as the last reset point" value consume_ai_credit()
-- already writes on its own lazy reset. The date_trunc('month', now())
-- comparison in has_ai_credit()/consume_ai_credit() is the single
-- source of truth for *when* the next reset happens; every writer of
-- this column now agrees on what a fresh value means.
create or replace function public.grant_plan_credits(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
begin
  select plan into v_plan from public.stores where id = p_store_id;
  if v_plan is null then
    raise exception 'Store % not found', p_store_id;
  end if;

  update public.stores
  set ai_credits_remaining = ai_credit_allotment(v_plan),
      ai_credits_reset_at = now()
  where id = p_store_id;
end;
$$;

revoke all on function public.grant_plan_credits(uuid) from public, anon, authenticated;
grant execute on function public.grant_plan_credits(uuid) to service_role;
