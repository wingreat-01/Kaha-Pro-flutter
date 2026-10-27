-- AI credit packs: bought credits live in their own column so the monthly
-- reset (which overwrites ai_credits_remaining) never wipes them.
-- consume_ai_credit() spends monthly credits first, then purchased ones.

-- 1) Purchased-credit balance --------------------------------------------------
alter table public.stores
  add column if not exists ai_credits_bonus integer not null default 0;
alter table public.stores drop constraint if exists stores_ai_credits_bonus_check;
alter table public.stores
  add constraint stores_ai_credits_bonus_check check (ai_credits_bonus >= 0);

-- 2) One row per pack purchase (token hash, never the raw token) -----------------
create table if not exists public.ai_credit_purchases (
  purchase_token_hash text primary key,
  store_id    uuid not null references public.stores(id) on delete cascade,
  product_id  text not null,
  credits     integer not null check (credits > 0),
  is_test     boolean not null default false,
  created_at  timestamptz not null default now(),
  refunded_at timestamptz
);
create index if not exists ai_credit_purchases_store_idx
  on public.ai_credit_purchases (store_id);
alter table public.ai_credit_purchases enable row level security; -- service role only

-- 3) Grant credits once per purchase (safe to call again with the same token) ----
create or replace function public.add_ai_credits(
  p_store_id uuid,
  p_token_hash text,
  p_product_id text,
  p_credits integer,
  p_is_test boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  insert into public.ai_credit_purchases (purchase_token_hash, store_id, product_id, credits, is_test)
  values (p_token_hash, p_store_id, p_product_id, p_credits, p_is_test)
  on conflict (purchase_token_hash) do nothing;

  if found then
    update public.stores
       set ai_credits_bonus = ai_credits_bonus + p_credits
     where id = p_store_id;
    return true;
  end if;

  select store_id into v_owner
    from public.ai_credit_purchases
   where purchase_token_hash = p_token_hash;
  if v_owner is distinct from p_store_id then
    raise exception 'purchase_linked_to_another_store';
  end if;
  return false; -- already granted earlier
end;
$$;

-- 4) Refund: take the credits back (never below zero) ----------------------------
create or replace function public.revoke_ai_credits(p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  update public.ai_credit_purchases
     set refunded_at = now()
   where purchase_token_hash = p_token_hash
     and refunded_at is null
  returning store_id, credits into v_row;

  if not found then
    return false;
  end if;

  update public.stores
     set ai_credits_bonus = greatest(ai_credits_bonus - v_row.credits, 0)
   where id = v_row.store_id;
  return true;
end;
$$;

revoke all on function public.add_ai_credits(uuid, text, text, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.add_ai_credits(uuid, text, text, integer, boolean) to service_role;
revoke all on function public.revoke_ai_credits(text) from public, anon, authenticated;
grant execute on function public.revoke_ai_credits(text) to service_role;

-- 5) Spend monthly credits first, then purchased ones ----------------------------
create or replace function public.consume_ai_credit()
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_store_id uuid := current_store_id();
  v_plan text;
  v_remaining int;
  v_reset_at timestamptz;
  v_bonus int;
begin
  if store_is_read_only(v_store_id) then
    return false;
  end if;

  select plan, ai_credits_remaining, ai_credits_reset_at, ai_credits_bonus
    into v_plan, v_remaining, v_reset_at, v_bonus
    from stores where id = v_store_id
    for update;

  if v_reset_at is null or v_reset_at < date_trunc('month', now()) then
    v_remaining := ai_credit_allotment(v_plan);
    v_reset_at := now();
  end if;

  if v_remaining > 0 then
    update stores set ai_credits_remaining = v_remaining - 1, ai_credits_reset_at = v_reset_at
      where id = v_store_id;
    return true;
  end if;

  if v_bonus > 0 then
    update stores
       set ai_credits_remaining = 0,
           ai_credits_reset_at = v_reset_at,
           ai_credits_bonus = v_bonus - 1
     where id = v_store_id;
    return true;
  end if;

  update stores set ai_credits_remaining = 0, ai_credits_reset_at = v_reset_at
    where id = v_store_id;
  return false;
end;
$function$;

create or replace function public.has_ai_credit()
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_store_id uuid := current_store_id();
  v_plan text;
  v_remaining int;
  v_reset_at timestamptz;
  v_bonus int;
begin
  select plan, ai_credits_remaining, ai_credits_reset_at, ai_credits_bonus
    into v_plan, v_remaining, v_reset_at, v_bonus
    from stores where id = v_store_id;

  if v_reset_at is null or v_reset_at < date_trunc('month', now()) then
    v_remaining := ai_credit_allotment(v_plan);
  end if;

  return v_remaining > 0 or coalesce(v_bonus, 0) > 0;
end;
$function$;
