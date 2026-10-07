import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Metode tidak diizinkan." }, 405);

  const authorization = req.headers.get("Authorization") || "";
  const bearer = authorization.match(/^Bearer\s+(\S+)$/i);
  if (!bearer) return json({ error: "Sesi pelanggan diperlukan untuk menghapus akun." }, 401);
  const token = bearer[1];

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) {
    return json({ error: "Layanan penghapusan akun belum siap. Coba lagi nanti." }, 503);
  }

  let rawBody = "";
  try {
    rawBody = await req.text();
  } catch {
    return json({ error: "Permintaan tidak dapat dibaca." }, 400);
  }
  if (rawBody.length > 1024) return json({ error: "Permintaan terlalu besar." }, 413);

  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return json({ error: "Konfirmasi penghapusan akun tidak valid." }, 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "Konfirmasi penghapusan akun tidak valid." }, 400);
  }
  const confirmation = body as Record<string, unknown>;
  if (Object.keys(confirmation).length !== 1 || confirmation.confirm !== true) {
    return json({ error: "Konfirmasi penghapusan akun tidak valid." }, 400);
  }

  const userClient = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  const userId = userData?.user?.id;
  if (userError || !userId) {
    return json({ error: "Sesi tidak valid atau telah kedaluwarsa. Masuk kembali." }, 401);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: adminRow, error: adminCheckError } = await adminClient
    .from("admins")
    .select("id")
    .eq("id", userId)
    .maybeSingle();
  if (adminCheckError) return json({ error: "Status akun tidak dapat diverifikasi. Coba lagi nanti." }, 503);
  if (adminRow) return json({ error: "Akun Admin tidak dapat dihapus melalui fitur pelanggan." }, 403);

  // Never accept a user ID from the caller. Auth Admin deletion is server-only;
  // the verified bearer session is the sole source of the target user ID.
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(userId, false);
  if (deleteError) {
    console.error("delete-account: authenticated user deletion failed");
    return json({ error: "Akun belum berhasil dihapus. Silakan coba lagi atau hubungi Admin." }, 500);
  }

  return json({ deleted: true });
});
