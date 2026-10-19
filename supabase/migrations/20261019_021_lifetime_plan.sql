-- Lifetime plan support: allow stores.plan = 'lifetime' and record one-time purchases.
-- NOTE: product_limit(), staff_limit(), ai_credit_allotment() and grant_plan_credits()
-- still need a 'lifetime' branch (treat it like 'pro'). Not included here because they
-- must be edited against their current definitions.

-- 1) If stores.plan is an enum type, add the new value.
DO $$
DECLARE t text;
BEGIN
  SELECT udt_name INTO t FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'stores' AND column_name = 'plan';
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = t AND typtype = 'e') THEN
    EXECUTE format('ALTER TYPE public.%I ADD VALUE IF NOT EXISTS %L', t, 'lifetime');
  END IF;
END $$;

-- 2) If stores.plan has a CHECK constraint, replace it with one that includes 'lifetime'.
DO $$
DECLARE c record; dropped boolean := false;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.stores'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ~ '\mplan\M'
  LOOP
    EXECUTE format('ALTER TABLE public.stores DROP CONSTRAINT %I', c.conname);
    dropped := true;
  END LOOP;
  IF dropped THEN
    ALTER TABLE public.stores
      ADD CONSTRAINT stores_plan_check
      CHECK (plan IN ('free', 'starter', 'basic', 'pro', 'lifetime', 'expired'));
  END IF;
END $$;

-- 3) One row per Lifetime purchase token; stops one purchase unlocking two stores.
CREATE TABLE IF NOT EXISTS public.lifetime_purchases (
  purchase_token text PRIMARY KEY,
  store_id       uuid NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  auth_user_id   uuid NOT NULL,
  product_id     text NOT NULL,
  is_test        boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS lifetime_purchases_store_idx ON public.lifetime_purchases (store_id);

-- Service role only (the Edge Function); no policies for regular users.
ALTER TABLE public.lifetime_purchases ENABLE ROW LEVEL SECURITY;
