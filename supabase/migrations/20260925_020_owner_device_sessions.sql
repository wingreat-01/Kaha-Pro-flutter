-- Single-active-device enforcement for store owners.
--
-- Supabase Auth (GoTrue) allows multiple concurrent sessions per user by
-- default and has no built-in "only one device at a time" setting -- this
-- migration builds that behavior ourselves. Approach: track which
-- device_id currently "holds" each owner's session in a small table, and
-- block a sign-in from any other device_id unless the caller explicitly
-- forces the claim (recovery path if the original device is lost/
-- uninstalled). Enforcement happens client-side around
-- signInWithPassword() (see store_setup_screen.dart) -- this migration
-- only provides the RPCs it calls.
--
-- Only 1 owner per store today (store_members is 1:1 owner<->store), so
-- this is keyed on owner_id directly rather than store_id.

create table if not exists public.owner_active_sessions (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  device_id text not null,
  device_label text,
  claimed_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

alter table public.owner_active_sessions enable row level security;

-- Read-only for the owner themselves (e.g. to show "signed in on
-- <device_label> since <date>" in a future Settings screen). All writes
-- go through the security-definer RPCs below, not direct table access --
-- there are deliberately no insert/update/delete policies, so a client
-- can't just overwrite the row by hand and bypass the block.
create policy "owner can read own device session"
  on public.owner_active_sessions for select
  using (auth.uid() = owner_id);

-- Called right after signInWithPassword() succeeds on the signing-in
-- device. Claims the session for p_device_id if no row exists yet, if
-- the row already belongs to this same device_id (re-login on the same
-- device/reinstall-with-restored-prefs), or if p_force is true.
-- Otherwise refuses and reports which device currently holds it, so the
-- caller can sign this new session back out and show a message.
create or replace function public.claim_device_session(
  p_device_id text,
  p_device_label text default null,
  p_force boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing record;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_existing
  from owner_active_sessions
  where owner_id = auth.uid()
  for update;

  if v_existing is null or v_existing.device_id = p_device_id or p_force then
    insert into owner_active_sessions (owner_id, device_id, device_label, claimed_at, last_seen_at)
    values (auth.uid(), p_device_id, p_device_label, now(), now())
    on conflict (owner_id) do update
      set device_id = excluded.device_id,
          device_label = excluded.device_label,
          claimed_at = now(),
          last_seen_at = now();
    return jsonb_build_object('allowed', true);
  end if;

  return jsonb_build_object(
    'allowed', false,
    'existing_device_label', v_existing.device_label,
    'existing_claimed_at', v_existing.claimed_at
  );
end;
$$;

-- Cheap "am I still the claimed device" heartbeat, called from the
-- device currently holding the session (see main.dart). Returns false
-- if another device has since forced a claim, so the caller knows to
-- sign itself out locally.
create or replace function public.touch_device_session(p_device_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row_count integer;
begin
  update owner_active_sessions
    set last_seen_at = now()
    where owner_id = auth.uid() and device_id = p_device_id;

  get diagnostics v_row_count = row_count;

  return v_row_count > 0;
end;
$$;

grant execute on function public.claim_device_session(text, text, boolean) to authenticated;
grant execute on function public.touch_device_session(text) to authenticated;
