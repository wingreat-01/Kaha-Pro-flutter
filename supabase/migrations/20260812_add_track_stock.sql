-- Adds a per-product flag: true = this product's stock auto-deducts
-- at checkout (drinks/cups); false = stock_qty is manual-only (food
-- items you restock/count by hand, unaffected by sales).
ALTER TABLE products
  ADD COLUMN track_stock boolean NOT NULL DEFAULT false;

-- Optional one-time backfill: if you want everything currently in
-- your "Drinks" category to start out flagged on, run this too
-- (safe to skip / edit the category name first if yours differs):
UPDATE products
SET track_stock = true
WHERE category_id = (SELECT id FROM categories WHERE name = 'Drinks' LIMIT 1);
