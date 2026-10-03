import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE_LAT = -7.0000833;
const BASE_LNG = 112.281;
const ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function validCoordinatePair(point: unknown): point is { lat: number; lng: number } {
  if (!point || typeof point !== "object") return false;
  const value = point as Record<string, unknown>;
  return typeof value.lat === "number" && Number.isFinite(value.lat) && value.lat >= -90 && value.lat <= 90 &&
    typeof value.lng === "number" && Number.isFinite(value.lng) && value.lng >= -180 && value.lng <= 180;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Metode tidak diizinkan." }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "Sesi pelanggan diperlukan." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const apiKey = Deno.env.get("GOOGLE_ROUTES_API_KEY");
  if (!supabaseUrl || !publicKey) return json({ error: "Layanan belum siap. Coba lagi nanti." }, 503);

  const authClient = createClient(supabaseUrl, publicKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "Sesi tidak valid atau telah kedaluwarsa." }, 401);
  if (!apiKey) return json({ error: "Perhitungan jarak jalan sedang tidak tersedia. Coba lagi nanti." }, 503);

  let rawBody = "";
  try { rawBody = await req.text(); } catch { return json({ error: "Permintaan tidak dapat dibaca." }, 400); }
  if (rawBody.length > 2048) return json({ error: "Permintaan terlalu besar." }, 413);

  let body: unknown;
  try { body = JSON.parse(rawBody); } catch { return json({ error: "Format permintaan tidak valid." }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "Format permintaan tidak valid." }, 400);
  const value = body as Record<string, unknown>;
  if (Object.keys(value).sort().join(",") !== "destination,origin") return json({ error: "Data rute tidak valid." }, 400);
  if (!validCoordinatePair(value.origin) || !validCoordinatePair(value.destination)) return json({ error: "Koordinat tujuan tidak valid." }, 400);

  const origin = value.origin;
  if (Math.abs(origin.lat - BASE_LAT) > 0.00001 || Math.abs(origin.lng - BASE_LNG) > 0.00001) {
    return json({ error: "Titik asal rute tidak valid." }, 400);
  }

  let routeResponse: Response;
  try {
    routeResponse = await fetch(ROUTES_URL, {
      method: "POST",
      signal: AbortSignal.timeout(12000),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "routes.distanceMeters",
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: BASE_LAT, longitude: BASE_LNG } } },
        destination: { location: { latLng: { latitude: value.destination.lat, longitude: value.destination.lng } } },
        travelMode: "TWO_WHEELER",
      }),
    });
  } catch {
    return json({ error: "Google Routes tidak dapat dihubungi. Periksa koneksi lalu coba lagi." }, 502);
  }

  if (!routeResponse.ok) return json({ error: "Google Routes gagal menghitung jarak jalan. Coba lagi." }, 502);
  let routeData: any;
  try { routeData = await routeResponse.json(); } catch { return json({ error: "Respons jarak jalan tidak valid. Coba lagi." }, 502); }
  const distanceMeters = routeData?.routes?.[0]?.distanceMeters;
  if (typeof distanceMeters !== "number" || !Number.isFinite(distanceMeters) || distanceMeters < 0) {
    return json({ error: "Google Routes tidak mengembalikan jarak jalan yang valid." }, 422);
  }

  return json({ distanceMeters, source: "google_routes", travelMode: "TWO_WHEELER" });
});
