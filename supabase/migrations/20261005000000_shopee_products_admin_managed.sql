-- Sules V1: produk Shopee Affiliate dikelola penuh oleh Admin.
-- Tidak ada batas jumlah, tidak ada slot tetap, tidak ada URL bawaan atau kunci.
-- Data lama dari shopee_affiliate_slots disalin sebagai produk biasa; booking dan data lain tidak disentuh.
BEGIN;

CREATE TABLE IF NOT EXISTS public.shopee_affiliate_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sort_order bigint GENERATED ALWAYS AS IDENTITY,
  affiliate_url text NOT NULL,
  product_name text NOT NULL DEFAULT '',
  product_image text NOT NULL DEFAULT '',
  product_price numeric,
  product_original_price numeric,
  aktif boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT shopee_products_official_url CHECK (
    affiliate_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
    OR affiliate_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
  ),
  CONSTRAINT shopee_products_name_length CHECK (length(product_name) <= 200),
  CONSTRAINT shopee_products_image_https CHECK (
    product_image = ''
    OR product_image ~* '^https://([a-z0-9-]+\.)+[a-z]{2,}([/?#][^[:space:]]*)?$'
  ),
  CONSTRAINT shopee_products_price_valid CHECK (
    product_price IS NULL OR (product_price >= 0 AND product_price = trunc(product_price))
  ),
  CONSTRAINT shopee_products_original_price_valid CHECK (
    product_original_price IS NULL
    OR (product_original_price >= 0 AND product_original_price = trunc(product_original_price))
  )
);

ALTER TABLE public.shopee_affiliate_products ENABLE ROW LEVEL SECURITY;
-- Tidak ada akses tabel langsung; semua lewat RPC SECURITY DEFINER di bawah.
REVOKE ALL PRIVILEGES ON TABLE public.shopee_affiliate_products FROM PUBLIC, anon, authenticated, service_role;

-- Salin data lama (hanya slot yang berisi) menjadi produk biasa. Slot kosong tidak disalin.
DO $copy$
DECLARE
  v_expected bigint := 0;
  v_copied bigint := 0;
BEGIN
  IF to_regclass('public.shopee_affiliate_slots') IS NULL THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.shopee_affiliate_products LIMIT 1) THEN
    RETURN; -- sudah pernah disalin
  END IF;

  SELECT count(*) INTO v_expected
  FROM public.shopee_affiliate_slots AS s
  WHERE btrim(s.affiliate_url) <> '';

  INSERT INTO public.shopee_affiliate_products
    (affiliate_url, product_name, product_image, product_price, product_original_price, aktif)
  SELECT btrim(s.affiliate_url),
         left(btrim(s.nama_produk), 200),
         CASE
           WHEN btrim(s.gambar_url) ~* '^https://([a-z0-9-]+\.)+[a-z]{2,}([/?#][^[:space:]]*)?$'
             THEN btrim(s.gambar_url)
           ELSE ''
         END,
         CASE
           WHEN btrim(s.harga_display) ~ '^[0-9]+$' THEN btrim(s.harga_display)::numeric
           WHEN btrim(s.harga_display) ~* '^Rp[[:space:]]*[0-9]{1,3}([.][0-9]{3})*$'
             THEN replace(regexp_replace(btrim(s.harga_display), '^Rp[[:space:]]*', '', 'i'), '.', '')::numeric
           ELSE NULL::numeric
         END,
         CASE
           WHEN btrim(coalesce(s.harga_display_asli, '')) ~ '^[0-9]+$' THEN btrim(s.harga_display_asli)::numeric
           ELSE NULL::numeric
         END,
         s.aktif
  FROM public.shopee_affiliate_slots AS s
  WHERE btrim(s.affiliate_url) <> ''
  ORDER BY s.slot;

  SELECT count(*) INTO v_copied FROM public.shopee_affiliate_products;
  IF v_copied <> v_expected THEN
    RAISE EXCEPTION 'Penyalinan produk lama tidak lengkap (% dari %); migrasi dibatalkan', v_copied, v_expected;
  END IF;
END;
$copy$;

-- Admin: daftar semua produk.
CREATE OR REPLACE FUNCTION public.admin_list_shopee_products()
RETURNS SETOF public.shopee_affiliate_products
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengelola produk affiliate';
  END IF;
  RETURN QUERY
  SELECT * FROM public.shopee_affiliate_products AS p ORDER BY p.sort_order;
END;
$function$;

-- Admin: tambah (p_id NULL) atau ubah (p_id terisi). Hanya link Shopee yang wajib.
CREATE OR REPLACE FUNCTION public.admin_save_shopee_product(
  p_id uuid,
  p_affiliate_url text,
  p_product_name text,
  p_product_image text,
  p_product_price numeric,
  p_product_original_price numeric,
  p_aktif boolean
)
RETURNS SETOF public.shopee_affiliate_products
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_url text := btrim(coalesce(p_affiliate_url, ''));
  v_name text := btrim(coalesce(p_product_name, ''));
  v_image text := btrim(coalesce(p_product_image, ''));
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengelola produk affiliate';
  END IF;
  IF p_aktif IS NULL THEN
    RAISE EXCEPTION 'Status aktif harus ditentukan';
  END IF;
  IF v_url = '' THEN
    RAISE EXCEPTION 'Link Shopee wajib diisi';
  END IF;
  IF NOT (
       v_url ~* '^https://([a-z0-9-]+\.)*shopee\.co\.id([/?#][^[:space:]]*)?$'
    OR v_url ~* '^https://shopee\.ee([/?#][^[:space:]]*)?$'
  ) THEN
    RAISE EXCEPTION 'Link harus HTTPS pada domain resmi Shopee';
  END IF;
  IF length(v_name) > 200 THEN
    RAISE EXCEPTION 'Nama produk maksimal 200 karakter';
  END IF;
  IF v_image <> '' AND v_image !~* '^https://([a-z0-9-]+\.)+[a-z]{2,}([/?#][^[:space:]]*)?$' THEN
    RAISE EXCEPTION 'Foto produk harus berupa URL HTTPS yang valid';
  END IF;
  IF p_product_price IS NOT NULL AND (p_product_price < 0 OR p_product_price <> trunc(p_product_price)) THEN
    RAISE EXCEPTION 'Harga harus berupa bilangan Rupiah bulat dan tidak negatif';
  END IF;
  IF p_product_original_price IS NOT NULL AND (p_product_original_price < 0 OR p_product_original_price <> trunc(p_product_original_price)) THEN
    RAISE EXCEPTION 'Harga awal harus berupa bilangan Rupiah bulat dan tidak negatif';
  END IF;

  IF p_id IS NULL THEN
    RETURN QUERY
    INSERT INTO public.shopee_affiliate_products AS t
      (affiliate_url, product_name, product_image, product_price, product_original_price, aktif)
    VALUES (v_url, v_name, v_image, p_product_price, p_product_original_price, p_aktif)
    RETURNING t.*;
  ELSE
    RETURN QUERY
    UPDATE public.shopee_affiliate_products AS t
       SET affiliate_url = v_url,
           product_name = v_name,
           product_image = v_image,
           product_price = p_product_price,
           product_original_price = p_product_original_price,
           aktif = p_aktif,
           updated_at = now()
     WHERE t.id = p_id
    RETURNING t.*;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk tidak ditemukan';
    END IF;
  END IF;
END;
$function$;

-- Admin: hapus permanen satu produk.
CREATE OR REPLACE FUNCTION public.admin_delete_shopee_product(p_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengelola produk affiliate';
  END IF;
  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Produk tidak ditemukan';
  END IF;
  DELETE FROM public.shopee_affiliate_products AS t WHERE t.id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Produk tidak ditemukan';
  END IF;
  RETURN true;
END;
$function$;

-- Publik: hanya produk aktif, hanya kolom yang perlu untuk kartu.
CREATE OR REPLACE FUNCTION public.get_active_shopee_products()
RETURNS TABLE(
  id uuid,
  affiliate_url text,
  product_name text,
  product_image text,
  product_price numeric,
  product_original_price numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT p.id, p.affiliate_url, p.product_name,
         NULLIF(p.product_image, ''), p.product_price, p.product_original_price
  FROM public.shopee_affiliate_products AS p
  WHERE p.aktif
  ORDER BY p.sort_order;
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.admin_list_shopee_products() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_shopee_products() TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.admin_save_shopee_product(uuid, text, text, text, numeric, numeric, boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_save_shopee_product(uuid, text, text, text, numeric, numeric, boolean) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.admin_delete_shopee_product(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_shopee_product(uuid) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.get_active_shopee_products() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_active_shopee_products() TO anon, authenticated;

-- Hapus RPC slot lama dan kunci slot 5. Tabel lama disimpan sebagai cadangan (tidak dihapus).
DROP FUNCTION IF EXISTS public.admin_get_shopee_affiliate_slots();
DROP FUNCTION IF EXISTS public.admin_save_shopee_affiliate_slot(smallint, text, text, text, text, text, boolean);
DROP FUNCTION IF EXISTS public.admin_get_shopee_affiliate_links();
DROP FUNCTION IF EXISTS public.admin_save_shopee_affiliate_link(smallint, text, boolean);
DROP FUNCTION IF EXISTS public.get_active_shopee_affiliate_links();
DROP FUNCTION IF EXISTS public.admin_save_shopee_product_slot(smallint, text, text, numeric, text, boolean);
DROP FUNCTION IF EXISTS public.get_active_shopee_product_cards();
DROP FUNCTION IF EXISTS public.admin_get_shopee_product_slots_v2();
DROP FUNCTION IF EXISTS public.admin_save_shopee_product_slot_v2(smallint, text, text, numeric, numeric, text, boolean);
DROP FUNCTION IF EXISTS public.get_active_shopee_product_cards_v2();

DO $legacy$
BEGIN
  IF to_regclass('public.shopee_affiliate_slots') IS NOT NULL THEN
    ALTER TABLE public.shopee_affiliate_slots
      DROP CONSTRAINT IF EXISTS shopee_affiliate_slots_slot5_url_fixed;
    ALTER TABLE public.shopee_affiliate_slots RENAME TO shopee_affiliate_slots_legacy_backup;
  END IF;
END;
$legacy$;

NOTIFY pgrst, 'reload schema';
COMMIT;
