-- 1. Bump ai_credit_allotment() to match the new plan copy in
--    upgrade_screen.dart: Basic 10 -> 30, Pro & Free 30 -> 90.
--    (Adjust the CASE branches below to match your actual existing
--    function body -- this assumes a simple plan -> flat number
--    mapping. Run `select pg_get_functiondef('ai_credit_allotment'::regproc);`
--    first to confirm the current shape before replacing it.)
create or replace function ai_credit_allotment(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'basic' then 30
    when 'pro' then 90
    when 'free' then 20 -- capped below Pro's 90, not a full mirror (was 90 until this change)
    else 0
  end;
$$;

-- 2. Lightweight usage log so future credit-ceiling decisions (like
--    this one) can be made on real fallback-hit-rate data instead of
--    judgment calls. One row per AI assistant request that actually
--    succeeded -- i.e. insert this right alongside consume_ai_credit(),
--    not on every attempt, so it reflects real cost/usage the same
--    way credit consumption already does.
create table if not exists ai_usage_log (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references stores(id),
  provider text not null, -- 'groq' | 'mistral' | 'gemini' | 'openrouter' | 'deepseek' | 'openai'
  is_paid_tier boolean not null, -- true for deepseek/openai fallbacks, false for the 4 free tiers
  created_at timestamptz not null default now()
);

create index if not exists ai_usage_log_store_id_created_at_idx
  on ai_usage_log (store_id, created_at);

alter table ai_usage_log enable row level security;

-- Store-scoped read access, same pattern as every other table --
-- an owner should be able to see their own store's usage breakdown
-- eventually (e.g. a future "AI usage" card in Reports), even though
-- nothing reads this yet.
create policy "ai_usage_log_select_own_store"
  on ai_usage_log for select
  using (store_id = current_store_id());

-- No insert/update/delete policies for authenticated users --
-- this table is only ever written by the ai-assistant Edge Function,
-- which uses the service role key and bypasses RLS entirely.
