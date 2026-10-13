-- Buka/Tutup sesi siang & malam.
-- Konfigurasi: operational_settings sesi_pagi / sesi_malam = {"buka":true,"pesan":"","sampai":null}.
-- Cek penutupan HANYA di create_booking_server (accept_booking & _dalam_jam_operasional tidak diubah).
-- Rollback: supabase/rollbacks/20261013_sesi_buka_tutup_rollback.sql

BEGIN;

INSERT INTO public.operational_settings (key, value) VALUES
  ('sesi_pagi',  '{"buka": true, "pesan": "", "sampai": null}'::jsonb),
  ('sesi_malam', '{"buka": true, "pesan": "", "sampai": null}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Helper internal: NULL = boleh booking; teks = pesan penolakan. Fail-open pada data rusak/hilang.
CREATE OR REPLACE FUNCTION public._pesan_sesi_tutup(p_tanggal date, p_jam_mulai time without time zone)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_key text;
  v_nama text;
  v_val jsonb;
  v_sampai date;
BEGIN
  IF p_tanggal IS NULL OR p_jam_mulai IS NULL THEN RETURN NULL; END IF;
  IF p_jam_mulai < time '17:00' THEN v_key := 'sesi_pagi'; v_nama := 'siang';
  ELSE v_key := 'sesi_malam'; v_nama := 'malam'; END IF;

  BEGIN
    SELECT value INTO v_val FROM public.operational_settings WHERE key = v_key;
    IF v_val IS NULL OR jsonb_typeof(v_val) <> 'object' THEN RETURN NULL; END IF;
    IF v_val->'buka' IS DISTINCT FROM 'false'::jsonb THEN RETURN NULL; END IF;
    IF v_val->>'sampai' IS NULL OR btrim(v_val->>'sampai') = '' THEN
      RETURN 'Sesi ' || v_nama || ' sedang ditutup. Silakan pilih sesi lain atau coba lagi nanti.';
    END IF;
    v_sampai := (v_val->>'sampai')::date;
    IF p_tanggal <= v_sampai THEN
      RETURN 'Sesi ' || v_nama || ' ditutup sampai ' || to_char(v_sampai, 'DD-MM-YYYY') || '. Silakan pilih tanggal setelahnya atau sesi lain.';
    END IF;
    RETURN NULL;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_pesan_sesi_tutup gagal dibaca (fail-open): %', SQLSTATE;
    RETURN NULL;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public._pesan_sesi_tutup(date, time without time zone) FROM PUBLIC, anon, authenticated;

-- create_booking_server: definisi produksi 20261009062845 + SATU blok cek sesi (setelah cek jam operasional).
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
  v_service_price numeric;
  v_travel_fee numeric;
  v_durasi_menit integer;
  v_booking public.bookings%rowtype;
  v_sesi_tutup text;
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

  -- Sesi ditutup Admin (siang < 17:00, malam >= 17:00). Hanya booking BARU; fail-open bila konfigurasi rusak.
  v_sesi_tutup := public._pesan_sesi_tutup(p_tanggal, p_jam_mulai);
  IF v_sesi_tutup IS NOT NULL THEN
    RAISE EXCEPTION '%', v_sesi_tutup;
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

-- RPC Admin: tutup / buka kembali satu sesi ('pagi' | 'malam').
CREATE OR REPLACE FUNCTION public.admin_set_sesi(p_sesi text, p_buka boolean, p_sampai date DEFAULT NULL, p_pesan text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_key text;
  v_val jsonb;
  v_pesan text;
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengubah sesi';
  END IF;
  IF p_sesi NOT IN ('pagi', 'malam') THEN RAISE EXCEPTION 'Sesi tidak valid'; END IF;
  IF p_buka IS NULL THEN RAISE EXCEPTION 'Status sesi wajib diisi'; END IF;
  v_key := 'sesi_' || p_sesi;

  IF p_buka THEN
    v_val := '{"buka": true, "pesan": "", "sampai": null}'::jsonb;
  ELSE
    IF p_sampai IS NOT NULL AND p_sampai < timezone('Asia/Jakarta', now())::date THEN
      RAISE EXCEPTION 'Tanggal batas penutupan sudah lewat';
    END IF;
    IF p_sampai IS NOT NULL AND p_sampai > timezone('Asia/Jakarta', now())::date + 365 THEN
      RAISE EXCEPTION 'Tanggal batas penutupan terlalu jauh';
    END IF;
    v_pesan := left(btrim(coalesce(p_pesan, '')), 200);
    v_val := jsonb_build_object('buka', false, 'pesan', v_pesan, 'sampai', p_sampai);
  END IF;

  INSERT INTO public.operational_settings (key, value) VALUES (v_key, v_val)
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();

  RETURN v_val;
END;
$function$;

-- Informasi saja: jumlah booking MENUNGGU/DITERIMA yang tercakup penutupan (tidak mengubah apa pun).
CREATE OR REPLACE FUNCTION public.admin_sesi_ringkasan()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_hari date := timezone('Asia/Jakarta', now())::date;
  v_out jsonb := '{}'::jsonb;
  v_key text;
  v_val jsonb;
  v_sampai date;
  v_menunggu int;
  v_diterima int;
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh melihat ringkasan sesi';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['sesi_pagi', 'sesi_malam'] LOOP
    v_menunggu := 0; v_diterima := 0;
    SELECT value INTO v_val FROM public.operational_settings WHERE key = v_key;
    IF v_val IS NOT NULL AND jsonb_typeof(v_val) = 'object' AND v_val->'buka' = 'false'::jsonb THEN
      BEGIN
        v_sampai := nullif(btrim(coalesce(v_val->>'sampai', '')), '')::date;
      EXCEPTION WHEN OTHERS THEN v_sampai := NULL; v_menunggu := -1; END;
      IF v_menunggu <> -1 THEN
        SELECT count(*) FILTER (WHERE b.status = 'MENUNGGU'), count(*) FILTER (WHERE b.status = 'DITERIMA')
          INTO v_menunggu, v_diterima
        FROM public.bookings b
        WHERE b.tanggal >= v_hari AND (v_sampai IS NULL OR b.tanggal <= v_sampai)
          AND (CASE WHEN v_key = 'sesi_pagi' THEN b.jam_mulai < time '17:00' ELSE b.jam_mulai >= time '17:00' END);
      ELSE v_menunggu := 0; END IF;
    END IF;
    v_out := v_out || jsonb_build_object(v_key, jsonb_build_object('menunggu', v_menunggu, 'diterima', v_diterima));
  END LOOP;
  RETURN v_out;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_sesi(text, boolean, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_sesi(text, boolean, date, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_sesi_ringkasan() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_sesi_ringkasan() TO authenticated;

COMMIT;
