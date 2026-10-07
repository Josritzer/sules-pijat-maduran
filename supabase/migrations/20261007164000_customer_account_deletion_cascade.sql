-- Account deletion: remove only bookings that belong to the customer whose
-- public.customers row is removed by the existing auth.users ON DELETE CASCADE.
-- This is atomic with Auth deletion and prevents partial deletion if the Auth
-- request fails. Existing booking rows are not changed by this migration.
ALTER TABLE public.bookings
  DROP CONSTRAINT bookings_customer_id_fkey,
  ADD CONSTRAINT bookings_customer_id_fkey
    FOREIGN KEY (customer_id)
    REFERENCES public.customers(id)
    ON DELETE CASCADE;
