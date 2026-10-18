-- iPaymu payment records for SL Relax.
-- Payment status is separate from booking lifecycle; callbacks never auto-accept/reject bookings.
CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'ipaymu' CHECK (provider = 'ipaymu'),
  environment text NOT NULL CHECK (environment IN ('sandbox', 'production')),
  reference_id text NOT NULL UNIQUE,
  provider_session_id text,
  provider_transaction_id text,
  checkout_url text,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'INITIATING'
    CHECK (status IN ('INITIATING', 'PENDING', 'PAID', 'EXPIRED', 'FAILED', 'CANCELLED')),
  provider_status_code integer,
  paid_at timestamptz,
  last_callback_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payments_booking_created_idx
  ON public.payments (booking_id, created_at DESC);
CREATE INDEX IF NOT EXISTS payments_customer_created_idx
  ON public.payments (customer_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS payments_one_open_attempt_per_booking_idx
  ON public.payments (booking_id)
  WHERE status IN ('INITIATING', 'PENDING');

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payments_read_own_or_admin ON public.payments;
CREATE POLICY payments_read_own_or_admin
  ON public.payments
  FOR SELECT
  TO authenticated
  USING (customer_id = auth.uid() OR public.is_admin(auth.uid()));

REVOKE ALL ON public.payments FROM anon, authenticated;
GRANT SELECT ON public.payments TO authenticated;
GRANT ALL ON public.payments TO service_role;

COMMENT ON TABLE public.payments IS
  'iPaymu payment attempts. Payment state is separate from booking status and is only updated by trusted server callbacks.';
