import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://bookingpijat.com", "https://www.bookingpijat.com"]);
function corsHeaders(req: Request) {
  const origin = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://bookingpijat.com",
    "Vary": "Origin",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
function json(req: Request, body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...corsHeaders(req), "Cache-Control": "no-store" } });
}
function validUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
function safeCheckoutUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "sandbox.ipaymu.com" && !url.username && !url.password ? url.toString() : null;
  } catch { return null; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) return json(req, { error: "payment_status_not_configured" }, 503);

  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(req, { error: "authentication_required" }, 401);
  const userClient = createClient(supabaseUrl, publicKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return json(req, { error: "invalid_session" }, 401);

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json(req, { error: "invalid_request" }, 400);
    body = parsed as Record<string, unknown>;
  } catch { return json(req, { error: "invalid_json" }, 400); }
  if (Object.keys(body).some(key => key !== "bookingIds") || !Array.isArray(body.bookingIds) ||
      body.bookingIds.length > 50 || body.bookingIds.some(id => !validUuid(id))) {
    return json(req, { error: "invalid_booking_ids" }, 400);
  }
  const bookingIds = [...new Set(body.bookingIds as string[])];
  if (!bookingIds.length) return json(req, { payments: [] });

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: ownedBookings, error: bookingError } = await admin.from("bookings")
    .select("id")
    .eq("customer_id", authData.user.id)
    .in("id", bookingIds);
  if (bookingError) return json(req, { error: "booking_lookup_failed" }, 503);
  const ownedIds = (ownedBookings || []).map(row => row.id);
  if (!ownedIds.length) return json(req, { payments: [] });

  const { data: rows, error: paymentError } = await admin.from("payment_transactions")
    .select("booking_id,status,amount,checkout_url,created_at")
    .eq("customer_id", authData.user.id)
    .in("booking_id", ownedIds)
    .order("created_at", { ascending: false });
  if (paymentError) return json(req, { error: "payment_lookup_failed" }, 503);

  const latest = new Map<string, Record<string, unknown>>();
  for (const row of rows || []) {
    if (!latest.has(row.booking_id)) {
      latest.set(row.booking_id, {
        bookingId: row.booking_id,
        status: row.status,
        amount: Number.isSafeInteger(Number(row.amount)) && Number(row.amount) > 0 ? Number(row.amount) : null,
        checkoutUrl: row.status === "PENDING" ? safeCheckoutUrl(row.checkout_url) : null,
        createdAt: row.created_at,
      });
    }
  }
  return json(req, { payments: Array.from(latest.values()) });
});
