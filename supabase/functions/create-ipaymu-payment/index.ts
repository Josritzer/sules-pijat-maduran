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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const proxyUrl = Deno.env.get("IPAYMU_PROXY_URL");
  const proxySecret = Deno.env.get("IPAYMU_PROXY_SECRET");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !proxyUrl || !proxySecret) {
    return json(req, { error: "payment_service_not_configured" }, 503);
  }

  const bearer = req.headers.get("Authorization") ?? "";
  const token = bearer.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(req, { error: "authentication_required" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return json(req, { error: "invalid_session" }, 401);

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json(req, { error: "invalid_request" }, 400);
    body = parsed as Record<string, unknown>;
  } catch {
    return json(req, { error: "invalid_json" }, 400);
  }
  const bookingId = typeof body.bookingId === "string" ? body.bookingId : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(bookingId)) {
    return json(req, { error: "invalid_booking_id" }, 400);
  }
  if (Object.keys(body).some((key) => key !== "bookingId")) return json(req, { error: "unexpected_fields" }, 400);

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: booking, error: bookingError } = await admin.from("bookings")
    .select("id,customer_id,status,service_id,jumlah_orang,package_key,final_total,grand_total,nama_pelanggan,wa_pelanggan")
    .eq("id", bookingId)
    .eq("customer_id", authData.user.id)
    .maybeSingle();
  if (bookingError) return json(req, { error: "booking_lookup_failed" }, 503);
  if (!booking) return json(req, { error: "booking_not_found" }, 404);
  if (booking.status !== "DITERIMA") return json(req, { error: "booking_not_accepted_for_payment" }, 409);

  const amount = Number(booking.final_total ?? booking.grand_total);
  if (!Number.isSafeInteger(amount) || amount <= 0) return json(req, { error: "booking_amount_invalid" }, 409);

  const { data: existing, error: existingError } = await admin.from("payment_transactions")
    .select("id,amount,status,checkout_url,ipaymu_session_id")
    .eq("booking_id", booking.id)
    .eq("status", "PENDING")
    .maybeSingle();
  if (existingError) return json(req, { error: "payment_lookup_failed" }, 503);
  if (existing?.checkout_url && Number(existing.amount) === amount) {
    return json(req, { paymentId: existing.id, checkoutUrl: existing.checkout_url, status: existing.status });
  }

  let payment = existing;
  if (!payment) {
    const { data: inserted, error: insertError } = await admin.from("payment_transactions")
      .insert({ booking_id: booking.id, customer_id: authData.user.id, amount, status: "PENDING" })
      .select("id,amount,status,checkout_url,ipaymu_session_id")
      .single();
    if (insertError) {
      // A concurrent request may have created the pending payment first.
      const { data: concurrent } = await admin.from("payment_transactions")
        .select("id,amount,status,checkout_url,ipaymu_session_id")
        .eq("booking_id", booking.id).eq("status", "PENDING").maybeSingle();
      if (concurrent?.checkout_url && Number(concurrent.amount) === amount) {
        return json(req, { paymentId: concurrent.id, checkoutUrl: concurrent.checkout_url, status: concurrent.status });
      }
      return json(req, { error: "payment_create_failed" }, 409);
    }
    payment = inserted;
  }
  if (!payment) {
    return json(req, { error: "payment_create_failed" }, 409);
  }

  const productName = booking.package_key || (booking.service_id === "120m" ? "Pijat 2 Jam" : "Pijat 90 Menit");
  let proxyResponse: Response;
  try {
    proxyResponse = await fetch(proxyUrl.replace(/\/+$/, "") + "/v1/redirect-payment", {
      method: "POST",
      signal: AbortSignal.timeout(20000),
      headers: { "content-type": "application/json", Authorization: `Bearer ${proxySecret}` },
      body: JSON.stringify({
        referenceId: payment.id,
        amount,
        productName,
        description: `SL Relax booking ${booking.id}`,
      }),
    });
  } catch {
    return json(req, { error: "payment_proxy_unreachable" }, 502);
  }
  if (!proxyResponse.ok) return json(req, { error: "payment_session_failed" }, 502);
  let session: Record<string, unknown>;
  try { session = await proxyResponse.json(); } catch { return json(req, { error: "payment_proxy_invalid_response" }, 502); }
  if (typeof session.sessionId !== "string" || typeof session.checkoutUrl !== "string" ||
      !session.checkoutUrl.startsWith("https://sandbox.ipaymu.com/")) {
    return json(req, { error: "payment_session_invalid" }, 502);
  }

  const { error: updateError } = await admin.from("payment_transactions")
    .update({ ipaymu_session_id: session.sessionId, checkout_url: session.checkoutUrl, updated_at: new Date().toISOString() })
    .eq("id", payment.id).eq("status", "PENDING");
  if (updateError) return json(req, { error: "payment_session_persist_failed" }, 503);

  return json(req, { paymentId: payment.id, checkoutUrl: session.checkoutUrl, status: "PENDING" });
});
