-- Allow the business to activate the base price as Level 0.
-- Pricing calculation already uses base * (1 + level * 0.10); this changes only accepted level ranges.
ALTER TABLE public.package_pricing_config
  DROP CONSTRAINT IF EXISTS package_pricing_config_active_level_check;
ALTER TABLE public.package_pricing_config
  ADD CONSTRAINT package_pricing_config_active_level_check
  CHECK (active_level >= 0 AND active_level <= 5);

ALTER TABLE public.bookings
  DROP CONSTRAINT IF EXISTS bookings_price_level_check;
ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_price_level_check
  CHECK (price_level IS NULL OR (price_level >= 0 AND price_level <= 5));
