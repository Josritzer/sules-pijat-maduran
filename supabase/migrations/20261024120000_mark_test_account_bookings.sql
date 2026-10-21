-- Mark bookings created by the dedicated test account without changing booking rules.
BEGIN;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS is_test_booking boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.mark_test_account_booking()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $test$
BEGIN
  NEW.is_test_booking := EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE u.id = NEW.customer_id
      AND u.email_confirmed_at IS NOT NULL
      AND lower(btrim(coalesce(u.email, ''))) = 'academialycium12@gmail.com'
  );
  RETURN NEW;
END;
$test$;

REVOKE ALL ON FUNCTION public.mark_test_account_booking() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_mark_test_account_booking ON public.bookings;
CREATE TRIGGER trg_mark_test_account_booking
BEFORE INSERT ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.mark_test_account_booking();

-- Tag historical bookings from this account, if any.
UPDATE public.bookings b
SET is_test_booking = true
FROM auth.users u
WHERE b.customer_id = u.id
  AND lower(btrim(coalesce(u.email, ''))) = 'academialycium12@gmail.com'
  AND b.is_test_booking IS DISTINCT FROM true;

DROP FUNCTION IF EXISTS public.list_bookings_admin(public.booking_status);
DROP FUNCTION IF EXISTS public.list_bookings_admin_period(date, date, public.booking_status);

CREATE FUNCTION public.list_bookings_admin(p_status public.booking_status DEFAULT NULL)
RETURNS TABLE(
  id uuid, nama text, wa text, service_id text, jumlah_orang smallint,
  tanggal date, jam_mulai time without time zone, tipe_lokasi public.tipe_lokasi,
  alamat text, lat double precision, lng double precision, jarak_meter numeric,
  package_key text, base_price numeric, price_level smallint, package_price numeric,
  subtotal numeric, promo_type text, promo_value numeric, promo_discount numeric,
  final_total numeric, service_price numeric, travel_fee numeric, grand_total numeric,
  status public.booking_status, created_at timestamptz, is_test_booking boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $admin$
BEGIN
  IF public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya admin yang boleh melihat daftar booking';
  END IF;
  RETURN QUERY
    SELECT b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa),
      b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai, b.tipe_lokasi,
      b.alamat, b.lat, b.lng, b.jarak_meter,
      b.package_key, b.base_price, b.price_level, b.package_price, b.subtotal,
      b.promo_type, b.promo_value, b.promo_discount, b.final_total,
      b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at, b.is_test_booking
    FROM public.bookings b
    JOIN public.customers c ON c.id = b.customer_id
    WHERE p_status IS NULL OR b.status = p_status
    ORDER BY b.created_at DESC;
END;
$admin$;

CREATE FUNCTION public.list_bookings_admin_period(
  p_start_date date, p_end_date date, p_status public.booking_status DEFAULT NULL
)
RETURNS TABLE(
  id uuid, nama text, wa text, service_id text, jumlah_orang smallint,
  tanggal date, jam_mulai time without time zone, tipe_lokasi public.tipe_lokasi,
  alamat text, lat double precision, lng double precision, jarak_meter numeric,
  package_key text, base_price numeric, price_level smallint, package_price numeric,
  subtotal numeric, promo_type text, promo_value numeric, promo_discount numeric,
  final_total numeric, service_price numeric, travel_fee numeric, grand_total numeric,
  status public.booking_status, created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $admin_period$
BEGIN
  IF public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya admin yang boleh melihat daftar booking';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_start_date > p_end_date THEN
    RAISE EXCEPTION 'Rentang tanggal tidak valid';
  END IF;
  RETURN QUERY
    SELECT b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa),
      b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai, b.tipe_lokasi,
      b.alamat, b.lat, b.lng, b.jarak_meter,
      b.package_key, b.base_price, b.price_level, b.package_price, b.subtotal,
      b.promo_type, b.promo_value, b.promo_discount, b.final_total,
      b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at
    FROM public.bookings b
    JOIN public.customers c ON c.id = b.customer_id
    WHERE b.tanggal BETWEEN p_start_date AND p_end_date
      AND (p_status IS NULL OR b.status = p_status)
    ORDER BY b.created_at DESC;
END;
$admin_period$;

REVOKE ALL ON FUNCTION public.list_bookings_admin(public.booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin(public.booking_status) TO authenticated;
REVOKE ALL ON FUNCTION public.list_bookings_admin_period(date, date, public.booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin_period(date, date, public.booking_status) TO authenticated;

 

COMMIT;
