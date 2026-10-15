-- Keep Level 1 equal to the approved base price; Level 5 reaches approved target prices.
-- Standard packages add Rp12,500 per level above Level 1; two-person package adds Rp25,000.
BEGIN;

CREATE OR REPLACE FUNCTION public.create_booking_server(p_customer_id uuid, p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_jarak_meter numeric DEFAULT NULL::numeric)
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
  v_promo_target text := 'active_level';
  v_promo_basis numeric := 0;
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
  -- Level 0 is the base mathematically; configured Levels 1-5 add 10% of base per level.
  v_package_price := v_base_price + (v_level - 1) * CASE WHEN v_package_key = 'home-90m-2' THEN 25000 ELSE 12500 END;

  v_durasi_menit := CASE
    WHEN p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN 180
    ELSE v_service.durasi_menit
  END;

  IF NOT public._dalam_jam_operasional(p_jam_mulai, v_durasi_menit) THEN
    RAISE EXCEPTION 'Jam di luar jam operasional atau melewati jam tutup';
  END IF;

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
    v_promo_target := CASE WHEN v_config.promo_target = 'base' THEN 'base' ELSE 'active_level' END;
    v_promo_value := v_config.promo_value;
    v_promo_basis := CASE WHEN v_promo_target = 'base' THEN v_base_price ELSE v_package_price END;
    IF v_promo_type = 'percent' THEN
      v_promo_discount := least(v_promo_basis, round(v_promo_basis * v_promo_value / 100));
    ELSIF v_promo_type = 'nominal' THEN
      v_promo_discount := least(v_promo_basis, round(v_promo_value));
    END IF;
  END IF;
  v_final_total := greatest(v_subtotal - v_promo_discount, 0);

  INSERT INTO public.customers (id, nama, wa)
  VALUES (p_customer_id, btrim(p_nama), btrim(p_wa)
  ) ON CONFLICT (id) DO UPDATE SET nama = excluded.nama, wa = excluded.wa;

  INSERT INTO public.bookings (
    customer_id, nama_pelanggan, wa_pelanggan, service_id, jumlah_orang, tanggal, jam_mulai,
    durasi_menit, tipe_lokasi, alamat, lat, lng, jarak_meter, service_price, travel_fee,
    grand_total, package_key, base_price, price_level, package_price, subtotal,
    promo_type, promo_target, promo_value, promo_discount, final_total, status
  ) VALUES (
    p_customer_id, btrim(p_nama), btrim(p_wa), p_service_id, p_jumlah_orang, p_tanggal, p_jam_mulai,
    v_durasi_menit, p_tipe_lokasi, p_alamat, p_lat, p_lng,
    CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN p_jarak_meter ELSE NULL END,
    v_package_price, v_travel_fee, v_final_total, v_package_key, v_base_price, v_level,
    v_package_price, v_subtotal, v_promo_type, v_promo_target, v_promo_value, v_promo_discount, v_final_total, 'MENUNGGU'
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
    'promo_target', v_booking.promo_target,
    'promo_value', v_booking.promo_value,
    'promo_discount', v_booking.promo_discount,
    'final_total', v_booking.final_total
  );
END;
$function$;

COMMIT;
