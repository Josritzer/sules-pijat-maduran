import express from "express";
import crypto from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const app = express();
app.disable("x-powered-by");
app.set("trust proxy", 1);
app.use(express.json({ limit: "32kb", type: ["application/json", "application/*+json"] }));
app.use(express.urlencoded({ extended: false, limit: "32kb" }));

const PORT = Number(process.env.PORT || 8080);
const ENVIRONMENT = (process.env.IPAYMU_ENV || "sandbox").toLowerCase();
const SITE_URL = (process.env.PUBLIC_SITE_URL || "https://www.bookingpijat.com").replace(/\/$/, "");
const API_PUBLIC_URL = (process.env.PAYMENT_API_PUBLIC_URL || "").replace(/\/$/, "");
const ALLOWED_ORIGINS = new Set(
  (process.env.ALLOWED_ORIGINS || "https://bookingpijat.com,https://www.bookingpijat.com")
    .split(",").map((value) => value.trim()).filter(Boolean)
);
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const IPAYMU_VA = process.env.IPAYMU_VA || "";
const IPAYMU_API_KEY = process.env.IPAYMU_API_KEY || "";
const IPAYMU_BASE_URL = process.env.IPAYMU_BASE_URL ||
  (ENVIRONMENT === "production" ? "https://my.ipaymu.com/api/v2" : "https://sandbox.ipaymu.com/api/v2");

const supabaseAdmin = SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
  : null;

function send(res, status, body) {
  res.set("Cache-Control", "no-store");
  return res.status(status).json(body);
}

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Vary", "Origin");
    res.set("Access-Control-Allow-Headers", "authorization, content-type");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  }
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

function configured() {
  return Boolean(supabaseAdmin && SUPABASE_ANON_KEY && IPAYMU_VA && IPAYMU_API_KEY &&
    API_PUBLIC_URL && (ENVIRONMENT === "sandbox" || ENVIRONMENT === "production"));
}

function getBearerToken(req) {
  const value = req.headers.authorization || "";
  const match = value.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

async function authenticateCustomer(req) {
  const token = getBearerToken(req);
  if (!token || !SUPABASE_URL || !SUPABASE_ANON_KEY) return null;
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data?.user) return null;
  return data.user;
}

function timestamp14() {
  const d = new Date();
  return d.getUTCFullYear().toString() +
    String(d.getUTCMonth() + 1).padStart(2, "0") +
    String(d.getUTCDate()).padStart(2, "0") +
    String(d.getUTCHours()).padStart(2, "0") +
    String(d.getUTCMinutes()).padStart(2, "0") +
    String(d.getUTCSeconds()).padStart(2, "0");
}

function requestSignature(method, va, apiKey, bodyText) {
  const bodyHash = crypto.createHash("sha256").update(bodyText).digest("hex").toLowerCase();
  const stringToSign = `${method}:${va}:${bodyHash}:${apiKey}`;
  return crypto.createHmac("sha256", apiKey).update(stringToSign).digest("hex");
}

function safeEqualHex(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || !/^[a-f0-9]{64}$/i.test(a) || !/^[a-f0-9]{64}$/i.test(b)) return false;
  const left = Buffer.from(a, "hex");
  const right = Buffer.from(b, "hex");
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function normalizeCallback(raw) {
  const result = {};
  for (const key of Object.keys(raw || {})) {
    let value = raw[key];
    if (key === "is_escrow") {
      result[key] = value === true || value === "true" || value === "1" || value === 1;
    } else if (["trx_id", "status_code", "transaction_status_code", "paid_off"].includes(key)) {
      const parsed = Number.parseInt(String(value), 10);
      if (!Number.isFinite(parsed)) throw new Error("invalid_callback_number");
      result[key] = parsed;
    } else if (key === "additional_info") {
      if (value === "[]") result[key] = [];
      else if (typeof value === "string") {
        try { result[key] = JSON.parse(value); } catch { result[key] = value; }
      } else result[key] = value;
    } else {
      result[key] = value === null ? null : String(value);
    }
  }
  if (!Object.hasOwn(result, "additional_info")) result.additional_info = [];
  return Object.keys(result).sort((a, b) => a.localeCompare(b))
    .reduce((sorted, key) => { sorted[key] = result[key]; return sorted; }, {});
}

function callbackSignature(payload) {
  const normalized = { ...payload };
  delete normalized.signature;
  let jsonBody = JSON.stringify(normalized);
  jsonBody = jsonBody.replace(/\//g, "\\/");
  return crypto.createHmac("sha256", IPAYMU_VA).update(jsonBody).digest("hex");
}

function rupiah(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 && Number.isSafeInteger(number) ? number : null;
}

app.get("/health", (_req, res) => send(res, 200, { ok: true, service: "sl-relax-ipaymu" }));

app.post("/api/payments", async (req, res) => {
  if (!configured()) return send(res, 503, { error: "Layanan pembayaran belum dikonfigurasi." });
  const user = await authenticateCustomer(req);
  if (!user) return send(res, 401, { error: "Sesi pelanggan tidak valid. Silakan masuk kembali." });
  const bookingId = typeof req.body?.bookingId === "string" ? req.body.bookingId : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(bookingId)) {
    return send(res, 400, { error: "ID booking tidak valid." });
  }

  const { data: booking, error: bookingError } = await supabaseAdmin
    .from("bookings")
    .select("id,customer_id,status,grand_total,final_total,service_id,tanggal,jam_mulai,nama_pelanggan,wa_pelanggan")
    .eq("id", bookingId)
    .eq("customer_id", user.id)
    .maybeSingle();
  if (bookingError) return send(res, 503, { error: "Data booking belum dapat diperiksa." });
  if (!booking) return send(res, 404, { error: "Booking tidak ditemukan pada akun ini." });
  if (booking.status !== "DITERIMA") return send(res, 409, { error: "Pembayaran online tersedia setelah Admin menerima booking." });
  const amount = rupiah(booking.grand_total ?? booking.final_total);
  if (!amount) return send(res, 409, { error: "Total booking belum valid untuk pembayaran online." });

  const { data: existing, error: existingError } = await supabaseAdmin
    .from("payments").select("id,reference_id,checkout_url,status,created_at,amount")
    .eq("booking_id", bookingId).in("status", ["INITIATING", "PENDING"])
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (existingError) return send(res, 503, { error: "Status pembayaran belum dapat diperiksa." });
  if (existing?.status === "PENDING" && existing.checkout_url) {
    return send(res, 200, { status: existing.status, amount: Number(existing.amount), checkoutUrl: existing.checkout_url });
  }
  if (existing?.status === "INITIATING") {
    const createdAt = Date.parse(existing.created_at || "");
    if (Number.isFinite(createdAt) && Date.now() - createdAt < 10 * 60 * 1000) {
      return send(res, 409, { error: "Permintaan pembayaran sedang diproses. Tunggu sebentar lalu coba lagi." });
    }
    await supabaseAdmin.from("payments").update({ status: "FAILED", updated_at: new Date().toISOString() }).eq("id", existing.id);
  }

  const referenceId = `SLR-${crypto.randomUUID().replace(/-/g, "").slice(0, 24).toUpperCase()}`;
  const { data: payment, error: insertError } = await supabaseAdmin.from("payments").insert({
    booking_id: booking.id,
    customer_id: user.id,
    provider: "ipaymu",
    environment: ENVIRONMENT,
    reference_id: referenceId,
    amount,
    status: "INITIATING",
  }).select("id").single();
  if (insertError || !payment) return send(res, 503, { error: "Catatan pembayaran belum dapat dibuat." });

  const dateTime = `${booking.tanggal} ${String(booking.jam_mulai || "").slice(0, 5)}`;
  const productName = `SL Relax - Pijat ${booking.service_id === "120m" ? "2 Jam" : "90 Menit"}`;
  const body = {
    product: [productName],
    qty: ["1"],
    price: [String(amount)],
    description: [`Booking ${booking.id} - ${dateTime}`],
    returnUrl: `${SITE_URL}/?payment=return&booking_id=${encodeURIComponent(booking.id)}`,
    notifyUrl: `${API_PUBLIC_URL}/ipaymu/callback`,
    cancelUrl: `${SITE_URL}/?payment=cancel&booking_id=${encodeURIComponent(booking.id)}`,
    referenceId,
    buyerName: typeof booking.nama_pelanggan === "string" ? booking.nama_pelanggan.slice(0, 100) : undefined,
    buyerPhone: typeof booking.wa_pelanggan === "string" ? booking.wa_pelanggan.slice(0, 40) : undefined,
  };
  const bodyText = JSON.stringify(body);
  let providerResponse;
  try {
    const response = await fetch(`${IPAYMU_BASE_URL.replace(/\/$/, "")}/payment`, {
      method: "POST",
      signal: AbortSignal.timeout(15000),
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        va: IPAYMU_VA,
        signature: requestSignature("POST", IPAYMU_VA, IPAYMU_API_KEY, bodyText),
        timestamp: timestamp14(),
      },
      body: bodyText,
    });
    providerResponse = await response.json();
    if (!response.ok || providerResponse?.Success === false || !providerResponse?.Data?.Url) {
      await supabaseAdmin.from("payments").update({ status: "FAILED", updated_at: new Date().toISOString() }).eq("id", payment.id);
      return send(res, 502, { error: "iPaymu belum dapat membuat halaman pembayaran. Coba lagi nanti." });
    }
  } catch {
    await supabaseAdmin.from("payments").update({ status: "FAILED", updated_at: new Date().toISOString() }).eq("id", payment.id);
    return send(res, 502, { error: "iPaymu tidak dapat dihubungi. Coba lagi nanti." });
  }

  const checkoutUrl = String(providerResponse.Data.Url);
  let checkoutHost;
  try { checkoutHost = new URL(checkoutUrl).hostname; } catch { checkoutHost = ""; }
  if (!checkoutUrl.startsWith("https://") || !(checkoutHost === "ipaymu.com" || checkoutHost.endsWith(".ipaymu.com"))) {
    await supabaseAdmin.from("payments").update({ status: "FAILED", updated_at: new Date().toISOString() }).eq("id", payment.id);
    return send(res, 502, { error: "Alamat checkout iPaymu tidak valid." });
  }
  const sessionId = typeof providerResponse.Data.SessionID === "string" ? providerResponse.Data.SessionID : null;
  const { error: updateError } = await supabaseAdmin.from("payments").update({
    status: "PENDING",
    provider_session_id: sessionId,
    checkout_url: checkoutUrl,
    updated_at: new Date().toISOString(),
  }).eq("id", payment.id).neq("status", "PAID");
  if (updateError) return send(res, 503, { error: "Pembayaran dibuat tetapi belum dapat disimpan. Hubungi Admin sebelum mencoba ulang." });
  // A fast callback may mark the payment PAID before the checkout response is saved.
  const { data: savedPayment, error: savedPaymentError } = await supabaseAdmin.from("payments")
    .select("status").eq("id", payment.id).maybeSingle();
  if (savedPaymentError || !savedPayment) return send(res, 503, { error: "Status pembayaran belum dapat dipastikan. Periksa Pesanan sebelum mencoba lagi." });
  return send(res, 200, { status: savedPayment.status, amount, checkoutUrl });
});

app.get("/api/payments/:bookingId", async (req, res) => {
  if (!configured()) return send(res, 503, { error: "Layanan pembayaran belum dikonfigurasi." });
  const user = await authenticateCustomer(req);
  if (!user) return send(res, 401, { error: "Sesi pelanggan tidak valid. Silakan masuk kembali." });
  const bookingId = req.params.bookingId;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(bookingId)) {
    return send(res, 400, { error: "ID booking tidak valid." });
  }
  const { data, error } = await supabaseAdmin.from("payments")
    .select("status,amount,checkout_url,updated_at,paid_at")
    .eq("booking_id", bookingId).eq("customer_id", user.id)
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (error) return send(res, 503, { error: "Status pembayaran belum dapat diperiksa." });
  if (!data) return send(res, 200, { payment: null });
  return send(res, 200, { payment: {
    status: data.status,
    amount: Number(data.amount),
    checkoutUrl: data.checkout_url,
    updatedAt: data.updated_at,
    paidAt: data.paid_at,
  } });
});

app.post("/ipaymu/callback", async (req, res) => {
  if (!supabaseAdmin || !IPAYMU_VA) return send(res, 503, { error: "Callback belum dikonfigurasi." });
  const receivedSignature = req.get("X-Signature") || "";
  let payload;
  try { payload = normalizeCallback(req.body || {}); } catch { return send(res, 400, { error: "Invalid callback." }); }
  const expectedSignature = callbackSignature(payload);
  if (!safeEqualHex(receivedSignature, expectedSignature)) return send(res, 400, { error: "Invalid signature." });

  const referenceId = String(payload.referenceId || payload.reference_id || "");
  if (!referenceId || (payload.merchant && String(payload.merchant) !== IPAYMU_VA)) {
    return send(res, 400, { error: "Invalid payment reference." });
  }
  const { data: payment, error } = await supabaseAdmin.from("payments")
    .select("id,booking_id,amount,status").eq("reference_id", referenceId).maybeSingle();
  if (error) return send(res, 503, { error: "Payment record unavailable." });
  if (!payment) return send(res, 200, { status: "ignored" });
  if (payment.status === "PAID") return send(res, 200, { status: "already_processed" });

  const callbackAmountRaw = payload.sub_total ?? payload.amount ?? payload.total;
  const callbackAmount = Number(callbackAmountRaw);
  if (callbackAmountRaw === undefined || callbackAmountRaw === null || callbackAmountRaw === "" ||
      !Number.isFinite(callbackAmount) || Math.round(callbackAmount) !== Math.round(Number(payment.amount))) {
    return send(res, 400, { error: "Payment amount mismatch." });
  }
  const statusText = String(payload.status || "").toLowerCase();
  const statusCode = Number(payload.status_code);
  let nextStatus = "PENDING";
  if (statusCode === 1 && statusText === "berhasil") nextStatus = "PAID";
  else if (statusCode === -2 || statusText === "expired") nextStatus = "EXPIRED";
  else if (statusText === "gagal" || statusText === "failed") nextStatus = "FAILED";

  const update = {
    status: nextStatus,
    provider_transaction_id: payload.trx_id == null ? null : String(payload.trx_id),
    provider_status_code: Number.isFinite(statusCode) ? statusCode : null,
    last_callback_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    ...(nextStatus === "PAID" ? { paid_at: Number.isFinite(Date.parse(String(payload.paid_at || ""))) ? new Date(String(payload.paid_at)).toISOString() : new Date().toISOString() } : {}),
  };
  const { error: updateError } = await supabaseAdmin.from("payments").update(update)
    .eq("id", payment.id).neq("status", "PAID");
  if (updateError) return send(res, 503, { error: "Payment status update failed." });
  return send(res, 200, { status: "OK" });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`SL Relax iPaymu API listening on port ${PORT}; environment=${ENVIRONMENT}`);
});
