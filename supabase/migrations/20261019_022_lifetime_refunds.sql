-- Lets rtdn-webhook mark a Lifetime purchase as refunded.
ALTER TABLE public.lifetime_purchases
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz;
