-- Correct the Admin save RPC: RETURNS TABLE exposes `slot` as a PL/pgSQL output variable,
-- so target the primary-key constraint by name in ON CONFLICT instead of using (slot).
CREATE OR REPLACE FUNCTION public.admin_save_shopee_affiliate_slot(
  p_slot smallint,
  p_nama_produk text,
  p_gambar_url text,
  p_harga_display text,
  p_deskripsi_singkat text,
  p_affiliate_url text,
  p_aktif boolean
)
RETURNS TABLE (
  slot smallint,
  nama_produk text,
  gambar_url text,
  harga_display text,
  deskripsi_singkat text,
  affiliate_url text,
  aktif boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_nama_produk text := coalesce(p_nama_produk, '');
  v_gambar_url text := btrim(coalesce(p_gambar_url, ''));
  v_harga_display text := coalesce(p_harga_display, '');
  v_deskripsi_singkat text := coalesce(p_deskripsi_singkat, '');
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

  IF v_gambar_url <> '' AND v_gambar_url !~* '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$' THEN
    RAISE EXCEPTION 'Gambar harus menggunakan URL HTTPS yang valid';
  END IF;

  IF v_affiliate_url <> '' AND NOT (
    v_affiliate_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
    OR v_affiliate_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
  ) THEN
    RAISE EXCEPTION 'Affiliate URL harus HTTPS pada domain resmi Shopee';
  END IF;

  IF p_aktif AND (btrim(v_nama_produk) = '' OR v_affiliate_url = '') THEN
    RAISE EXCEPTION 'Produk aktif memerlukan nama dan Affiliate URL Shopee yang valid';
  END IF;

  INSERT INTO public.shopee_affiliate_slots AS current_slot (
    slot, nama_produk, gambar_url, harga_display, deskripsi_singkat, affiliate_url, aktif
  ) VALUES (
    p_slot, v_nama_produk, v_gambar_url, v_harga_display,
    v_deskripsi_singkat, v_affiliate_url, p_aktif
  )
  ON CONFLICT ON CONSTRAINT shopee_affiliate_slots_pkey DO UPDATE SET
    nama_produk = EXCLUDED.nama_produk,
    gambar_url = EXCLUDED.gambar_url,
    harga_display = EXCLUDED.harga_display,
    deskripsi_singkat = EXCLUDED.deskripsi_singkat,
    affiliate_url = EXCLUDED.affiliate_url,
    aktif = EXCLUDED.aktif;

  RETURN QUERY
  SELECT s.slot, s.nama_produk, s.gambar_url, s.harga_display,
         s.deskripsi_singkat, s.affiliate_url, s.aktif
  FROM public.shopee_affiliate_slots AS s
  WHERE s.slot = p_slot;
END;
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.admin_save_shopee_affiliate_slot(smallint, text, text, text, text, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_save_shopee_affiliate_slot(smallint, text, text, text, text, text, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
