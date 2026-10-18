# SL Relax iPaymu API

Backend service intended for a VPS with a **static public IP**. It creates hosted iPaymu Redirect Payment sessions and processes signed callbacks. Do not expose iPaymu or Supabase service-role secrets to the browser.

## Required environment variables

See `.env.example`. Keep all real values in the VPS environment/secrets manager. Start in Sandbox; Sandbox and Production credentials are separate.

## Endpoints

- `GET /health` — health check.
- `POST /api/payments` — requires a Supabase customer access token; JSON `{ "bookingId": "<uuid>" }`. Only the booking owner may create a payment, and only when booking status is `DITERIMA`. The amount is read from Supabase, never from the browser.
- `GET /api/payments/:bookingId` — requires a customer access token and returns that customer's latest payment status.
- `POST /ipaymu/callback` — public callback endpoint; verifies iPaymu `X-Signature` with the merchant VA, validates reference and amount, and handles retries idempotently.

## Before Sandbox testing

1. Apply the migration `supabase/migrations/20261024_ipaymu_payments.sql` in a reviewable deployment step.
2. Deploy this service on a VPS with a static IP, configure TLS for `api.bookingpijat.com`, and set environment variables.
3. Configure the iPaymu Sandbox callback to `https://api.bookingpijat.com/ipaymu/callback` and the same callback content format documented in iPaymu (JSON or URL-encoded).
4. Add the Sandbox VA and API key only to the VPS environment; never put them in frontend files, GitHub, or chat.
5. Test accepted booking -> checkout redirect -> signed callback -> payment status update. Never treat the browser return URL as proof of payment.

## Production checklist

- Use Production VA/API key and API base URL only after merchant approval.
- Register the VPS static IP and all domains/subdomains used in request URLs with iPaymu.
- Keep the public site on Vercel and Supabase as the booking/database source of truth.
- Keep payment status separate from booking status. A paid callback does not auto-accept, complete, or reschedule a booking.
- Confirm iPaymu callback signature behavior and amount semantics with Sandbox test callbacks before Production.

## Deployment safety

This directory is not deployed by Vercel's static frontend. Deploy it separately to the VPS. Do not merge or apply the database migration to production until the PR is reviewed and Sandbox credentials are available for end-to-end testing.
