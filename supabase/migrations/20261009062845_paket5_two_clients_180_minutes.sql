-- Paket 5: one therapist serves two customers sequentially (90 + 90 minutes).
-- This version is already recorded in Supabase production as 20261009062845.
-- Keep this source synchronized with the deployed create_booking_server RPC.

CREATE OR REPLACE FUNCTION public.create_booking_server(p_customer_id uuid, p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_jarak_meter numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_service public.services%rowtype;
  v_gratis_meter numeric;
  v_tarif numeric;
  v_service_price numeric;
  v_travel_fee numeric;
  v_durasi_menit integer;
  v_booking public.bookings%rowtype;
BEGIN
  IF p_customer_id IS NULL THEN RAISE EXCEPTION 'Customer ID wajib'; END IF;
  IF p_nama IS NULL OR btrim(p_nama) = '' THEN RAISE EXCEPTION 'Nama pelanggan wajib diisi'; END IF;
  IF p_wa IS NULL OR btrim(p_wa) = '' THEN RAISE EXCEPTION 'Nomor WA wajib diisi'; END IF;
  IF p_jumlah_orang IS NULL OR p_jumlah_orang < 1 OR p_jumlah_orang > 2 THEN RAISE EXCEPTION 'Jumlah orang harus 1 atau 2'; END IF;
  IF p_tanggal IS NULL OR p_tanggal < timezone('Asia/Jakarta', now())::date THEN RAISE EXCEPTION 'Tanggal booking tidak valid atau sudah lewat'; END IF;
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

  v_durasi_menit := CASE
    WHEN p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN 180
    ELSE v_service.durasi_menit
  END;

  IF NOT public._dalam_jam_operasional(p_jam_mulai, v_durasi_menit) THEN
    RAISE EXCEPTION 'Jam di luar jam operasional atau melewati jam tutup';
  END IF;

  IF p_tipe_lokasi = 'HOME_SERVICE' THEN
    IF p_lat IS NULL OR p_lng IS NULL OR p_lat::text = 'NaN' OR p_lng::text = 'NaN' OR
       p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
      RAISE EXCEPTION 'Home Service wajib menyertakan lokasi valid (lat/lng)';
    END IF;
    IF p_jarak_meter IS NULL OR p_jarak_meter < 0 OR p_jarak_meter::text IN ('NaN', 'Infinity', '-Infinity') THEN
      RAISE EXCEPTION 'Jarak tempuh Google Routes wajib untuk Home Service';
    END IF;
  END IF;

  IF p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN
    v_service_price := 120000;
  ELSE
    v_service_price := v_service.harga * p_jumlah_orang;
  END IF;

  SELECT value::numeric INTO v_gratis_meter FROM public.operational_settings WHERE key = 'travel_gratis_meter';
  SELECT value::numeric INTO v_tarif FROM public.operational_settings WHERE key = 'travel_tarif_per_meter';
  IF v_gratis_meter IS NULL OR v_tarif IS NULL THEN RAISE EXCEPTION 'Aturan travel fee belum tersedia'; END IF;

  IF p_tipe_lokasi = 'DI_TEMPAT' THEN
    v_travel_fee := 0;
  ELSE
    v_travel_fee := greatest(p_jarak_meter - v_gratis_meter, 0) * v_tarif;
  END IF;

  INSERT INTO public.customers (id, nama, wa)
  VALUES (p_customer_id, btrim(p_nama), btrim(p_wa))
  ON CONFLICT (id) DO UPDATE SET nama = excluded.nama, wa = excluded.wa;

  INSERT INTO public.bookings (
    customer_id, nama_pelanggan, wa_pelanggan, service_id, jumlah_orang, tanggal, jam_mulai,
    durasi_menit, tipe_lokasi, alamat, lat, lng, jarak_meter, service_price, travel_fee, status
  ) VALUES (
    p_customer_id, btrim(p_nama), btrim(p_wa), p_service_id, p_jumlah_orang, p_tanggal, p_jam_mulai,
    v_durasi_menit, p_tipe_lokasi, p_alamat, p_lat, p_lng,
    CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN p_jarak_meter ELSE NULL END,
    v_service_price, v_travel_fee, 'MENUNGGU'
  ) RETURNING * INTO v_booking;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id, 'access_token', v_booking.access_token, 'status', v_booking.status,
    'service_price', v_booking.service_price, 'travel_fee', v_booking.travel_fee, 'grand_total', v_booking.grand_total
  );
END;
$function$;
