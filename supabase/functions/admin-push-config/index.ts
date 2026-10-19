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

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    if (!ALLOWED_ORIGINS.has(req.headers.get("Origin") || "")) {
      return json({ error: "origin_not_allowed" }, 403, cors);
    }
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405, cors);
  if (!ALLOWED_ORIGINS.has(req.headers.get("Origin") || "")) {
    return json({ error: "origin_not_allowed" }, 403, cors);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = req.headers.get("Authorization") || "";
  if (!url || !serviceKey || !authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401, cors);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401, cors);

  const { data: adminRow, error: adminError } = await admin.from("admins")
    .select("id").eq("id", userData.user.id).maybeSingle();
  if (adminError || !adminRow) return json({ error: "admin_only" }, 403, cors);

  try {
    const { data, error } = await admin.rpc("get_secret", { secret_name: "web_push_vapid_public_key" });
    if (error || typeof data !== "string" || !data) return json({ error: "push_not_configured" }, 503, cors);
    return json({ publicKey: data }, 200, cors);
  } catch {
    return json({ error: "push_not_configured" }, 503, cors);
  }
});
