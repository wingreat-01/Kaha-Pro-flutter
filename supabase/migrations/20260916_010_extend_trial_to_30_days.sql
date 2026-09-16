-- Extends the free-plan trial window set by 006_add_trial_expiry.sql
-- from 15 days to 30 days. Only changes the trigger function, so this
-- affects stores created from here on — deliberately NOT backfilling
-- existing free-plan stores, which keep whatever plan_expires_at they
-- were already given (15 days from their created_at).
create or replace function set_default_trial_expiry()
returns trigger
language plpgsql
as $$
begin
  if new.plan = 'free' and new.plan_expires_at is null then
    new.plan_expires_at := coalesce(new.created_at, now()) + interval '30 days';
  end if;
  return new;
end;
$$;

-- Trigger itself is unchanged (still calls set_default_trial_expiry),
-- so no drop/create needed here — replacing the function body is
-- enough since the trigger just invokes it by name.
