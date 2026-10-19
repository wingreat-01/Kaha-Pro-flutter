-- Lets a product be deleted even if customers ordered it through the QR menu.
-- Before: order_items.product_id was ON DELETE RESTRICT, which blocked the delete.
-- After:  the line keeps a product_name snapshot and product_id becomes NULL.
-- Safe to run more than once.

begin;

-- 1. Name snapshot, so old QR orders still show the item name after deletion.
alter table public.order_items add column if not exists product_name text;

update public.order_items oi
set product_name = p.name
from public.products p
where p.id = oi.product_id
  and oi.product_name is null;

-- 2. Fill the snapshot automatically on every new order line (no change
--    needed in the QR menu code that inserts them).
create or replace function public.order_items_snapshot_product_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.product_name is null and new.product_id is not null then
    select name into new.product_name
    from public.products
    where id = new.product_id;
  end if;
  return new;
end;
$$;

drop trigger if exists order_items_snapshot_product_name on public.order_items;
create trigger order_items_snapshot_product_name
before insert on public.order_items
for each row execute function public.order_items_snapshot_product_name();

-- 3. Let a deleted product leave the order line behind.
alter table public.order_items alter column product_id drop not null;

alter table public.order_items drop constraint if exists order_items_product_id_fkey;
alter table public.order_items
  add constraint order_items_product_id_fkey
  foreign key (product_id) references public.products(id) on delete set null;

commit;
