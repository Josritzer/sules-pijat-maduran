-- Sules V1: product-card projection from the existing six private affiliate slots.
-- Reuse nama_produk, gambar_url, and harga_display; no new table or columns.
BEGIN;

DO $precheck$
DECLARE
  v_slot_count bigint;
BEGIN
  SELECT count(*) INTO v_slot_count
  FROM public.shopee_affiliate_slots;
  IF v_slot_count <> 6 THEN
    RAISE EXCEPTION 'Jumlah slot affiliate harus tetap tepat 6';
  END IF;
END;
$precheck$;

-- Admin-only update of an existing fixed slot. No INSERT/DELETE and no other business data.
CREATE OR REPLACE FUNCTION public.admin_save_shopee_product_slot(
  p_slot smallint,
  p_product_name text,
  p_product_image text,
  p_product_price numeric,
  p_affiliate_url text,
  p_aktif boolean
)
RETURNS TABLE(
  slot smallint,
  product_name text,
  product_image text,
  product_price numeric,
  affiliate_url text,
  aktif boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_product_name text := btrim(coalesce(p_product_name, ''));
  v_product_image text := btrim(coalesce(p_product_image, ''));
  v_affiliate_url text := btrim(coalesce(p_affiliate_url, ''));
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengubah slot affiliate';
  END IF;
  IF p_slot IS NULL OR p_slot < 1 OR p_slot > 6 THEN
    RAISE EXCEPTION 'Nomor slot harus 1 sampai 6';
  END IF;
  IF p_aktif IS NULL THEN
    RAISE EXCEPTION 'Status aktif harus ditentukan';
  END IF;
  IF length(v_product_name) > 200 THEN
    RAISE EXCEPTION 'Nama produk maksimal 200 karakter';
  END IF;
  IF v_product_image <> '' AND v_product_image !~* '^https://([a-z0-9-]+\.)+[a-z]{2,}([/?#][^[:space:]]*)?$' THEN
    RAISE EXCEPTION 'Foto produk harus berupa URL HTTPS yang valid';
  END IF;
  IF p_product_price IS NOT NULL AND (p_product_price < 0 OR p_product_price <> trunc(p_product_price)) THEN
    RAISE EXCEPTION 'Harga harus berupa bilangan Rupiah bulat dan tidak negatif';
  END IF;
  IF v_affiliate_url <> '' AND NOT (
       v_affiliate_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
    OR v_affiliate_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
  ) THEN
    RAISE EXCEPTION 'Affiliate URL harus HTTPS pada domain resmi Shopee';
  END IF;
  IF p_aktif AND v_affiliate_url = '' THEN
    RAISE EXCEPTION 'Slot aktif memerlukan Affiliate URL Shopee yang valid';
  END IF;

  UPDATE public.shopee_affiliate_slots AS s
     SET nama_produk = v_product_name,
         gambar_url = v_product_image,
         harga_display = CASE WHEN p_product_price IS NULL THEN '' ELSE p_product_price::text END,
         affiliate_url = v_affiliate_url,
         aktif = p_aktif
   WHERE s.slot = p_slot;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Slot tidak ditemukan';
  END IF;

  RETURN QUERY
  SELECT s.slot,
         s.nama_produk,
         NULLIF(btrim(s.gambar_url), ''),
         CASE
           WHEN btrim(s.harga_display) = '' THEN NULL::numeric
           WHEN btrim(s.harga_display) ~ '^[0-9]+$' THEN btrim(s.harga_display)::numeric
           WHEN btrim(s.harga_display) ~* '^Rp[[:space:]]*[0-9]{1,3}([.][0-9]{3})*$'
             THEN replace(regexp_replace(btrim(s.harga_display), '^Rp[[:space:]]*', '', 'i'), '.', '')::numeric
           ELSE NULL::numeric
         END,
         s.affiliate_url,
         s.aktif
  FROM public.shopee_affiliate_slots AS s
  WHERE s.slot = p_slot;
END;
$function$;

-- Public read-only projection: only active slots with a valid Affiliate URL and valid name.
-- A blank image/price remains NULL so the frontend can show its neutral fallback/hide price.
CREATE OR REPLACE FUNCTION public.get_active_shopee_product_cards()
RETURNS TABLE(
  slot smallint,
  affiliate_url text,
  product_name text,
  product_image text,
  product_price numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT s.slot,
         s.affiliate_url,
         btrim(s.nama_produk),
         NULLIF(btrim(s.gambar_url), ''),
         CASE
           WHEN btrim(s.harga_display) = '' THEN NULL::numeric
           WHEN btrim(s.harga_display) ~ '^[0-9]+$' THEN btrim(s.harga_display)::numeric
           WHEN btrim(s.harga_display) ~* '^Rp[[:space:]]*[0-9]{1,3}([.][0-9]{3})*$'
             THEN replace(regexp_replace(btrim(s.harga_display), '^Rp[[:space:]]*', '', 'i'), '.', '')::numeric
           ELSE NULL::numeric
         END
  FROM public.shopee_affiliate_slots AS s
  WHERE s.aktif
    AND btrim(s.nama_produk) <> ''
    AND length(btrim(s.nama_produk)) <= 200
    AND (
         s.affiliate_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
      OR s.affiliate_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
    )
    AND (
      btrim(s.gambar_url) = ''
      OR btrim(s.gambar_url) ~* '^https://([a-z0-9-]+\.)+[a-z]{2,}([/?#][^[:space:]]*)?$'
    )
    AND (
      btrim(s.harga_display) = ''
      OR btrim(s.harga_display) ~ '^[0-9]+$'
      OR btrim(s.harga_display) ~* '^Rp[[:space:]]*[0-9]{1,3}([.][0-9]{3})*$'
    )
  ORDER BY s.slot;
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.admin_save_shopee_product_slot(smallint, text, text, numeric, text, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_save_shopee_product_slot(smallint, text, text, numeric, text, boolean)
  TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.get_active_shopee_product_cards()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_active_shopee_product_cards()
  TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
