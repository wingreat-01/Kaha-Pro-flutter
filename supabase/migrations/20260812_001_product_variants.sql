-- Migration: product_variants (sizes) for KahaPro
-- Run this in the Supabase SQL editor for project uykrnoxlzlvjtazicjim.
-- Safe to run once; re-running will error on the CREATE TABLE (expected).

-- ---------------------------------------------------------------------
-- 1. product_variants table
-- ---------------------------------------------------------------------
create table product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  store_id uuid not null references stores(id) on delete cascade,
  name text not null,
  price numeric not null check (price >= 0),
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index product_variants_product_id_idx on product_variants(product_id);
create index product_variants_store_id_idx on product_variants(store_id);

-- ---------------------------------------------------------------------
-- 2. RLS — matches the products table exactly: single ALL policy
--    driven by the current_store_id() helper function.
-- ---------------------------------------------------------------------
alter table product_variants enable row level security;

create policy "store scoped access"
  on product_variants for all
  using (store_id = current_store_id())
  with check (store_id = current_store_id());

-- ---------------------------------------------------------------------
-- 3. transaction_line_items — snapshot the chosen variant at sale time
--    (name + price captured as text/numeric, NOT just a foreign key,
--    so a later rename/delete of the variant doesn't rewrite history).
-- ---------------------------------------------------------------------
alter table transaction_line_items
  add column variant_id uuid references product_variants(id) on delete set null,
  add column variant_name text;
