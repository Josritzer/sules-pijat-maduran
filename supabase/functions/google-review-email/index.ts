import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const REVIEW_URL = "https://g.page/r/CWXCZycYzhXqEBE/review";
const MAX_ATTEMPTS = 3;

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, ch => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[ch] ?? ch);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "service_unavailable" }, 503);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let expectedSecret: string | null = null;
  try {
    const { data, error } = await admin.rpc("get_secret", {
      secret_name: "notify_booking_webhook_secret",
    });
    if (!error && typeof data === "string") expectedSecret = data;
  } catch {
    // Never log secrets.
  }

  const suppliedSecret = req.headers.get("x-webhook-secret") ?? "";
  if (!expectedSecret || !suppliedSecret || suppliedSecret !== expectedSecret) {
    return json({ error: "unauthorized" }, 401);
  }

  let limit = 20;
  try {
    const raw = await req.text();
    if (raw.length > 2048) return json({ error: "invalid_request" }, 413);
    if (raw.trim()) {
      const parsed = JSON.parse(raw);
      if (parsed && Number.isInteger(parsed.limit)) limit = Math.min(Math.max(parsed.limit, 1), 50);
    }
  } catch {
    return json({ error: "invalid_request" }, 400);
  }

  let resendKey: string | null = null;
  try {
    const { data, error } = await admin.rpc("get_secret", { secret_name: "resend_api_key" });
    if (!error && typeof data === "string") resendKey = data;
  } catch {
    // Never log secrets.
  }
  if (!resendKey) return json({ error: "email_provider_unavailable" }, 503);

  const { data: jobs, error: claimError } = await admin.rpc("claim_google_review_emails", {
    p_limit: limit,
  });
  if (claimError) {
    console.error("Google review queue claim failed.");
    return json({ error: "queue_unavailable" }, 503);
  }

  let sent = 0;
  let skipped = 0;
  let retried = 0;
  for (const job of (Array.isArray(jobs) ? jobs : [])) {
    const bookingId = String(job.booking_id ?? "");
    try {
      const { data: booking, error: bookingError } = await admin
        .from("bookings").select("status").eq("id", bookingId).maybeSingle();

      if (bookingError) throw new Error("booking_lookup_failed");
      if (!booking || booking.status !== "SELESAI") {
        await admin.from("google_review_email_queue").update({
          status: "cancelled", locked_at: null, last_error: "booking_not_completed",
          updated_at: new Date().toISOString(),
        }).eq("booking_id", bookingId).eq("status", "processing");
        skipped++;
        continue;
      }

      const { data: userResult, error: userError } = await admin.auth.admin.getUserById(String(job.customer_id));
      const email = userResult?.user?.email;
      if (userError || typeof email !== "string" || !email.trim()) {
        await admin.from("google_review_email_queue").update({
          status: "failed", locked_at: null, last_error: "customer_email_unavailable",
          updated_at: new Date().toISOString(),
        }).eq("booking_id", bookingId).eq("status", "processing");
        skipped++;
        continue;
      }

      const name = escapeHtml(job.customer_name || "Kak");
      const html = `<!doctype html>
<html lang="id"><body style="margin:0;padding:24px;background:#f4f7fb;font-family:Arial,sans-serif;color:#1d2d45">
  <main style="max-width:560px;margin:0 auto;background:#fff;border:1px solid #e5eaf3;border-radius:16px;padding:28px">
    <p style="font-size:12px;letter-spacing:1.5px;color:#526bd8;font-weight:700">SL RELAX · SULES PIJAT MADURAN</p>
    <h1 style="font-size:24px;line-height:1.35">Terima kasih telah memilih SL Relax 💙</h1>
    <p>Halo ${name},</p>
    <p>Terima kasih telah mempercayakan kebutuhan pijat Kakak kepada <strong>SL Relax — SULES PIJAT MADURAN</strong>.</p>
    <p>Kami berharap layanan kami memberikan kenyamanan dan membantu Kakak merasa lebih rileks.</p>
    <p>Jika Kakak berkenan, kami mengundang Kakak untuk berbagi pengalaman melalui ulasan Google. Ulasan Kakak sangat berarti bagi kami dan membantu orang lain mengenal SL Relax.</p>
    <p style="margin:28px 0;text-align:center"><a href="${REVIEW_URL}" style="display:inline-block;background:#3157c8;color:#fff;text-decoration:none;font-weight:700;padding:14px 22px;border-radius:10px">⭐ Berikan Ulasan Google</a></p>
    <p>Terima kasih atas dukungan dan kepercayaan Kakak. Semoga Kakak selalu sehat, nyaman, dan bahagia.</p>
    <p>Salam hangat,<br><strong>Tim SL Relax</strong><br>SULES PIJAT MADURAN</p>
    <p style="font-size:12px;color:#6b778b"><a href="https://bookingpijat.com" style="color:#526bd8">bookingpijat.com</a></p>
  </main>
</body></html>`;
      const text = `Halo ${String(job.customer_name || "Kak")},

Terima kasih telah mempercayakan kebutuhan pijat Kakak kepada SL Relax — SULES PIJAT MADURAN.

Kami berharap layanan kami memberikan kenyamanan dan membantu Kakak merasa lebih rileks.

Jika Kakak berkenan, kami mengundang Kakak untuk berbagi pengalaman melalui ulasan Google. Ulasan Kakak sangat berarti bagi kami dan membantu orang lain mengenal SL Relax.

Berikan Ulasan Google: ${REVIEW_URL}

Terima kasih atas dukungan dan kepercayaan Kakak. Semoga Kakak selalu sehat, nyaman, dan bahagia.

Salam hangat,
Tim SL Relax
SULES PIJAT MADURAN
https://bookingpijat.com`;

      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        signal: AbortSignal.timeout(15000),
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": `google-review-${bookingId}`,
        },
        body: JSON.stringify({
          from: "SL Relax <SL-RELAX@bookingpijat.com>",
          to: [email],
          subject: "Terima Kasih Telah Memilih SL Relax 💙",
          html,
          text,
        }),
      });

      if (!response.ok) throw new Error(`resend_http_${response.status}`);

      const { error: updateError } = await admin.from("google_review_email_queue").update({
        status: "sent", sent_at: new Date().toISOString(), locked_at: null,
        last_error: null, updated_at: new Date().toISOString(),
      }).eq("booking_id", bookingId).eq("status", "processing");
      if (updateError) throw new Error("queue_update_failed");
      sent++;
    } catch (error) {
      const attempts = Number(job.attempts || 1);
      const canRetry = attempts < MAX_ATTEMPTS;
      await admin.from("google_review_email_queue").update({
        status: canRetry ? "pending" : "failed",
        scheduled_at: canRetry ? new Date(Date.now() + 5 * 60 * 1000).toISOString() : undefined,
        locked_at: null,
        last_error: error instanceof Error ? error.message.slice(0, 160) : "delivery_failed",
        updated_at: new Date().toISOString(),
      }).eq("booking_id", bookingId).eq("status", "processing");
      if (canRetry) retried++;
      console.error("Google review email job failed.", { bookingId, attempts, canRetry });
    }
  }

  return json({ ok: true, processed: Array.isArray(jobs) ? jobs.length : 0, sent, skipped, retried });
});
