-- Add terminal status for unconfirmed bookings whose requested start time has passed.
-- Keep this enum change separate from functions that use the new value.
ALTER TYPE public.booking_status ADD VALUE IF NOT EXISTS 'KEDALUWARSA';
