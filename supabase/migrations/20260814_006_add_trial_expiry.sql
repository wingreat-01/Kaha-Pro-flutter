-- Auto-sets stores.plan_expires_at to a 15-day trial window for
-- free-plan stores. Implemented as a BEFORE INSERT trigger on
-- `stores` directly (not folded into handle_new_user) so it applies
-- regardless of exactly how a store row gets created, and so it's a
-- single self-contained migration independent of that trigger's
-- current definition.
--
-- Only fires when plan = 'free' AND plan_expires_at wasn't already
-- supplied — a paid plan (basic/pro) or a manually-set expiry is left
-- untouched. 'expired' (the manual testing value used for the
-- trial-expired banner, see kahapro-subscription-plan.md) is not
-- 'free', so this trigger never overwrites that either.
create or replace function set_default_trial_expiry()
returns trigger
language plpgsql
as $$
begin
  if new.plan = 'free' and new.plan_expires_at is null then
    new.plan_expires_at := coalesce(new.created_at, now()) + interval '15 days';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_default_trial_expiry on stores;
create trigger trg_set_default_trial_expiry
  before insert on stores
  for each row
  execute function set_default_trial_expiry();

-- Backfill: existing free-plan stores created before this trigger
-- existed (e.g. Flynn's Coffee, BiryaniKing) currently show
-- plan_expires_at = NULL. Give them the same 15-day-from-created_at
-- window retroactively rather than leaving old stores permanently
-- exempt from expiry. Paid-plan stores and anything already set are
-- untouched by the WHERE clause.
update stores
set plan_expires_at = created_at + interval '15 days'
where plan = 'free' and plan_expires_at is null;
