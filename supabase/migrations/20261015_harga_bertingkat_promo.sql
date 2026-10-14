-- SL Relax V1: tiered package pricing and promotions.
-- Feature branch only. Do not apply to production until reviewed and approved.
-- Preserve historical booking totals while changing grand_total from generated to stored.

CREATE TABLE IF NOT EXISTS public.package_pricing_config (
  package_key text PRIMARY KEY CHECK (package_key IN (
    'sules-90m-1', 'sules-120m-1', 'home-90m-1', 'home-120m-1', 'home-90m-2'
  )),
  active_level smallint NOT NULL DEFAULT 1 CHECK (active_level BETWEEN 1 AND 5),
  promo_type text NOT NULL DEFAULT 'none' CHECK (promo_type IN ('none', 'percent', 'nominal')),
  promo_value numeric(12,2) NOT NULL DEFAULT 0 CHECK (promo_value >= 0),
  promo_start_date date,
  promo_end_date date,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (promo_type = 'none' AND promo_value = 0)
    OR
    (promo_type = 'percent' AND promo_value IN (5, 10, 15, 20, 25, 30)
      AND promo_start_date IS NOT NULL AND promo_end_date IS NOT NULL AND promo_end_date >= promo_start_date)
    OR
    (promo_type = 'nominal' AND promo_value > 0
      AND promo_start_date IS NOT NULL AND promo_end_date IS NOT NULL AND promo_end_date >= promo_start_date)
  )
);

INSERT INTO public.package_pricing_config (package_key)
VALUES ('sules-90m-1'), ('sules-120m-1'), ('home-90m-1'), ('home-120m-1'), ('home-90m-2')
ON CONFLICT (package_key) DO NOTHING;

ALTER TABLE public.package_pricing_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS package_pricing_public_read ON public.package_pricing_config;
CREATE POLICY package_pricing_public_read
  ON public.package_pricing_config FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS package_pricing_admin_update ON public.package_pricing_config;
CREATE POLICY package_pricing_admin_update
  ON public.package_pricing_config FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

REVOKE ALL ON public.package_pricing_config FROM PUBLIC;
GRANT SELECT ON public.package_pricing_config TO anon, authenticated;
GRANT UPDATE ON public.package_pricing_config TO authenticated;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS package_key text,
  ADD COLUMN IF NOT EXISTS base_price numeric(12,2),
  ADD COLUMN IF NOT EXISTS price_level smallint,
  ADD COLUMN IF NOT EXISTS package_price numeric(12,2),
  ADD COLUMN IF NOT EXISTS subtotal numeric(12,2),
  ADD COLUMN IF NOT EXISTS promo_type text,
  ADD COLUMN IF NOT EXISTS promo_value numeric(12,2),
  ADD COLUMN IF NOT EXISTS promo_discount numeric(12,2),
  ADD COLUMN IF NOT EXISTS final_total numeric(12,2);

-- DROP EXPRESSION preserves each existing computed value as a normal stored value.
ALTER TABLE public.bookings ALTER COLUMN grand_total DROP EXPRESSION;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_package_key_check
    CHECK (package_key IS NULL OR package_key IN ('sules-90m-1','sules-120m-1','home-90m-1','home-120m-1','home-90m-2')),
  ADD CONSTRAINT bookings_price_level_check
    CHECK (price_level IS NULL OR price_level BETWEEN 1 AND 5),
  ADD CONSTRAINT bookings_promo_type_check
    CHECK (promo_type IS NULL OR promo_type IN ('none','percent','nominal')),
  ADD CONSTRAINT bookings_nonnegative_price_snapshot_check
    CHECK (
      (base_price IS NULL OR base_price >= 0) AND
      (package_price IS NULL OR package_price >= 0) AND
      (subtotal IS NULL OR subtotal >= 0) AND
      (promo_discount IS NULL OR promo_discount >= 0) AND
      (final_total IS NULL OR final_total >= 0) AND
      (promo_value IS NULL OR promo_value >= 0)
    );

CREATE OR REPLACE FUNCTION public.create_booking_server(
  p_customer_id uuid,
  p_nama text,
  p_wa text,
  p_service_id text,
  p_jumlah_orang smallint,
  p_tanggal date,
  p_jam_mulai time without time zone,
  p_tipe_lokasi public.tipe_lokasi,
  p_alamat text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_jarak_meter numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_service public.services%rowtype;
  v_gratis_meter numeric;
  v_tarif numeric;
  v_base_price numeric;
  v_level smallint;
  v_package_key text;
  v_package_price numeric;
  v_travel_fee numeric;
  v_subtotal numeric;
  v_promo_type text := 'none';
  v_promo_value numeric := 0;
  v_promo_discount numeric := 0;
  v_final_total numeric;
  v_durasi_menit integer;
  v_booking public.bookings%rowtype;
  v_sesi_tutup text;
  v_config public.package_pricing_config%rowtype;
  v_today date := timezone('Asia/Jakarta', now())::date;
BEGIN
  IF p_customer_id IS NULL THEN RAISE EXCEPTION 'Customer ID wajib'; END IF;
  IF p_nama IS NULL OR btrim(p_nama) = '' THEN RAISE EXCEPTION 'Nama pelanggan wajib diisi'; END IF;
  IF p_wa IS NULL OR btrim(p_wa) = '' THEN RAISE EXCEPTION 'Nomor WA wajib diisi'; END IF;
  IF p_jumlah_orang IS NULL OR p_jumlah_orang < 1 OR p_jumlah_orang > 2 THEN RAISE EXCEPTION 'Jumlah orang harus 1 atau 2'; END IF;
  IF p_tanggal IS NULL OR p_tanggal < v_today THEN RAISE EXCEPTION 'Tanggal booking tidak valid atau sudah lewat'; END IF;
  IF p_jam_mulai IS NULL THEN RAISE EXCEPTION 'Jam booking wajib diisi'; END IF;
  IF p_tipe_lokasi IS NULL THEN RAISE EXCEPTION 'Lokasi layanan wajib dipilih'; END IF;

  IF NOT (
    (p_service_id = '90m' AND p_tipe_lokasi = 'DI_TEMPAT' AND p_jumlah_orang = 1) OR
    (p_service_id = '120m' AND p_tipe_lokasi = 'DI_TEMPAT' AND p_jumlah_orang = 1) OR
    (p_service_id = '90m' AND p_tipe_lokasi = 'HOME_SERVICE' AND p_jumlah_orang = 1) OR
    (p_service_id = '120m' AND p_tipe_lokasi = 'HOME_SERVICE' AND p_jumlah_orang = 1) OR
    (p_service_id = '90m' AND p_tipe_lokasi = 'HOME_SERVICE' AND p_jumlah_orang = 2)
  ) THEN RAISE EXCEPTION 'Paket yang dipilih tidak valid'; END IF;

  SELECT * INTO v_service FROM public.services WHERE id = p_service_id AND aktif = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Layanan tidak ditemukan'; END IF;

  v_package_key := CASE
    WHEN p_tipe_lokasi = 'DI_TEMPAT' AND p_service_id = '90m' THEN 'sules-90m-1'
    WHEN p_tipe_lokasi = 'DI_TEMPAT' AND p_service_id = '120m' THEN 'sules-120m-1'
    WHEN p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN 'home-90m-2'
    WHEN p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' THEN 'home-90m-1'
    ELSE 'home-120m-1'
  END;

  v_base_price := CASE v_package_key
    WHEN 'sules-90m-1' THEN 60000
    WHEN 'sules-120m-1' THEN 80000
    WHEN 'home-90m-1' THEN 60000
    WHEN 'home-120m-1' THEN 80000
    WHEN 'home-90m-2' THEN 120000
  END;

  SELECT * INTO v_config FROM public.package_pricing_config WHERE package_key = v_package_key;
  v_level := coalesce(v_config.active_level, 1);
  -- Level 1 remains base; evenly spaced increments hit the approved level-5 targets.
  v_package_price := v_base_price + (v_level - 1) *
    CASE WHEN v_package_key = 'home-90m-2' THEN 25000 ELSE 12500 END;

  v_durasi_menit := CASE
    WHEN p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN 180
    ELSE v_service.durasi_menit
  END;

  IF NOT public._dalam_jam_operasional(p_jam_mulai, v_durasi_menit) THEN
    RAISE EXCEPTION 'Jam di luar jam operasional atau melewati jam tutup';
  END IF;

  -- Keep the existing Admin session-close rule for new bookings.
  v_sesi_tutup := public._pesan_sesi_tutup(p_tanggal, p_jam_mulai);
  IF v_sesi_tutup IS NOT NULL THEN RAISE EXCEPTION '%', v_sesi_tutup; END IF;

  IF p_tipe_lokasi = 'HOME_SERVICE' THEN
    IF p_lat IS NULL OR p_lng IS NULL OR p_lat::text = 'NaN' OR p_lng::text = 'NaN' OR
       p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
      RAISE EXCEPTION 'Home Service wajib menyertakan lokasi valid (lat/lng)';
    END IF;
    IF p_jarak_meter IS NULL OR p_jarak_meter < 0 OR p_jarak_meter::text IN ('NaN', 'Infinity', '-Infinity') THEN
      RAISE EXCEPTION 'Jarak tempuh Google Routes wajib untuk Home Service';
    END IF;
  END IF;

  SELECT value::numeric INTO v_gratis_meter FROM public.operational_settings WHERE key = 'travel_gratis_meter';
  SELECT value::numeric INTO v_tarif FROM public.operational_settings WHERE key = 'travel_tarif_per_meter';
  IF v_gratis_meter IS NULL OR v_tarif IS NULL THEN RAISE EXCEPTION 'Aturan travel fee belum tersedia'; END IF;

  IF p_tipe_lokasi = 'DI_TEMPAT' THEN
    v_travel_fee := 0;
  ELSE
    v_travel_fee := round(greatest(p_jarak_meter - v_gratis_meter, 0) * v_tarif);
  END IF;

  v_subtotal := v_package_price + v_travel_fee;
  IF v_config.package_key IS NOT NULL
     AND v_config.promo_type <> 'none'
     AND v_config.promo_start_date <= p_tanggal
     AND v_config.promo_end_date >= p_tanggal THEN
    v_promo_type := v_config.promo_type;
    v_promo_value := v_config.promo_value;
    IF v_promo_type = 'percent' THEN
      v_promo_discount := least(v_subtotal, round(v_subtotal * v_promo_value / 100));
    ELSIF v_promo_type = 'nominal' THEN
      v_promo_discount := least(v_subtotal, round(v_promo_value));
    END IF;
  END IF;
  v_final_total := greatest(v_subtotal - v_promo_discount, 0);

  INSERT INTO public.customers (id, nama, wa)
  VALUES (p_customer_id, btrim(p_nama), btrim(p_wa))
  ON CONFLICT (id) DO UPDATE SET nama = excluded.nama, wa = excluded.wa;

  INSERT INTO public.bookings (
    customer_id, nama_pelanggan, wa_pelanggan, service_id, jumlah_orang, tanggal, jam_mulai,
    durasi_menit, tipe_lokasi, alamat, lat, lng, jarak_meter, service_price, travel_fee,
    grand_total, package_key, base_price, price_level, package_price, subtotal,
    promo_type, promo_value, promo_discount, final_total, status
  ) VALUES (
    p_customer_id, btrim(p_nama), btrim(p_wa), p_service_id, p_jumlah_orang, p_tanggal, p_jam_mulai,
    v_durasi_menit, p_tipe_lokasi, p_alamat, p_lat, p_lng,
    CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN p_jarak_meter ELSE NULL END,
    v_package_price, v_travel_fee, v_final_total, v_package_key, v_base_price, v_level,
    v_package_price, v_subtotal, v_promo_type, v_promo_value, v_promo_discount, v_final_total, 'MENUNGGU'
  ) RETURNING * INTO v_booking;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id,
    'status', v_booking.status,
    'service_price', v_booking.service_price,
    'travel_fee', v_booking.travel_fee,
    'grand_total', v_booking.grand_total,
    'package_key', v_booking.package_key,
    'base_price', v_booking.base_price,
    'price_level', v_booking.price_level,
    'package_price', v_booking.package_price,
    'subtotal', v_booking.subtotal,
    'promo_type', v_booking.promo_type,
    'promo_value', v_booking.promo_value,
    'promo_discount', v_booking.promo_discount,
    'final_total', v_booking.final_total
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_booking_server(uuid,text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_booking_server(uuid,text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) TO service_role;

 
-- Keep the legacy authenticated RPC aligned with the same authoritative price engine.
-- The Edge Function calls create_booking_server only after calculating Google Routes distance.
CREATE OR REPLACE FUNCTION public.create_booking(
  p_nama text,
  p_wa text,
  p_service_id text,
  p_jumlah_orang smallint,
  p_tanggal date,
  p_jam_mulai time without time zone,
  p_tipe_lokasi public.tipe_lokasi,
  p_alamat text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_jarak_meter numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $legacy$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Anda harus login (verifikasi email) terlebih dahulu sebelum membuat booking'
      USING errcode = '28000';
  END IF;

  RETURN public.create_booking_server(
    auth.uid(), p_nama, p_wa, p_service_id, p_jumlah_orang,
    p_tanggal, p_jam_mulai, p_tipe_lokasi, p_alamat, p_lat, p_lng, p_jarak_meter
  );
END;
$legacy$;

REVOKE ALL ON FUNCTION public.create_booking(text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_booking(text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) TO authenticated;
