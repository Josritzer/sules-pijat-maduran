import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { constantTimeEqualHex, normalizeCallback, hmacSha256Hex } from "./callback-utils.ts";

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
async function parsePayload(req: Request): Promise<Record<string, unknown> | null> {
  const raw = await req.text();
  if (raw.length > 32 * 1024) return null;
  const type = (req.headers.get("content-type") || "").toLowerCase();
  try {
    if (type.includes("application/json")) {
      const value = JSON.parse(raw);
      return value && typeof value === "object" && !Array.isArray(value) ? value : null;
    }
    const params = new URLSearchParams(raw);
    const value: Record<string, unknown> = {};
    for (const [key, entry] of params.entries()) value[key] = entry;
    return Object.keys(value).length ? value : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const merchantVa = Deno.env.get("IPAYMU_VA");
  if (!supabaseUrl || !serviceRoleKey || !merchantVa) return json({ error: "callback_not_configured" }, 503);

  const payload = await parsePayload(req);
  const receivedSignature = req.headers.get("x-signature") || "";
  if (!payload || !receivedSignature) return json({ error: "invalid_callback" }, 400);

  const normalized = normalizeCallback(payload);
  const canonicalBody = JSON.stringify(normalized).replace(/\//g, "\\/");
  const expectedSignature = await hmacSha256Hex(canonicalBody, merchantVa);
  if (!constantTimeEqualHex(receivedSignature, expectedSignature)) return json({ error: "invalid_signature" }, 401);

  const referenceId = typeof payload.reference_id === "string" ? payload.reference_id : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(referenceId)) {
    return json({ status: "ignored" });
  }

  const statusCode = Number(payload.status_code);
  const statusText = typeof payload.status === "string" ? payload.status.toLowerCase() : "";
  if (statusCode !== 1 || statusText !== "berhasil") {
    // A valid but non-success callback must never mark a payment as paid.
    return json({ status: "acknowledged" });
  }

  const callbackAmountValue = payload.amount ?? payload.total;
  const callbackAmount = typeof callbackAmountValue === "string" || typeof callbackAmountValue === "number"
    ? Number(callbackAmountValue)
    : NaN;
  if (!Number.isFinite(callbackAmount) || callbackAmount <= 0) return json({ error: "callback_amount_missing" }, 400);

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: payment, error: paymentError } = await admin.from("payment_transactions")
    .select("id,amount,status,ipaymu_session_id")
    .eq("id", referenceId)
    .maybeSingle();
  if (paymentError) return json({ error: "payment_lookup_failed" }, 503);
  if (!payment) return json({ status: "ignored" });
  if (Number(payment.amount) !== callbackAmount) return json({ status: "acknowledged_amount_mismatch" });
  const callbackSessionId = typeof payload.sid === "string" ? payload.sid : "";
  if (!callbackSessionId || callbackSessionId !== payment.ipaymu_session_id) return json({ status: "acknowledged_session_mismatch" });
  if (payment.status === "PAID") return json({ status: "already_processed" });
  if (payment.status !== "PENDING") return json({ status: "not_pending" });

  const transactionId = payload.trx_id === undefined || payload.trx_id === null ? null : String(payload.trx_id);
  const { data: updated, error: updateError } = await admin.from("payment_transactions")
    .update({
      status: "PAID",
      ipaymu_transaction_id: transactionId,
      callback_signature_valid: true,
      last_callback_at: new Date().toISOString(),
      paid_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    })
    .eq("id", referenceId)
    .eq("status", "PENDING")
    .select("id")
    .maybeSingle();
  if (updateError) return json({ error: "payment_update_failed" }, 503);
  if (!updated) return json({ status: "already_processed" });
  return json({ status: "ok" });
});
