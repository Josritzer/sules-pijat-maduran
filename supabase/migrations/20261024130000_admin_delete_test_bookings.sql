-- Allow Admin to permanently remove only bookings explicitly marked as test data.
BEGIN;

CREATE OR REPLACE FUNCTION public.delete_test_booking(p_booking_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $delete_test$
DECLARE
  v_booking_id uuid;
BEGIN
  IF public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh menghapus data uji'
      USING ERRCODE = '42501';
  END IF;

  IF p_booking_id IS NULL THEN
    RAISE EXCEPTION 'ID booking wajib diisi';
  END IF;

  SELECT b.id INTO v_booking_id
  FROM public.bookings b
  WHERE b.id = p_booking_id
    AND b.is_test_booking IS TRUE
  FOR UPDATE;

  IF v_booking_id IS NULL THEN
    RAISE EXCEPTION 'Booking tidak ditemukan atau bukan data uji';
  END IF;

  -- Remove only payment rows attached to this explicitly marked test booking;
  -- the payment_transactions FK otherwise restricts booking deletion.
  DELETE FROM public.payment_transactions
  WHERE booking_id = v_booking_id;

  DELETE FROM public.bookings
  WHERE id = v_booking_id
    AND is_test_booking IS TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Data uji gagal dihapus; tidak ada perubahan yang dikonfirmasi';
  END IF;

  RETURN jsonb_build_object('success', true, 'deleted_booking_id', v_booking_id);
END;
$delete_test$;

REVOKE ALL ON FUNCTION public.delete_test_booking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_test_booking(uuid) TO authenticated;

COMMIT;
