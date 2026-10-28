-- 20261028_029_employees_timeclock_payroll.sql
--
-- Employees, selfie + PIN time clock, and daily-rate payroll. Run once in
-- the Supabase SQL editor.
--
-- Design notes
--  * Employees are their own list, separate from staff_users (POS logins):
--    a cook or helper can clock in without being able to ring up sales.
--  * Employee PINs live in employee_pins, which has RLS on and NO policies
--    or grants, so the hash never reaches a client. Only the SECURITY
--    DEFINER functions below read/write it. Hashing uses pgcrypto's
--    bcrypt (crypt + gen_salt('bf')) — Supabase installs pgcrypto in the
--    `extensions` schema, hence the qualified calls.
--  * clock_punch() decides time-in vs time-out and stamps the SERVER's
--    now(), so a device with a wrong/edited clock can't shift hours.
--  * Each punch carries a selfie stored in the private `timeclock-photos`
--    bucket under <auth uid>/<employee id>/<uuid>.jpg (same uid-folder
--    convention as product images), viewed by the owner via signed URLs.
--    The app uploads a ~320 px copy (~15–25 KB) and deletes photos older
--    than the owner's retention period (30–180 days, default 90) through
--    the Storage API — see PayrollProvider.purgeOldPhotos. Nothing here
--    deletes them: removing storage.objects rows in SQL would leave the
--    files behind. Time records are kept; only their photo paths clear.
--  * Payroll math runs in the app (lib/services/payroll_calculator.dart);
--    a saved run stores a full snapshot per employee so later rate or
--    schedule changes never rewrite past payslips.

create extension if not exists pgcrypto with schema extensions;

-- 1) Employees -------------------------------------------------------------
create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id() references stores(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  position text,
  daily_rate numeric(12, 2) not null default 0 check (daily_rate >= 0),
  -- Scheduled shift, used for late / undertime / overtime. shift_end at or
  -- before shift_start means an overnight shift (ends the next day).
  shift_start time not null default '08:00',
  shift_end time not null default '17:00',
  break_minutes int not null default 60 check (break_minutes between 0 and 600),
  late_grace_minutes int not null default 0 check (late_grace_minutes between 0 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists employees_store_name_key
  on public.employees (store_id, lower(trim(name)));

alter table public.employees enable row level security;
drop policy if exists "store scoped access" on public.employees;
create policy "store scoped access" on public.employees
  for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());

-- 2) Employee PINs (server-only) --------------------------------------------
create table if not exists public.employee_pins (
  employee_id uuid primary key references public.employees(id) on delete cascade,
  pin_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz
);

alter table public.employee_pins enable row level security;
-- No policies on purpose: only the SECURITY DEFINER functions touch this.
revoke all on public.employee_pins from anon, authenticated;

-- 3) Time entries ------------------------------------------------------------
create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id() references stores(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  clock_in timestamptz not null,
  clock_out timestamptz,
  in_photo_path text,
  out_photo_path text,
  source text not null default 'clock' check (source in ('clock', 'manual')),
  -- Set when a punch had to auto-close a forgotten time-out (see
  -- clock_punch); the owner fixes it in Time Records.
  needs_review boolean not null default false,
  note text,
  edited_by text,
  created_at timestamptz not null default now(),
  check (clock_out is null or clock_out >= clock_in)
);

create index if not exists time_entries_employee_clock_in_idx
  on public.time_entries (employee_id, clock_in desc);
create index if not exists time_entries_store_clock_in_idx
  on public.time_entries (store_id, clock_in desc);
-- At most one open (not yet timed-out) entry per employee.
create unique index if not exists time_entries_one_open_per_employee
  on public.time_entries (employee_id) where clock_out is null;

alter table public.time_entries enable row level security;
drop policy if exists "store scoped access" on public.time_entries;
create policy "store scoped access" on public.time_entries
  for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());

-- 4) Payroll runs + payslips --------------------------------------------------
create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id() references stores(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  overtime_paid boolean not null default false,
  overtime_multiplier numeric(5, 2) not null default 1.25,
  total_net numeric(14, 2) not null default 0,
  created_by text,
  created_at timestamptz not null default now(),
  check (period_end >= period_start)
);

create table if not exists public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id() references stores(id) on delete cascade,
  run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete set null,
  employee_name text not null,
  daily_rate numeric(12, 2) not null,
  days_worked int not null default 0,
  late_minutes int not null default 0,
  undertime_minutes int not null default 0,
  overtime_minutes int not null default 0,
  basic_pay numeric(14, 2) not null default 0,
  overtime_pay numeric(14, 2) not null default 0,
  late_deduction numeric(14, 2) not null default 0,
  undertime_deduction numeric(14, 2) not null default 0,
  -- [{ "label": "Cash advance", "amount": 500, "kind": "deduction" }, ...]
  adjustments jsonb not null default '[]'::jsonb,
  gross_pay numeric(14, 2) not null default 0,
  total_deductions numeric(14, 2) not null default 0,
  net_pay numeric(14, 2) not null default 0
);

create index if not exists payroll_items_run_idx on public.payroll_items (run_id);

alter table public.payroll_runs enable row level security;
drop policy if exists "store scoped access" on public.payroll_runs;
create policy "store scoped access" on public.payroll_runs
  for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());

alter table public.payroll_items enable row level security;
drop policy if exists "store scoped access" on public.payroll_items;
create policy "store scoped access" on public.payroll_items
  for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());

-- 5) Set / reset an employee's PIN -------------------------------------------
create or replace function public.set_employee_pin(p_employee_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $function$
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,8}$' then
    raise exception 'PIN must be 4 to 8 digits.' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from employees where id = p_employee_id and store_id = current_store_id()
  ) then
    raise exception 'Employee not found.' using errcode = 'P0002';
  end if;

  insert into employee_pins (employee_id, pin_hash, failed_attempts, locked_until)
  values (p_employee_id, crypt(p_pin, gen_salt('bf')), 0, null)
  on conflict (employee_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null;
end;
$function$;

revoke all on function public.set_employee_pin(uuid, text) from public, anon;
grant execute on function public.set_employee_pin(uuid, text) to authenticated;

-- Which employees have a PIN yet (for the Employees list) — never the hash.
create or replace function public.employees_with_pin()
returns setof uuid
language sql
security definer
set search_path = public
stable
as $function$
  select p.employee_id
  from employee_pins p
  join employees e on e.id = p.employee_id
  where e.store_id = current_store_id();
$function$;

revoke all on function public.employees_with_pin() from public, anon;
grant execute on function public.employees_with_pin() to authenticated;

-- 6) Time in / time out -------------------------------------------------------
--
-- Returns jsonb rather than raising on a wrong PIN, so the failed-attempt
-- counter it just incremented is actually committed (an exception would
-- roll it back and make the lockout useless):
--   { ok: true,  action: 'in'|'out', at, employee_name, entry_id, closed_missed_out }
--   { ok: false, error: '<message for the employee>' }
create or replace function public.clock_punch(
  p_employee_id uuid,
  p_pin text,
  p_photo_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_emp employees;
  v_pin employee_pins;
  v_open time_entries;
  v_entry_id uuid;
  v_now timestamptz := now();
  v_closed_missed boolean := false;
begin
  select * into v_emp
  from employees
  where id = p_employee_id and store_id = current_store_id() and is_active;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Employee not found.');
  end if;

  select * into v_pin from employee_pins where employee_id = v_emp.id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'No PIN set yet. Ask your admin to set one.');
  end if;

  if v_pin.locked_until is not null and v_pin.locked_until > v_now then
    return jsonb_build_object('ok', false, 'error',
      format('Too many wrong PINs. Try again in %s min.',
             ceil(extract(epoch from (v_pin.locked_until - v_now)) / 60)::int));
  end if;

  if p_pin is null or crypt(p_pin, v_pin.pin_hash) <> v_pin.pin_hash then
    update employee_pins
       set failed_attempts = case when v_pin.failed_attempts + 1 >= 5 then 0 else v_pin.failed_attempts + 1 end,
           locked_until = case when v_pin.failed_attempts + 1 >= 5 then v_now + interval '15 minutes' else null end
     where employee_id = v_emp.id;
    return jsonb_build_object('ok', false, 'error', 'Wrong PIN.');
  end if;

  update employee_pins set failed_attempts = 0, locked_until = null where employee_id = v_emp.id;

  select * into v_open
  from time_entries
  where employee_id = v_emp.id and clock_out is null
  for update;

  if found and v_now - v_open.clock_in > interval '16 hours' then
    -- Forgotten time-out from an earlier shift: close it at its own
    -- start (zero hours) and flag it, then treat this punch as a new
    -- time-in. The owner sets the real time-out in Time Records.
    update time_entries
       set clock_out = clock_in,
           needs_review = true,
           note = coalesce(note || ' · ', '') || 'Missed time-out'
     where id = v_open.id;
    v_closed_missed := true;
  elsif found then
    if v_now - v_open.clock_in < interval '1 minute' then
      return jsonb_build_object('ok', false, 'error', 'You just timed in. Wait a minute before timing out.');
    end if;
    update time_entries
       set clock_out = v_now, out_photo_path = p_photo_path
     where id = v_open.id;
    return jsonb_build_object('ok', true, 'action', 'out', 'at', v_now,
      'employee_name', v_emp.name, 'entry_id', v_open.id, 'closed_missed_out', false);
  end if;

  insert into time_entries (store_id, employee_id, clock_in, in_photo_path)
  values (v_emp.store_id, v_emp.id, v_now, p_photo_path)
  returning id into v_entry_id;

  return jsonb_build_object('ok', true, 'action', 'in', 'at', v_now,
    'employee_name', v_emp.name, 'entry_id', v_entry_id, 'closed_missed_out', v_closed_missed);
end;
$function$;

revoke all on function public.clock_punch(uuid, text, text) from public, anon;
grant execute on function public.clock_punch(uuid, text, text) to authenticated;

-- 7) Private bucket for time clock selfies ------------------------------------
insert into storage.buckets (id, name, public)
values ('timeclock-photos', 'timeclock-photos', false)
on conflict (id) do nothing;

drop policy if exists "timeclock photos own folder read" on storage.objects;
create policy "timeclock photos own folder read" on storage.objects
  for select to authenticated
  using (bucket_id = 'timeclock-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "timeclock photos own folder insert" on storage.objects;
create policy "timeclock photos own folder insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'timeclock-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "timeclock photos own folder delete" on storage.objects;
create policy "timeclock photos own folder delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'timeclock-photos' and (storage.foldername(name))[1] = auth.uid()::text);
