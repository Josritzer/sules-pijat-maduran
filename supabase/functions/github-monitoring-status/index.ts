import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_ORIGINS = new Set([
  "https://bookingpijat.com",
  "https://www.bookingpijat.com",
]);

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  if (!ALLOWED_ORIGINS.has(origin)) return { "Vary": "Origin" };
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type, x-supabase-api-version",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return Response.json(body, {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers },
  });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    if (!ALLOWED_ORIGINS.has(req.headers.get("Origin") || "")) {
      return json({ error: "origin_not_allowed" }, 403, cors);
    }
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405, cors);
  const origin = req.headers.get("Origin");
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: "origin_not_allowed" }, 403, cors);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "server_not_configured" }, 503, cors);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const webhookSecret = Deno.env.get("GITHUB_MONITORING_SECRET") || "";
  const suppliedSecret = req.headers.get("x-monitoring-secret") || "";

  // Server-to-server GitHub Actions write. No GitHub token is exposed to the browser.
  if (suppliedSecret) {
    if (!webhookSecret || !constantTimeEqual(suppliedSecret, webhookSecret)) {
      return json({ error: "unauthorized_webhook" }, 401);
    }
    let payload: Record<string, unknown>;
    try {
      payload = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const status = payload.status === "success" || payload.status === "failure" ? payload.status : null;
    const checkedAt = typeof payload.checked_at === "string" ? payload.checked_at : "";
    const checkedDate = new Date(checkedAt);
    const runUrl = typeof payload.workflow_run_url === "string" ? payload.workflow_run_url : "";
    const commitSha = typeof payload.commit_sha === "string" ? payload.commit_sha : "";
    if (!status || !Number.isFinite(checkedDate.getTime())) return json({ error: "invalid_status_payload" }, 400);
    if (runUrl && !/^https:\/\/github\.com\/Josritzer\/sules-pijat-maduran\/actions\/runs\/\d+$/.test(runUrl)) {
      return json({ error: "invalid_workflow_url" }, 400);
    }
    if (commitSha && !/^[a-f0-9]{7,40}$/i.test(commitSha)) return json({ error: "invalid_commit_sha" }, 400);
    const httpStatus = Number.isInteger(payload.http_status) && Number(payload.http_status) >= 100 && Number(payload.http_status) <= 599
      ? Number(payload.http_status) : null;
    const duration = typeof payload.duration_seconds === "number" && Number.isFinite(payload.duration_seconds) && payload.duration_seconds >= 0
      ? Math.min(payload.duration_seconds, 86400) : null;
    const runId = Number.isSafeInteger(payload.workflow_run_id) && Number(payload.workflow_run_id) > 0
      ? Number(payload.workflow_run_id) : null;
    const summary = typeof payload.summary === "string" ? payload.summary.trim().slice(0, 1500) : "";
    const { error } = await admin.from("github_monitoring_status").upsert({
      id: 1,
      status,
      checked_at: checkedDate.toISOString(),
      workflow_run_id: runId,
      workflow_run_url: runUrl || null,
      commit_sha: commitSha || null,
      http_status: httpStatus,
      duration_seconds: duration,
      summary,
      updated_at: new Date().toISOString(),
    }, { onConflict: "id" });
    if (error) {
      console.error("monitoring_status_write_failed", error.message);
      return json({ error: "status_write_failed" }, 500);
    }
    return json({ ok: true });
  }

  // Browser read is permitted only for an authenticated user listed in public.admins.
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401, cors);
  const { data: userData, error: userError } = await admin.auth.getUser(authHeader.slice("Bearer ".length));
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401, cors);
  const { data: adminRow, error: adminError } = await admin.from("admins")
    .select("id").eq("id", userData.user.id).maybeSingle();
  if (adminError || !adminRow) return json({ error: "admin_only" }, 403, cors);

  const { data, error } = await admin.from("github_monitoring_status")
    .select("status,checked_at,workflow_run_id,workflow_run_url,commit_sha,http_status,duration_seconds,summary,updated_at")
    .eq("id", 1).maybeSingle();
  if (error) {
    console.error("monitoring_status_read_failed", error.message);
    return json({ error: "status_read_failed" }, 500, cors);
  }
  return json({ status: data || null }, 200, cors);
});
