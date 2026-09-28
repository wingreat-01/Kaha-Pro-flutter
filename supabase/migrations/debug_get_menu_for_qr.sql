-- Run this in the Supabase SQL editor to see the real error directly
-- (bypasses the browser/anon-key layer entirely).

-- 1. Confirm the function exists and see its current definition:
select proname, prosrc
from pg_proc
where proname = 'get_menu_for_qr';

-- 2. Get a real qr_token to test with:
select id, label, qr_token, is_active, store_id
from public.tables
order by created_at desc
limit 5;

-- 3. Call the function directly with one of those tokens
-- (replace the uuid below with a real qr_token from step 2):
select get_menu_for_qr('00000000-0000-0000-0000-000000000000'::uuid);
