-- Add the Starter plan's product cap to product_limit(), matching the
-- client-side mirror in product_provider.dart's _productLimits map.
-- Free (5) and Basic (30) unchanged; Pro and anything else still
-- falls through to null (unlimited).
create or replace function product_limit(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan
    when 'free' then 5
    when 'starter' then 10
    when 'basic' then 30
    else null
  end;
$$;
