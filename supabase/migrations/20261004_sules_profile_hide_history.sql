-- Sules FIX 1/FIX 2: server-authoritative profile and customer-only history hiding.
-- Adding the nullable column performs no UPDATE/backfill; all existing rows remain NULL.
BEGIN;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS disembunyikan_pelanggan_at timestamptz NULL;

-- The existing trigger normally updates updated_at for every UPDATE. A history-hide
-- operation must change only disembunyikan_pelanggan_at, so preserve updated_at when
-- every other row field is byte-for-byte unchanged. Ordinary updates still receive now().
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF (to_jsonb(NEW) - 'disembunyikan_pelanggan_at') IS DISTINCT FROM
     (to_jsonb(OLD) - 'disembunyikan_pelanggan_at') THEN
    NEW.updated_at := now();
  ELSE
    NEW.updated_at := OLD.updated_at;
  END IF;
  RETURN NEW;
END;
$function$;

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

  -- DIBATALKAN currently has no legacy rows; do not introduce or authorize that flow.
  IF v_status NOT IN ('SELESAI', 'DITOLAK') THEN
    RETURN false;
  END IF;

  -- Idempotent: repeat calls succeed without altering the original timestamp.
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

COMMIT;
