-- Queue a neutral Google review invitation one hour after a booking transitions to SELESAI.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.google_review_email_queue (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id uuid NOT NULL UNIQUE REFERENCES public.bookings(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL,
  customer_name text NOT NULL DEFAULT 'Kak',
  scheduled_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  locked_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX IF NOT EXISTS google_review_email_queue_due_idx
  ON public.google_review_email_queue (scheduled_at)
  WHERE status = 'pending';

ALTER TABLE public.google_review_email_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.google_review_email_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.google_review_email_queue TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.google_review_email_queue_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_google_review_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NEW.status = 'SELESAI' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.google_review_email_queue (
      booking_id, customer_id, customer_name, scheduled_at
    )
    VALUES (
      NEW.id,
      NEW.customer_id,
      COALESCE(NULLIF(btrim(NEW.nama_pelanggan), ''), 'Kak'),
      pg_catalog.clock_timestamp() + interval '1 hour'
    )
    ON CONFLICT (booking_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enqueue_google_review_email ON public.bookings;
CREATE TRIGGER trg_enqueue_google_review_email
AFTER UPDATE OF status ON public.bookings
FOR EACH ROW
WHEN (NEW.status = 'SELESAI' AND OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.enqueue_google_review_email();

CREATE OR REPLACE FUNCTION public.claim_google_review_emails(p_limit integer DEFAULT 20)
RETURNS TABLE (booking_id uuid, customer_id uuid, customer_name text, attempts integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  -- Recover jobs abandoned by a worker that stopped mid-request.
  UPDATE public.google_review_email_queue q
     SET status = 'pending', locked_at = NULL,
         scheduled_at = pg_catalog.clock_timestamp() + interval '5 minutes',
         updated_at = pg_catalog.clock_timestamp()
   WHERE q.status = 'processing'
     AND q.locked_at < pg_catalog.clock_timestamp() - interval '10 minutes';

  RETURN QUERY
  WITH due AS (
    SELECT q.id
      FROM public.google_review_email_queue q
     WHERE q.status = 'pending'
       AND q.scheduled_at <= pg_catalog.clock_timestamp()
     ORDER BY q.scheduled_at
     FOR UPDATE SKIP LOCKED
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)
  )
  UPDATE public.google_review_email_queue q
     SET status = 'processing',
         attempts = q.attempts + 1,
         locked_at = pg_catalog.clock_timestamp(),
         updated_at = pg_catalog.clock_timestamp()
    FROM due
   WHERE q.id = due.id
  RETURNING q.booking_id, q.customer_id, q.customer_name, q.attempts;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_google_review_emails(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_google_review_emails(integer) TO service_role;

-- Recreate the named minute job idempotently. It authenticates to the worker using
-- the existing secret already stored in Supabase Vault for notify-booking.
DO $block$
DECLARE v_job record;
BEGIN
  FOR v_job IN SELECT jobid FROM cron.job WHERE jobname = 'sules-google-review-email-worker'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
END;
$block$;

SELECT cron.schedule(
  'sules-google-review-email-worker',
  '* * * * *',
  $job$
    SELECT net.http_post(
      url := 'https://tzupkourtcmqemymszgt.supabase.co/functions/v1/google-review-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', public.get_secret('notify_booking_webhook_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 10000
    );
  $job$
);

COMMIT;
