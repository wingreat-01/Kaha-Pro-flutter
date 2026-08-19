-- 009_receipt_printing_toggle.sql
-- Receipt printing feature toggle. Stage 1 of the printer feature —
-- controls whether a receipt preview appears after checkout. Off by
-- default, same reasoning as senior_pwd_discount_enabled: existing
-- stores shouldn't see new post-checkout UI until the owner opts in.
-- Stage 2 (actual Bluetooth thermal printing) will reuse this same
-- column — no new toggle needed when that ships.

alter table stores
  add column if not exists receipt_printing_enabled boolean not null default false;
