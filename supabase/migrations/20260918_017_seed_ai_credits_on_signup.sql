-- 20260918_017_seed_ai_credits_on_signup.sql
--
-- Bug: handle_new_user() inserts a new stores row with no
-- ai_credits_remaining/ai_credits_reset_at values, so both sit at
-- their raw column defaults (0 / null) from the moment a store is
-- created. consume_ai_credit()/has_ai_credit() DO correctly detect
-- ai_credits_reset_at is null and would reset to the real allotment
-- (10 for 'free') the moment the store's first AI call fires -- but
-- until that first call happens, Store.aiCreditsRemaining in the app
-- reads the raw 0 straight off the row, so a brand-new account shows
-- "0 credits left this month" even though the true number is 10.
--
-- Fix: seed the real allotment directly in handle_new_user(), so the
-- row is correct from the first read, not just after first use.
--
-- Reset semantics note: this uses date_trunc('month', now()) to match
-- what has_ai_credit()/consume_ai_credit() already check against --
-- NOT grant_plan_credits()'s now() + interval '30 days' rolling
-- window, which is a separate, currently-inconsistent convention on
-- the same column (flagged, not fixed here -- see chat).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  new_store_id uuid;
begin
  insert into stores (
    name,
    business_type,
    ai_credits_remaining,
    ai_credits_reset_at
  )
  values (
    coalesce(NEW.raw_user_meta_data->>'store_name', 'My Store'),
    coalesce(NEW.raw_user_meta_data->>'business_type', 'general'),
    ai_credit_allotment('free'), -- every new store starts on the free plan
    now()
  )
  returning id into new_store_id;

  -- Firing this insert also fires trg_seed_uncategorized above, so the
  -- new store's Uncategorized category exists before anyone logs in.
  insert into store_members (store_id, auth_user_id, role)
  values (new_store_id, NEW.id, 'owner');

  return NEW;
end;
$function$;

-- Backfill: any existing store still sitting at the broken default
-- (0 credits, never reset) gets corrected the same way
-- consume_ai_credit() would have corrected it on first use -- this
-- just does it immediately instead of waiting for that first call.
-- Scoped tightly (ai_credits_remaining = 0 AND ai_credits_reset_at is
-- null) so it only touches rows that never got a real value, not any
-- store that has legitimately run its credits down to 0 through use.
update stores
set ai_credits_remaining = ai_credit_allotment(plan),
    ai_credits_reset_at = now()
where ai_credits_remaining = 0
  and ai_credits_reset_at is null;
