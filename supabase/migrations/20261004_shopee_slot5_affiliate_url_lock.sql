-- Preserve the user-specified affiliate URL for fixed slot 5.
-- Only seed this exact user-provided URL when a fresh six-slot install is blank.
-- Existing non-empty slot-5 values are never overwritten.
BEGIN;

DO $precheck$
DECLARE
  v_slot_count bigint;
  v_slot5_url text;
BEGIN
  SELECT count(*) INTO v_slot_count FROM public.shopee_affiliate_slots;
  IF v_slot_count <> 6 THEN
    RAISE EXCEPTION 'Jumlah slot affiliate harus tetap tepat 6';
  END IF;

  SELECT affiliate_url INTO v_slot5_url
  FROM public.shopee_affiliate_slots
  WHERE slot = 5
  LIMIT 1;

  IF v_slot5_url IS NULL THEN
    RAISE EXCEPTION 'Slot 5 tidak ditemukan atau URL-nya NULL';
  END IF;
  IF btrim(v_slot5_url) <> ''
     AND btrim(v_slot5_url) <> 'https://s.shopee.co.id/6fhmVPAiYt' THEN
    RAISE EXCEPTION 'Slot 5 berisi URL lain; tidak ada data yang diubah';
  END IF;
END;
$precheck$;

-- On a clean install only, initialize the URL supplied in the user specification.
-- Preserve the slot's existing active status and all product metadata.
UPDATE public.shopee_affiliate_slots
SET affiliate_url = 'https://s.shopee.co.id/6fhmVPAiYt'
WHERE slot = 5
  AND btrim(affiliate_url) = '';

DO $constraint$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.shopee_affiliate_slots'::regclass
      AND conname = 'shopee_affiliate_slots_slot5_url_fixed'
    LIMIT 1
  ) THEN
    ALTER TABLE public.shopee_affiliate_slots
      ADD CONSTRAINT shopee_affiliate_slots_slot5_url_fixed
      CHECK (slot <> 5 OR affiliate_url = 'https://s.shopee.co.id/6fhmVPAiYt');
  END IF;
END;
$constraint$;

NOTIFY pgrst, 'reload schema';
COMMIT;
