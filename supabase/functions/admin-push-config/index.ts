import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = req.headers.get("Authorization") || "";
  if (!url || !serviceKey || !authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401);

  const { data: adminRow, error: adminError } = await admin.from("admins")
    .select("id").eq("id", userData.user.id).maybeSingle();
  if (adminError || !adminRow) return json({ error: "admin_only" }, 403);

  try {
    const { data, error } = await admin.rpc("get_secret", { secret_name: "web_push_vapid_public_key" });
    if (error || typeof data !== "string" || !data) return json({ error: "push_not_configured" }, 503);
    return json({ publicKey: data });
  } catch {
    return json({ error: "push_not_configured" }, 503);
  }
});
