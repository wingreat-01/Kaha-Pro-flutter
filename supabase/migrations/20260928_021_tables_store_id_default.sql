-- ============================================================================
-- Follow-up to 20260928_020_qr_ordering_core.sql
-- Suggested filename: supabase/migrations/20260928_021_tables_store_id_default.sql
--
-- Why this is needed: the Flutter "Add table" screen inserts a new row
-- the same way ProductProvider inserts a category — `.insert({'label':
-- label})` with no store_id — relying on store_id defaulting itself
-- server-side. The original tables migration didn't give store_id a
-- default, so that insert would fail its NOT NULL constraint as written.
--
-- ASSUMPTION FLAGGED: this assumes a `current_store_id()` function
-- already exists in your schema (referenced in earlier session notes
-- around verify_staff_login) that resolves the calling session's
-- store via store_members. If it's named differently, or doesn't
-- exist, tell me and I'll adjust this to match whatever the real
-- category-insert default actually calls.
-- ============================================================================

alter table public.tables
  alter column store_id set default current_store_id();
