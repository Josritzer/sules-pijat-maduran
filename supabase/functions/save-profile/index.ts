import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

/** Returns a canonical Indonesian mobile number for validation/storage, or null. */
export function normalizeIndonesianWhatsapp(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 40 || !/^\+?[\d\s().-]+$/.test(trimmed)) return null;

  const compact = trimmed.replace(/[\s().-]/g, "");
  if (!/^\+?\d+$/.test(compact)) return null;

  let subscriber: string;
  if (compact.startsWith("+62")) subscriber = compact.slice(3);
  else if (compact.startsWith("62")) subscriber = compact.slice(2);
  else if (compact.startsWith("0")) subscriber = compact.slice(1);
  else return null;

  // Indonesian mobile numbers use the 08 / +628 prefix; accept 9–12 digits after 62.
  if (!/^8\d{8,11}$/.test(subscriber)) return null;
  return `+62${subscriber}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Metode tidak diizinkan." }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Silakan masuk sebelum melengkapi profil." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) {
    return json({ error: "Layanan profil belum siap. Coba lagi nanti." }, 503);
  }

  const userClient = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "Sesi tidak valid atau telah kedaluwarsa. Masuk kembali." }, 401);

  let rawBody = "";
  try { rawBody = await req.text(); } catch { return json({ error: "Permintaan tidak dapat dibaca." }, 400); }
  if (rawBody.length > 8192) return json({ error: "Permintaan terlalu besar." }, 413);

  let parsed: unknown;
  try { parsed = JSON.parse(rawBody); } catch { return json({ error: "Format permintaan tidak valid." }, 400); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json({ error: "Format permintaan tidak valid." }, 400);
  const body = parsed as Record<string, unknown>;
  if (Object.keys(body).some(key => key !== "nama" && key !== "wa")) {
    return json({ error: "Permintaan profil hanya boleh berisi nama dan WhatsApp." }, 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: current, error: readError } = await adminClient
    .from("customers")
    .select("id,nama,wa")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (readError) return json({ error: "Profil pelanggan tidak dapat dibaca. Coba lagi." }, 503);

  const currentNama = typeof current?.nama === "string" ? current.nama : "";
  const currentWa = typeof current?.wa === "string" ? current.wa : "";
  const currentWaCanonical = normalizeIndonesianWhatsapp(currentWa);

  if (currentWa.trim() && !currentWaCanonical) {
    return json({
      code: "WA_PERLU_VERIFIKASI",
      error: "Nomor WhatsApp yang sudah tersimpan belum lolos format dan tidak dapat diganti tanpa verifikasi tambahan. Hubungi Admin untuk bantuan.",
    }, 409);
  }

  // Never let a profile-save request overwrite a profile already complete.
  if (currentNama.trim() && currentWa.trim() && currentWaCanonical) {
    return json({
      profile: { id: userData.user.id, nama: currentNama, wa: currentWa },
      complete: true,
      updated: false,
    });
  }

  const requestedNama = typeof body.nama === "string" ? body.nama.trim() : "";
  const requestedWa = normalizeIndonesianWhatsapp(body.wa);
  const nextNama = currentNama.trim() ? currentNama : requestedNama;
  const nextWa = currentWa.trim() && currentWaCanonical ? currentWa : requestedWa;

  if (!nextNama.trim()) {
    return json({ code: "NAMA_TIDAK_VALID", error: "Nama lengkap wajib diisi." }, 400);
  }
  if (!nextWa || !nextWa.trim()) {
    return json({ code: "WA_FORMAT_TIDAK_VALID", error: "Masukkan nomor WhatsApp Indonesia yang valid, misalnya 08… atau +62…." }, 400);
  }

  // service_role is used only in this JWT-authenticated function; customer RLS policies
  // and table grants are intentionally unchanged. Existing valid fields are preserved.
  const { data: saved, error: saveError } = await adminClient
    .from("customers")
    .upsert({ id: userData.user.id, nama: nextNama, wa: nextWa }, { onConflict: "id" })
    .select("id,nama,wa")
    .single();
  if (saveError || !saved || !String(saved.nama || "").trim() || !normalizeIndonesianWhatsapp(saved.wa)) {
    return json({ error: "Profil belum dapat disimpan. Periksa nama dan nomor WhatsApp, lalu coba lagi." }, 500);
  }

  return json({
    profile: { id: saved.id, nama: saved.nama, wa: saved.wa },
    complete: true,
    updated: true,
  });
});
