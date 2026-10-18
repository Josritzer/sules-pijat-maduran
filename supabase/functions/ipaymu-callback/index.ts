import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
function constantTimeEqualHex(a: string, b: string) {
  if (!/^[0-9a-f]{64}$/i.test(a) || !/^[0-9a-f]{64}$/i.test(b)) return false;
  const left = new TextEncoder().encode(a.toLowerCase());
  const right = new TextEncoder().encode(b.toLowerCase());
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}
function normalizeCallback(input: Record<string, unknown>) {
  const normalized: Record<string, unknown> = { ...input };
  delete normalized.signature;
  for (const key of ["trx_id", "status_code", "transaction_status_code", "paid_off"]) {
    if (typeof normalized[key] === "string" && /^-?\d+$/.test(normalized[key] as string)) {
      normalized[key] = Number(normalized[key]);
    }
  }
  if (typeof normalized.is_escrow === "string") {
    const value = (normalized.is_escrow as string).toLowerCase();
    if (value === "true" || value === "1") normalized.is_escrow = true;
    else if (value === "false" || value === "0") normalized.is_escrow = false;
  }
  if (typeof normalized.additional_info === "string") {
    try { normalized.additional_info = JSON.parse(normalized.additional_info as string); }
    catch { /* keep the original value if provider sends a non-JSON string */ }
  }
  if (!("additional_info" in normalized)) normalized.additional_info = [];
  return Object.fromEntries(Object.keys(normalized).sort().map((key) => [key, normalized[key]]));
}
async function hmacSha256Hex(value: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
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
    .select("id,amount,status")
    .eq("id", referenceId)
    .maybeSingle();
  if (paymentError) return json({ error: "payment_lookup_failed" }, 503);
  if (!payment) return json({ status: "ignored" });
  if (Number(payment.amount) !== callbackAmount) return json({ error: "amount_mismatch" }, 409);
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
