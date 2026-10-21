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
    if (payload.action === "claim") {
      const { data: pending, error: pendingError } = await admin.from("github_monitoring_run_queue")
        .select("id,requested_at").eq("status", "pending").order("requested_at", { ascending: true }).limit(1).maybeSingle();
      if (pendingError) return json({ error: "queue_read_failed" }, 500);
      if (!pending) return json({ request: null });
      const { data: claimed, error: claimError } = await admin.from("github_monitoring_run_queue")
        .update({ status: "running", started_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", pending.id).eq("status", "pending").select("id,requested_at").maybeSingle();
      if (claimError) return json({ error: "queue_claim_failed" }, 500);
      return json({ request: claimed || null });
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
    if (typeof payload.request_id === "string" && /^[0-9a-f-]{36}$/i.test(payload.request_id)) {
      const { error: queueError } = await admin.from("github_monitoring_run_queue").update({
        status, finished_at: new Date().toISOString(), workflow_run_id: runId,
        workflow_run_url: runUrl || null, result_summary: summary, updated_at: new Date().toISOString()
      }).eq("id", payload.request_id).eq("status", "running");
      if (queueError) console.error("monitoring_queue_finish_failed", queueError.message);
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

  let browserPayload: Record<string, unknown> = {};
  try { browserPayload = await req.json(); } catch { browserPayload = {}; }
  if (browserPayload.action === "enqueue") {
    const { data: queued, error: queueError } = await admin.from("github_monitoring_run_queue")
      .insert({ requested_by: userData.user.id, status: "pending" })
      .select("id,status,requested_at").single();
    if (queueError) {
      console.error("monitoring_queue_enqueue_failed", queueError.message);
      return json({ error: "queue_enqueue_failed" }, 500, cors);
    }

    // Start GitHub Actions immediately when the server-side dispatch secret is configured.
    // The secret never reaches the browser. The periodic worker remains a fallback.
    const dispatchToken = Deno.env.get("GITHUB_ACTIONS_DISPATCH_TOKEN") || "";
    let workerTriggered = false;
    if (dispatchToken) {
      try {
        const response = await fetch("https://api.github.com/repos/Josritzer/sules-pijat-maduran/actions/workflows/monitoring-queue-worker.yml/dispatches", {
          method: "POST",
          headers: {
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + dispatchToken,
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ ref: "main" }),
        });
        workerTriggered = response.status === 204;
        if (!workerTriggered) console.error("monitoring_worker_dispatch_failed", response.status);
      } catch (error) {
        console.error("monitoring_worker_dispatch_error", error instanceof Error ? error.message : "unknown");
      }
    } else {
      console.error("monitoring_worker_dispatch_token_missing");
    }

    return json({ request: queued, worker_triggered: workerTriggered }, 202, cors);
  }
  if (browserPayload.action === "queue_status") {
    const { data: queue, error: queueError } = await admin.from("github_monitoring_run_queue")
      .select("id,status,requested_at,started_at,finished_at,workflow_run_url,result_summary")
      .eq("requested_by", userData.user.id).order("requested_at", { ascending: false }).limit(1).maybeSingle();
    if (queueError) return json({ error: "queue_status_failed" }, 500, cors);
    return json({ request: queue || null }, 200, cors);
  }

  const { data, error } = await admin.from("github_monitoring_status")
    .select("status,checked_at,workflow_run_id,workflow_run_url,commit_sha,http_status,duration_seconds,summary,updated_at")
    .eq("id", 1).maybeSingle();
  if (error) {
    console.error("monitoring_status_read_failed", error.message);
    return json({ error: "status_read_failed" }, 500, cors);
  }
  return json({ status: data || null }, 200, cors);
});
