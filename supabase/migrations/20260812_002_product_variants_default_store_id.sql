-- Follow-up to 001_product_variants.sql — run this too.
-- Adds the same store_id default your products/categories tables
-- already use, so app code never has to pass store_id explicitly.
alter table product_variants
  alter column store_id set default current_store_id();
