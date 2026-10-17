-- Expire unconfirmed bookings after their requested start time.
-- Interpret the date + time in Maduran's operational timezone (WIB / Asia-Jakarta).
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

CREATE OR REPLACE FUNCTION public.expire_unhandled_bookings()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.bookings AS b
     SET status = 'KEDALUWARSA'
   WHERE b.status = 'MENUNGGU'
     AND ((b.tanggal + b.jam_mulai) AT TIME ZONE 'Asia/Jakarta') <= pg_catalog.now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.expire_unhandled_bookings()
  FROM PUBLIC, anon, authenticated, service_role;

-- Prevent a scheduler delay from allowing Admin to accept a booking whose start time has passed.
CREATE OR REPLACE FUNCTION public.accept_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_booking public.bookings%rowtype;
  v_conflict record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Hanya admin yang boleh menerima booking';
  END IF;

  SELECT * INTO v_booking
    FROM public.bookings
   WHERE id = p_booking_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking tidak ditemukan';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_booking.tanggal::text));

  IF v_booking.status = 'MENUNGGU'
     AND ((v_booking.tanggal + v_booking.jam_mulai) AT TIME ZONE 'Asia/Jakarta') <= pg_catalog.now() THEN
    UPDATE public.bookings SET status = 'KEDALUWARSA' WHERE id = p_booking_id;
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'KEDALUWARSA',
      'status', 'KEDALUWARSA',
      'booking_id', p_booking_id
    );
  END IF;

  IF v_booking.status <> 'MENUNGGU' THEN
    RAISE EXCEPTION 'Booking sudah berstatus % (bukan MENUNGGU)', v_booking.status;
  END IF;

  IF NOT public._dalam_jam_operasional(v_booking.jam_mulai, v_booking.durasi_menit) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'DI_LUAR_JAM_OPERASIONAL');
  END IF;

  SELECT b.id, b.jam_mulai, b.durasi_menit
    INTO v_conflict
    FROM public.bookings b
   WHERE b.tanggal = v_booking.tanggal
     AND b.status = 'DITERIMA'
     AND b.id <> v_booking.id
     AND b.durasi_menit IS NOT NULL
     AND b.durasi_menit > 0
     AND (extract(hour from v_booking.jam_mulai)::integer * 60 + extract(minute from v_booking.jam_mulai)::integer)
         < (extract(hour from b.jam_mulai)::integer * 60 + extract(minute from b.jam_mulai)::integer + b.durasi_menit)
     AND (extract(hour from b.jam_mulai)::integer * 60 + extract(minute from b.jam_mulai)::integer)
         < (extract(hour from v_booking.jam_mulai)::integer * 60 + extract(minute from v_booking.jam_mulai)::integer + v_booking.durasi_menit)
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'BENTROK',
      'conflict_with_booking_id', v_conflict.id
    );
  END IF;

  UPDATE public.bookings SET status = 'DITERIMA' WHERE id = p_booking_id;
  RETURN jsonb_build_object('success', true, 'booking_id', p_booking_id, 'status', 'DITERIMA');
END;
$function$;

-- Allow customers to hide expired bookings from their own history without deleting records.
CREATE OR REPLACE FUNCTION public.sembunyikan_riwayat(p_booking_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_status text;
  v_hidden_at timestamptz;
BEGIN
  IF auth.uid() IS NULL OR p_booking_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT b.status::text, b.disembunyikan_pelanggan_at
    INTO v_status, v_hidden_at
    FROM public.bookings AS b
   WHERE b.id = p_booking_id
     AND b.customer_id = auth.uid()
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_status NOT IN ('SELESAI', 'DITOLAK', 'KEDALUWARSA') THEN
    RETURN false;
  END IF;

  IF v_hidden_at IS NOT NULL THEN
    RETURN true;
  END IF;

  UPDATE public.bookings AS b
     SET disembunyikan_pelanggan_at = clock_timestamp()
   WHERE b.id = p_booking_id
     AND b.customer_id = auth.uid()
     AND b.disembunyikan_pelanggan_at IS NULL;

  RETURN FOUND;
END;
$function$;

REVOKE ALL ON FUNCTION public.sembunyikan_riwayat(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sembunyikan_riwayat(uuid) TO authenticated;

-- Idempotently replace the named one-minute job.
DO $block$
DECLARE
  v_job record;
BEGIN
  FOR v_job IN SELECT jobid FROM cron.job WHERE jobname = 'sules-expire-unhandled-bookings'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
END;
$block$;

SELECT cron.schedule(
  'sules-expire-unhandled-bookings',
  '* * * * *',
  'SELECT public.expire_unhandled_bookings();'
);

COMMIT;
