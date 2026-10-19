# Admin Web Push Notifications — Setup Notes

This branch adds an opt-in Web Push path for Admin booking notifications. It does not deploy functions or apply the database migration.

## Required Supabase Vault secrets

Set these only after explicit approval, using the existing `get_secret` RPC/Vault workflow:

- `web_push_vapid_public_key`: VAPID public key (safe to expose only through the admin-validated `admin-push-config` function).
- `web_push_vapid_private_key`: VAPID private key; never expose to browser or commit.
- `web_push_vapid_subject`: contact URI such as `mailto:admin@bookingpijat.com`.

The VAPID public/private keys must be a matching pair. Do not use a random key or an iPaymu secret.

## Rollout order

1. Review code and confirm the Web Push package works in Supabase Edge Runtime.
2. Generate a fresh VAPID key pair in a trusted environment; never paste the private key into source control or chat.
3. Apply `supabase/migrations/20261019010000_admin_push_subscriptions.sql` only after explicit approval.
4. Add the three Vault secrets only after explicit approval.
5. Deploy `admin-push-config` and the updated `notify-booking` Edge Function only after explicit approval.
6. Open Dashboard Admin on Chrome/Android and press **Aktifkan notifikasi HP**; grant browser permission.
7. Test a new booking with the app closed, tap the notification, and verify Dashboard Admin opens. Also verify email still works when push delivery fails.

## Security and behavior

- Browser subscription is saved only for the authenticated Admin whose ID exists in `public.admins`.
- Push subscriptions are protected by RLS; service role is used only inside the Edge Function.
- Push delivery is best-effort and must not change booking/payment status or block booking creation.
- Push click opens `/?admin=1`; the Admin screen still requires valid Admin authentication.
- Service worker and browser/OS support are required. Delivery may be delayed or unavailable if the browser disables background activity.
