-- =============================================================
-- KahaPro: payment_methods — attach set_store_id() trigger
-- categories.store_id is populated by trg_categories_set_store_id
-- (BEFORE INSERT, calls set_store_id()) — not a column default.
-- Reusing that same existing function here so payment_methods
-- inserts work exactly like categories/products inserts: the app
-- never passes store_id, the trigger fills it in.
-- =============================================================

create trigger trg_payment_methods_set_store_id
  before insert on payment_methods
  for each row
  execute function set_store_id();
