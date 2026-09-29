-- Lets a brand-new Google sign-up name their store.
-- handle_new_user() creates the store as 'My Store' when the sign-up has
-- no store_name metadata (Google sign-in never has any). This renames it,
-- but ONLY if the caller is an owner of a store still called 'My Store',
-- so it can never overwrite a real store name.

create or replace function public.set_initial_store_details(
  p_name text,
  p_business_type text default 'general'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if p_name is null or btrim(p_name) = '' then
    raise exception 'invalid_store_name';
  end if;

  select s.id into v_store_id
  from public.store_members m
  join public.stores s on s.id = m.store_id
  where m.auth_user_id = auth.uid()
    and m.role = 'owner'
    and s.name = 'My Store'
  limit 1;

  if v_store_id is null then
    return; -- nothing to do: store already has a real name
  end if;

  update public.stores
  set name = btrim(p_name),
      business_type = coalesce(p_business_type, 'general')
  where id = v_store_id;
end;
$$;

revoke all on function public.set_initial_store_details(text, text) from public, anon;
grant execute on function public.set_initial_store_details(text, text) to authenticated;
