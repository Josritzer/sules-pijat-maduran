import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";
const BASE_LAT = -7.0000833;
const BASE_LNG = 112.281;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function validPoint(lat: unknown, lng: unknown): lat is number {
  return typeof lat === "number" && Number.isFinite(lat) && lat >= -90 && lat <= 90 &&
    typeof lng === "number" && Number.isFinite(lng) && lng >= -180 && lng <= 180;
}

function normalizeIndonesianWhatsapp(value: unknown): string | null {
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
  return /^8\d{8,11}$/.test(subscriber) ? `+62${subscriber}` : null;
}

function rpcMessage(message: string) {
  const known: Array<[RegExp, string]> = [
    [/Nama pelanggan wajib/i, "Nama lengkap wajib diisi."],
    [/Nomor WA wajib/i, "Nomor WhatsApp wajib diisi."],
    [/Jumlah orang/i, "Jumlah orang pada paket tidak valid."],
    [/Paket/i, "Paket yang dipilih tidak valid."],
    [/Layanan tidak ditemukan/i, "Paket ini sedang tidak tersedia."],
    [/Tanggal booking wajib|Tanggal tidak valid|tidak boleh.*lampau/i, "Tanggal booking tidak valid atau sudah lewat."],
    [/Jam di luar|melewati jam tutup/i, "Jam yang dipilih berada di luar jam operasional atau durasinya melewati jam tutup."],
    [/lokasi.*lat\/lng|lokasi valid/i, "Untuk layanan ke Rumah, lokasi yang valid wajib diisi."],
    [/Jarak tempuh Google Routes wajib/i, "Jarak jalan belum tersedia. Hitung ulang lalu coba lagi."],
  ];
  return known.find(([pattern]) => pattern.test(message))?.[1] ?? "Booking belum dapat disimpan. Periksa data dan coba lagi.";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Metode tidak diizinkan." }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Silakan masuk sebelum membuat booking." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) return json({ error: "Layanan booking belum siap. Coba lagi nanti." }, 503);

  const userClient = createClient(supabaseUrl, publicKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "Sesi tidak valid atau telah kedaluwarsa. Masuk kembali." }, 401);

  let rawBody = "";
  try { rawBody = await req.text(); } catch { return json({ error: "Permintaan tidak dapat dibaca." }, 400); }
  if (rawBody.length > 8192) return json({ error: "Permintaan terlalu besar." }, 413);
  let parsed: unknown;
  try { parsed = JSON.parse(rawBody); } catch { return json({ error: "Format permintaan tidak valid." }, 400); }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json({ error: "Format permintaan tidak valid." }, 400);

  const body = parsed as Record<string, unknown>;
  // nama/wa remain accepted for older clients but are deliberately ignored.
  const allowed = ["nama", "wa", "serviceId", "jumlahOrang", "tanggal", "jamMulai", "tipeLokasi", "alamat", "lat", "lng"];
  if (Object.keys(body).some(key => !allowed.includes(key))) return json({ error: "Data booking berisi kolom yang tidak diizinkan." }, 400);
  const { serviceId, jumlahOrang, tanggal, jamMulai, tipeLokasi } = body;
  const alamat = body.alamat === undefined ? null : body.alamat;
  const lat = body.lat === undefined ? null : body.lat;
  const lng = body.lng === undefined ? null : body.lng;

  if (serviceId !== "90m" && serviceId !== "120m") return json({ error: "Paket yang dipilih tidak valid." }, 400);
  if (jumlahOrang !== 1 && jumlahOrang !== 2) return json({ error: "Jumlah orang pada paket tidak valid." }, 400);
  if (tipeLokasi !== "DI_TEMPAT" && tipeLokasi !== "HOME_SERVICE") return json({ error: "Lokasi layanan tidak valid." }, 400);
  const parsedDate = typeof tanggal === "string" ? new Date(`${tanggal}T00:00:00.000Z`) : null;
  if (typeof tanggal !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(tanggal) || !parsedDate || Number.isNaN(parsedDate.getTime()) || parsedDate.toISOString().slice(0, 10) !== tanggal) {
    return json({ error: "Tanggal booking tidak valid." }, 400);
  }
  if (typeof jamMulai !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(jamMulai)) return json({ error: "Jam mulai tidak valid." }, 400);
  if (alamat !== null && (typeof alamat !== "string" || alamat.length > 500)) return json({ error: "Alamat terlalu panjang atau tidak valid." }, 400);
  if (jumlahOrang === 2 && !(tipeLokasi === "HOME_SERVICE" && serviceId === "90m")) {
    return json({ error: "Paket 2 orang hanya tersedia untuk Pijat 90 Menit ke Rumah." }, 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: profile, error: profileError } = await adminClient
    .from("customers")
    .select("nama,wa")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (profileError) return json({ error: "Profil pelanggan tidak dapat diperiksa. Coba lagi." }, 503);
  const nama = typeof profile?.nama === "string" ? profile.nama.trim() : "";
  const wa = typeof profile?.wa === "string" ? profile.wa.trim() : "";
  if (!nama || !wa || !normalizeIndonesianWhatsapp(wa)) {
    return json({ code: "PROFIL_BELUM_LENGKAP", error: "Profil belum lengkap. Lengkapi nama dan nomor WhatsApp yang valid sebelum membuat booking." }, 409);
  }

  let jarakMeter: number | null = null;
  if (tipeLokasi === "HOME_SERVICE") {
    if (!validPoint(lat, lng)) return json({ error: "Untuk layanan ke Rumah, lokasi GPS/koordinat yang valid wajib diisi." }, 400);
    const routesKey = Deno.env.get("GOOGLE_ROUTES_API_KEY");
    if (!routesKey) return json({ error: "Perhitungan Google Routes belum dikonfigurasi. Coba lagi nanti." }, 503);

    let routesResponse: Response;
    try {
      routesResponse = await fetch(ROUTES_URL, {
        method: "POST",
        signal: AbortSignal.timeout(12000),
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": routesKey,
          "X-Goog-FieldMask": "routes.distanceMeters",
        },
        body: JSON.stringify({
          origin: { location: { latLng: { latitude: BASE_LAT, longitude: BASE_LNG } } },
          destination: { location: { latLng: { latitude: lat, longitude: lng } } },
          travelMode: "TWO_WHEELER",
        }),
      });
    } catch {
      return json({ error: "Google Routes tidak dapat dihubungi. Periksa koneksi dan coba lagi." }, 502);
    }
    if (!routesResponse.ok) return json({ error: "Google Routes gagal menghitung jarak jalan. Coba lagi." }, 502);
    let routesData: any;
    try { routesData = await routesResponse.json(); } catch { return json({ error: "Respons Google Routes tidak valid. Coba lagi." }, 502); }
    const distance = routesData?.routes?.[0]?.distanceMeters;
    if (typeof distance !== "number" || !Number.isFinite(distance) || distance < 0) {
      return json({ error: "Google Routes tidak mengembalikan jarak jalan yang valid." }, 422);
    }
    jarakMeter = distance;
  } else if (lat !== null || lng !== null) {
    if (!validPoint(lat, lng)) return json({ error: "Koordinat tidak valid." }, 400);
  }

  const { data, error } = await adminClient.rpc("create_booking_server", {
    p_customer_id: userData.user.id,
    p_nama: nama,
    p_wa: wa,
    p_service_id: serviceId,
    p_jumlah_orang: jumlahOrang,
    p_tanggal: tanggal,
    p_jam_mulai: jamMulai,
    p_tipe_lokasi: tipeLokasi,
    p_alamat: alamat,
    p_lat: lat,
    p_lng: lng,
    p_jarak_meter: jarakMeter,
  });
  if (error) return json({ error: rpcMessage(error.message) }, 400);
  return json(data);
});
