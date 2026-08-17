-- Audit log for every ingredient stock change -- both manual
-- corrections (the +/- stock dialog in the Ingredients screen) and
-- sale-driven deductions (source = 'sale'), so "why did this drop by
-- 20?" always has an answer.
--
-- store_id defaults to current_store_id() and is RLS-scoped the same
-- way as ingredients/products/staff_users -- matches that established
-- pattern rather than joining through ingredients.store_id.
--
-- staff_id is a real FK (nullable -- ON DELETE SET NULL so deleting a
-- staff account doesn't destroy history), but staff_name is also
-- stored as a plain snapshot column, mirroring
-- transactions.cashier_name -- a renamed or deleted staff account
-- shouldn't make old log entries show a blank "who".
create table if not exists ingredient_stock_movements (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null default current_store_id(),
  ingredient_id uuid not null references ingredients(id) on delete cascade,
  delta numeric not null, -- positive = added, negative = deducted
  reason text not null,
  note text,
  staff_id uuid references staff_users(id) on delete set null,
  staff_name text,
  source text not null default 'manual' check (source in ('manual', 'sale')),
  created_at timestamptz not null default now()
);

create index if not exists idx_ingredient_stock_movements_ingredient
  on ingredient_stock_movements (ingredient_id, created_at desc);

alter table ingredient_stock_movements enable row level security;

create policy "store scoped access" on ingredient_stock_movements
  for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());
