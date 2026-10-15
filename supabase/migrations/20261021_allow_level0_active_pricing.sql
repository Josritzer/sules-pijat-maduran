-- Allow Level 0 (base price) as a selectable active pricing level.
-- Keep the existing pricing formula; Level 0 evaluates to the base price.
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
