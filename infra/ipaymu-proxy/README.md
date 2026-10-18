# iPaymu Redirect Proxy (Sandbox-first)

This service is an outbound-only proxy for iPaymu Redirect Payment. It is intended to run on the CubePath VPS so iPaymu sees the VPS's verified static outbound IPv4 address.

## Safety

- Defaults to iPaymu Sandbox.
- Never deploy with Production credentials until the Sandbox flow is tested and the merchant IP/domain are accepted by iPaymu.
- Never expose `IPAYMU_API_KEY` or `PROXY_SHARED_SECRET` to the browser or repository.
- The caller must be a trusted server-side Supabase Edge Function. This service does not trust browser requests.
- This service creates a checkout session only. It does not mark a booking paid; payment status must come from a separately verified callback handler.
- No VPS or production resource is created by this repository change.

## Environment

Required:
- `PORT` (default 8080)
- `PROXY_SHARED_SECRET` (long random secret shared only with the Supabase Edge Function)
- `IPAYMU_VA`
- `IPAYMU_API_KEY`
- `IPAYMU_ENV=sandbox` (only `sandbox` is permitted by the initial scaffold)
- `PUBLIC_BASE_URL=https://bookingpijat.com`
- `IPAYMU_NOTIFY_URL=https://tzupkourtcmqemymszgt.supabase.co/functions/v1/ipaymu-callback`

## API

`POST /v1/redirect-payment`

Authorization: `Bearer <PROXY_SHARED_SECRET>`

Body:
```json
{
  "referenceId": "payment-uuid",
  "amount": 60000,
  "productName": "Pijat 90 Menit",
  "description": "Booking SL Relax"
}
```

The proxy validates the request, signs the raw iPaymu API request body with HMAC-SHA256, and returns only `sessionId` and `checkoutUrl` on success. The Supabase caller must derive the amount and product name from the persisted booking/payment record, never from browser-supplied prices.

## Run locally

```sh
node server.mjs
```

Do not expose this service publicly until a reverse proxy/TLS termination, firewall, rate limits, and a strong shared secret are configured. The production endpoint must be HTTPS.
