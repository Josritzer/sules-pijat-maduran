-- Sules security and booking validation hardening.
-- No customer or booking rows are read, changed, or deleted by this migration.

DO $$
DECLARE
  v_secret text;
BEGIN
  IF EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'notify_booking_webhook_secret') THEN
    RAISE EXCEPTION 'notify_booking_webhook_secret already exists; inspect Vault metadata before rotating';
  END IF;
  v_secret := gen_random_uuid()::text || gen_random_uuid()::text || gen_random_uuid()::text || gen_random_uuid()::text;
  PERFORM vault.create_secret(
    v_secret,
    'notify_booking_webhook_secret',
    'Rotated shared authentication secret for the Sules booking notification trigger',
    NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._dalam_jam_operasional(
  p_jam_mulai time without time zone,
  p_durasi_menit integer
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pagi jsonb;
  v_malam jsonb;
  v_start_minutes integer;
  v_pagi_open integer;
  v_pagi_close integer;
  v_malam_open integer;
  v_malam_close integer;
BEGIN
  IF p_jam_mulai IS NULL OR p_durasi_menit IS NULL OR p_durasi_menit <= 0 THEN
    RETURN false;
  END IF;
  IF extract(second FROM p_jam_mulai) <> 0 OR mod(extract(minute FROM p_jam_mulai)::integer, 30) <> 0 THEN
    RETURN false;
  END IF;

  SELECT value INTO v_pagi FROM operational_settings WHERE key = 'jam_operasional_pagi';
  SELECT value INTO v_malam FROM operational_settings WHERE key = 'jam_operasional_malam';
  IF v_pagi IS NULL OR v_malam IS NULL THEN
    RETURN false;
  END IF;

  v_start_minutes := extract(hour FROM p_jam_mulai)::integer * 60 + extract(minute FROM p_jam_mulai)::integer;
  v_pagi_open := split_part(v_pagi ->> 'mulai', ':', 1)::integer * 60 + split_part(v_pagi ->> 'mulai', ':', 2)::integer;
  v_pagi_close := split_part(v_pagi ->> 'selesai', ':', 1)::integer * 60 + split_part(v_pagi ->> 'selesai', ':', 2)::integer;
  v_malam_open := split_part(v_malam ->> 'mulai', ':', 1)::integer * 60 + split_part(v_malam ->> 'mulai', ':', 2)::integer;
  v_malam_close := split_part(v_malam ->> 'selesai', ':', 1)::integer * 60 + split_part(v_malam ->> 'selesai', ':', 2)::integer;

  IF v_start_minutes >= v_pagi_open AND v_start_minutes + p_durasi_menit <= v_pagi_close THEN
    RETURN true;
  END IF;
  IF v_start_minutes >= v_malam_open AND v_start_minutes + p_durasi_menit <= v_malam_close THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$function$;

REVOKE ALL ON FUNCTION public._dalam_jam_operasional(time without time zone, integer) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_booking_server(
  p_customer_id uuid,
  p_nama text,
  p_wa text,
  p_service_id text,
  p_jumlah_orang smallint,
  p_tanggal date,
  p_jam_mulai time without time zone,
  p_tipe_lokasi tipe_lokasi,
  p_alamat text DEFAULT NULL::text,
  p_lat double precision DEFAULT NULL::double precision,
  p_lng double precision DEFAULT NULL::double precision,
  p_jarak_meter numeric DEFAULT NULL::numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_service services%rowtype;
  v_gratis_meter numeric;
  v_tarif numeric;
  v_service_price numeric;
  v_travel_fee numeric;
  v_booking bookings%rowtype;
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

  SELECT * INTO v_service FROM services WHERE id = p_service_id AND aktif = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Layanan tidak ditemukan'; END IF;
  IF NOT _dalam_jam_operasional(p_jam_mulai, v_service.durasi_menit) THEN
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

  SELECT value::numeric INTO v_gratis_meter FROM operational_settings WHERE key = 'travel_gratis_meter';
  SELECT value::numeric INTO v_tarif FROM operational_settings WHERE key = 'travel_tarif_per_meter';
  IF v_gratis_meter IS NULL OR v_tarif IS NULL THEN RAISE EXCEPTION 'Aturan travel fee belum tersedia'; END IF;

  IF p_tipe_lokasi = 'DI_TEMPAT' THEN
    v_travel_fee := 0;
  ELSE
    v_travel_fee := greatest(p_jarak_meter - v_gratis_meter, 0) * v_tarif;
  END IF;

  INSERT INTO customers (id, nama, wa)
  VALUES (p_customer_id, btrim(p_nama), btrim(p_wa))
  ON CONFLICT (id) DO UPDATE SET nama = excluded.nama, wa = excluded.wa;

  INSERT INTO bookings (
    customer_id, nama_pelanggan, wa_pelanggan, service_id, jumlah_orang, tanggal, jam_mulai,
    durasi_menit, tipe_lokasi, alamat, lat, lng, jarak_meter, service_price, travel_fee, status
  ) VALUES (
    p_customer_id, btrim(p_nama), btrim(p_wa), p_service_id, p_jumlah_orang, p_tanggal, p_jam_mulai,
    v_service.durasi_menit, p_tipe_lokasi, p_alamat, p_lat, p_lng,
    CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN p_jarak_meter ELSE NULL END,
    v_service_price, v_travel_fee, 'MENUNGGU'
  ) RETURNING * INTO v_booking;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id, 'access_token', v_booking.access_token, 'status', v_booking.status,
    'service_price', v_booking.service_price, 'travel_fee', v_booking.travel_fee, 'grand_total', v_booking.grand_total
  );
END;
$function$;

-- Keep the legacy RPC present for later migration of any unknown external clients,
-- but do not allow authenticated browsers to bypass server-calculated Google Routes.
REVOKE EXECUTE ON FUNCTION public.create_booking(text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_booking(text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) TO service_role;

-- Restrict the server-only booking RPC explicitly to its trusted caller.
REVOKE EXECUTE ON FUNCTION public.create_booking_server(uuid,text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_booking_server(uuid,text,text,text,smallint,date,time without time zone,public.tipe_lokasi,text,double precision,double precision,numeric) TO service_role;

CREATE OR REPLACE FUNCTION public.notify_new_booking()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer customers%rowtype;
  v_payload jsonb;
  v_webhook_secret text;
BEGIN
  -- Email delivery must never prevent the source-of-truth booking insert.
  BEGIN
    SELECT * INTO v_customer FROM customers WHERE id = NEW.customer_id;
    v_webhook_secret := public.get_secret('notify_booking_webhook_secret');
    IF v_webhook_secret IS NULL OR v_webhook_secret = '' THEN
      RAISE EXCEPTION 'notification secret unavailable';
    END IF;

    v_payload := jsonb_build_object(
      'nama', coalesce(NEW.nama_pelanggan, v_customer.nama),
      'wa', coalesce(NEW.wa_pelanggan, v_customer.wa),
      'service_id', NEW.service_id,
      'jumlah_orang', NEW.jumlah_orang,
      'tanggal', NEW.tanggal,
      'jam_mulai', NEW.jam_mulai,
      'tipe_lokasi', NEW.tipe_lokasi,
      'alamat', NEW.alamat,
      'travel_fee', NEW.travel_fee,
      'service_price', NEW.service_price,
      'grand_total', NEW.grand_total
    );

    PERFORM net.http_post(
      url := 'https://tzupkourtcmqemymszgt.supabase.co/functions/v1/notify-booking',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', v_webhook_secret
      ),
      body := v_payload
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Booking notification enqueue failed; booking insert continues.';
  END;
  RETURN NEW;
END;
$function$;
