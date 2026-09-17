-- 20260917_015_grant_plan_credits.sql
--
-- ai_credit_allotment(p_plan) already exists and returns the right
-- number for a plan -- but nothing before now actually applies that
-- number to a specific store's ai_credits_remaining on demand. This
-- is called by the verify-purchase Edge Function immediately after a
-- verified Play Billing purchase, so a new subscriber sees their
-- plan's real credit count right away instead of waiting for
-- whatever the existing monthly reset job's schedule happens to be.
--
-- security definer + locked to service_role only, same reasoning as
-- delete_account_cascade: this must be able to write ai_credits_remaining
-- regardless of what RLS policies exist for authenticated users, and
-- must never be callable by a client directly (a client calling this
-- on its own plan would be a free way to refill credits without
-- paying).
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
      ai_credits_reset_at = now() + interval '30 days'
  where id = p_store_id;
end;
$$;

revoke all on function public.grant_plan_credits(uuid) from public, anon, authenticated;
grant execute on function public.grant_plan_credits(uuid) to service_role;
