-- 008_receipt_details.sql
-- Receipt Details fields — the business info typically printed on a
-- Philippine sales receipt/invoice, separate from the address/footer
-- added in 007. All nullable free text — an owner may not have a TIN
-- or permit number entered yet, and the receipt should just omit a
-- blank line rather than require these up front.

alter table stores
  add column if not exists tin text,               -- BIR Tax Identification Number
  add column if not exists contact_number text,     -- phone shown on the receipt
  add column if not exists permit_number text;      -- Business Permit / OR / ATP number

-- Sanity check after running:
-- select column_name, data_type
-- from information_schema.columns
-- where table_name = 'stores' and column_name in ('tin', 'contact_number', 'permit_number');
