-- Sules V1: expose only active validated Shopee links publicly; keep table writes Admin-only.
-- The six existing rows and all product metadata are preserved.
BEGIN;

DO $precheck$
DECLARE
  v_slot_count bigint;
BEGIN
  SELECT count(*) INTO v_slot_count FROM public.shopee_affiliate_slots;
  IF v_slot_count <> 6 THEN
    RAISE EXCEPTION 'Jumlah slot bukan 6';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.shopee_affiliate_slots
    WHERE aktif AND btrim(affiliate_url) = ''
  ) THEN
    RAISE EXCEPTION 'Ada slot aktif tanpa URL';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.shopee_affiliate_slots'::regclass
      AND conname = 'shopee_affiliate_slots_active_has_product'
  ) THEN
    RAISE EXCEPTION 'Constraint active_has_product tidak ditemukan';
  END IF;
END;
$precheck$;

-- Active slots require a URL, not product metadata. All other constraints remain unchanged.
ALTER TABLE public.shopee_affiliate_slots
  DROP CONSTRAINT shopee_affiliate_slots_active_has_product;
ALTER TABLE public.shopee_affiliate_slots
  ADD CONSTRAINT shopee_affiliate_slots_active_has_url
  CHECK (NOT aktif OR affiliate_url <> '');

-- Narrow Admin-only read for the link-only editor; legacy full-detail RPC stays for compatibility.
CREATE OR REPLACE FUNCTION public.admin_get_shopee_affiliate_links()
RETURNS TABLE(slot smallint, affiliate_url text, aktif boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengakses slot affiliate';
  END IF;

  RETURN QUERY
  SELECT s.slot, s.affiliate_url, s.aktif
  FROM public.shopee_affiliate_slots AS s
  ORDER BY s.slot;
END;
$function$;

-- Link-only Admin write: UPDATE exactly two columns; never replace legacy metadata or upsert.
CREATE OR REPLACE FUNCTION public.admin_save_shopee_affiliate_link(
  p_slot smallint,
  p_affiliate_url text,
  p_aktif boolean
)
RETURNS TABLE(slot smallint, affiliate_url text, aktif boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_url text := btrim(coalesce(p_affiliate_url, ''));
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengubah slot affiliate';
  END IF;
  IF p_slot IS NULL OR p_slot < 1 OR p_slot > 6 THEN
    RAISE EXCEPTION 'Nomor slot harus 1 sampai 6';
  END IF;
  IF p_aktif IS NULL THEN
    RAISE EXCEPTION 'Status harus ditentukan';
  END IF;
  IF v_url <> '' AND NOT (
       v_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
    OR v_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
  ) THEN
    RAISE EXCEPTION 'Affiliate URL harus HTTPS pada domain resmi Shopee';
  END IF;
  IF p_aktif AND v_url = '' THEN
    RAISE EXCEPTION 'Slot aktif memerlukan Affiliate URL Shopee yang valid';
  END IF;

  UPDATE public.shopee_affiliate_slots AS s
     SET affiliate_url = v_url,
         aktif = p_aktif
   WHERE s.slot = p_slot;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Slot tidak ditemukan';
  END IF;

  RETURN QUERY
  SELECT s.slot, s.affiliate_url, s.aktif
  FROM public.shopee_affiliate_slots AS s
  WHERE s.slot = p_slot;
END;
$function$;

-- Public read-only projection: only active, server-validated links; no product or customer data.
CREATE OR REPLACE FUNCTION public.get_active_shopee_affiliate_links()
RETURNS TABLE(slot smallint, affiliate_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT s.slot, s.affiliate_url
  FROM public.shopee_affiliate_slots AS s
  WHERE s.aktif
    AND (
         s.affiliate_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
      OR s.affiliate_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
    )
  ORDER BY s.slot;
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.admin_get_shopee_affiliate_links() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_shopee_affiliate_links() TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.admin_save_shopee_affiliate_link(smallint, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_save_shopee_affiliate_link(smallint, text, boolean) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.get_active_shopee_affiliate_links() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_active_shopee_affiliate_links() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
