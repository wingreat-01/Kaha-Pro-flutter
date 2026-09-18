-- Table for tracking pending account-deletion confirmation links.
-- A row is created when someone submits the delete-account form,
-- and consumed (used_at set) when they click the confirmation link.
create table if not exists account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  token text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);

create index if not exists idx_account_deletion_requests_token
  on account_deletion_requests (token);

-- No public RLS policy is created here on purpose: this table is only
-- ever read/written by Edge Functions using the service role key,
-- which bypasses RLS. Nothing about it needs to be client-readable.
