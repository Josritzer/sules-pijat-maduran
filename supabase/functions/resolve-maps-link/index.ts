import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveMapsUrl } from "./resolver.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Metode tidak diizinkan." }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Sesi pelanggan diperlukan." }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!supabaseUrl || !publicKey) return json({ error: "Layanan belum siap. Coba lagi nanti." }, 503);
  const authClient = createClient(supabaseUrl, publicKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "Sesi tidak valid atau telah kedaluwarsa." }, 401);

  let raw = "";
  try { raw = await req.text(); } catch { return json({ error: "Permintaan tidak dapat dibaca." }, 400); }
  if (raw.length > 2048) return json({ error: "Permintaan terlalu besar." }, 413);
  let body: unknown;
  try { body = JSON.parse(raw); } catch { return json({ error: "Format permintaan tidak valid." }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).join(",") !== "url" || typeof (body as { url: unknown }).url !== "string") {
    return json({ error: "Format permintaan tidak valid." }, 400);
  }

  const hasil = await resolveMapsUrl((body as { url: string }).url);
  if (hasil.ok) return json({ lat: hasil.lat, lng: hasil.lng, sumber: hasil.sumber });
  if (hasil.kode === "tidak_didukung") return json({ error: "Tautan ini tidak didukung. Gunakan tautan Google Maps." }, 422);
  if (hasil.kode === "gagal_ambil") return json({ error: "Tautan tidak dapat dibuka sekarang. Coba lagi." }, 502);
  return json({ error: "Koordinat tidak ditemukan pada tautan ini." }, 422);
});
