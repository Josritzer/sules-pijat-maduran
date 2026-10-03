import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SERVICE_LABEL: Record<string, string> = { "90m": "Pijat 90 Menit", "120m": "Pijat 2 Jam" };

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

function constantTimeEqual(a: string, b: string) {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[ch] ?? ch);
}

function formatRupiah(value: unknown) {
  const amount = Number(value);
  return "Rp" + (Number.isFinite(amount) ? Math.round(amount) : 0).toLocaleString("id-ID");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Metode tidak diizinkan." }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "Layanan notifikasi belum siap." }, 503);

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  let expectedSecret: string | null = null;
  try {
    const { data, error } = await supabaseAdmin.rpc("get_secret", { secret_name: "notify_booking_webhook_secret" });
    if (!error && typeof data === "string") expectedSecret = data;
  } catch { /* never log secret or provider response */ }
  const receivedSecret = req.headers.get("x-webhook-secret") ?? "";
  if (!expectedSecret || !receivedSecret || !constantTimeEqual(receivedSecret, expectedSecret)) {
    return json({ error: "unauthorized" }, 401);
  }

  let rawBody = "";
  try { rawBody = await req.text(); } catch { return json({ error: "invalid_request" }, 400); }
  if (rawBody.length > 16384) return json({ error: "invalid_request" }, 413);
  let payload: Record<string, unknown>;
  try {
    const parsed = JSON.parse(rawBody);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json({ error: "invalid_request" }, 400);
    payload = parsed as Record<string, unknown>;
  } catch { return json({ error: "invalid_request" }, 400); }

  const requiredStrings = ["nama", "wa", "service_id", "tanggal", "jam_mulai", "tipe_lokasi"];
  if (requiredStrings.some(key => typeof payload[key] !== "string" || !(payload[key] as string).trim())) return json({ error: "invalid_payload" }, 400);
  if (!Number.isInteger(payload.jumlah_orang) || ![1, 2].includes(payload.jumlah_orang as number)) return json({ error: "invalid_payload" }, 400);
  if (payload.tipe_lokasi !== "HOME_SERVICE" && payload.tipe_lokasi !== "DI_TEMPAT") return json({ error: "invalid_payload" }, 400);

  const { data: adminRows, error: adminRowsError } = await supabaseAdmin.from("admins").select("id").limit(20);
  if (adminRowsError || !Array.isArray(adminRows) || adminRows.length === 0) return json({ error: "notification_unavailable" }, 503);
  const users = await Promise.all(adminRows.map(async (row: { id: string }) => {
    const { data, error } = await supabaseAdmin.auth.admin.getUserById(row.id);
    if (error || !data.user?.email) return null;
    return data.user.email;
  }));
  const recipients = [...new Set(users.filter((email): email is string => typeof email === "string" && email.length <= 320))];
  if (recipients.length === 0) return json({ error: "notification_unavailable" }, 503);

  let resendKey: string | null = null;
  try {
    const { data, error } = await supabaseAdmin.rpc("get_secret", { secret_name: "resend_api_key" });
    if (!error && typeof data === "string") resendKey = data;
  } catch { /* no secret output in logs */ }
  if (!resendKey) return json({ error: "notification_unavailable" }, 503);

  const name = escapeHtml(payload.nama);
  const wa = escapeHtml(payload.wa);
  const service = escapeHtml(SERVICE_LABEL[String(payload.service_id)] ?? payload.service_id);
  const date = escapeHtml(payload.tanggal);
  const time = escapeHtml(payload.jam_mulai);
  const location = payload.tipe_lokasi === "HOME_SERVICE" ? "ke Rumah" : "Di Sules";
  const address = payload.alamat ? `<p><b>Alamat/koordinat:</b> ${escapeHtml(payload.alamat)}</p>` : "";
  const guests = escapeHtml(payload.jumlah_orang);
  const html = `
    <h2>Booking Baru — Sules Pijat Maduran</h2>
    <p><b>Nama:</b> ${name}</p>
    <p><b>No. WhatsApp:</b> ${wa}</p>
    <p><b>Layanan:</b> ${service} × ${guests} orang</p>
    <p><b>Tanggal:</b> ${date}</p>
    <p><b>Jam:</b> ${time}</p>
    <p><b>Lokasi:</b> ${location}</p>
    ${address}
    <p><b>Travel fee:</b> ${formatRupiah(payload.travel_fee)}</p>
    <p><b>Harga layanan:</b> ${formatRupiah(payload.service_price)}</p>
    <p><b>Total:</b> ${formatRupiah(payload.grand_total)}</p>
    <p>Status: <b>MENUNGGU</b> — periksa jadwal di Dashboard Admin.</p>
  `;
  const subject = `Booking baru: ${String(payload.nama).slice(0, 80)} — ${date} ${time}`;
  try {
    const responses = await Promise.all(recipients.map(to => fetch("https://api.resend.com/emails", {
      method: "POST",
      signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: "Sules Booking <onboarding@resend.dev>", to: [to], subject, html }),
    })));
    if (responses.some(response => !response.ok)) {
      console.error("Booking notification provider returned a non-success status.");
      return json({ error: "notification_failed" }, 502);
    }
    return json({ ok: true });
  } catch {
    console.error("Booking notification delivery failed.");
    return json({ error: "notification_failed" }, 502);
  }
});
