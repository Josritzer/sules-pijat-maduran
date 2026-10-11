// Mengubah tautan pendek Google Maps menjadi koordinat. Tanpa dependensi agar mudah diuji.
// Keamanan: hanya host Google/goo.gl yang diizinkan (awal dan setiap lompatan), redirect diikuti manual,
// jumlah lompatan, waktu, dan ukuran isi dibatasi. Tidak pernah menebak lokasi dari nama tempat.

export const MAX_HOPS = 6;
export const HOP_TIMEOUT_MS = 6000;
export const MAX_BODY_BYTES = 300_000;

export type Hasil =
  | { ok: true; lat: number; lng: number; sumber: "url" | "halaman" }
  | { ok: false; kode: "tidak_didukung" | "tidak_ditemukan" | "gagal_ambil" };

export function koordinatValid(la: number, ln: number): boolean {
  return Number.isFinite(la) && Number.isFinite(ln) && Math.abs(la) <= 90 && Math.abs(ln) <= 180 && !(la === 0 && ln === 0);
}

// Host yang boleh dikunjungi. goo.gl hanya untuk jalur /maps.
export function hostDiizinkan(u: URL): boolean {
  if (u.protocol !== "https:" || u.username || u.password || (u.port && u.port !== "443")) return false;
  const h = u.hostname.toLowerCase();
  if (h === "maps.app.goo.gl") return true;
  if (h === "goo.gl") return u.pathname.startsWith("/maps");
  if (h === "maps.google.com") return true;
  if (h === "google.com" || h === "www.google.com") return u.pathname.startsWith("/maps");
  return false;
}

const D = "(-?\\d+\\.\\d+)";
const POLA_URL = [
  new RegExp("!3d" + D + "!4d" + D),
  new RegExp("@" + D + "," + D),
  new RegExp("[?&](?:q|ll|query|destination|daddr|center)=" + D + "\\s*,\\s*" + D),
];
const POLA_HALAMAN = [
  new RegExp("!3d" + D + "!4d" + D),
  new RegExp("center=" + D + ",\\s*" + D),
  new RegExp("@" + D + "," + D),
];

export function cariKoordinat(teks: string, pola: RegExp[]): { lat: number; lng: number } | null {
  let t = teks;
  for (let i = 0; i < 2; i++) { try { t = decodeURIComponent(t); } catch { break; } }
  for (const re of pola) {
    const m = t.match(re);
    if (m) {
      const lat = parseFloat(m[1]), lng = parseFloat(m[2]);
      return koordinatValid(lat, lng) ? { lat, lng } : null;
    }
  }
  return null;
}

async function bacaTerbatas(res: Response): Promise<string> {
  const reader = res.body?.getReader();
  if (!reader) return "";
  const dec = new TextDecoder();
  let out = "", total = 0;
  while (total < MAX_BODY_BYTES) {
    const { done, value } = await reader.read();
    if (done || !value) break;
    total += value.byteLength;
    out += dec.decode(value, { stream: true });
  }
  try { await reader.cancel(); } catch { /* abaikan */ }
  return out;
}

export async function resolveMapsUrl(input: string, fetchFn: typeof fetch = fetch): Promise<Hasil> {
  let u: URL;
  try { u = new URL(input.trim()); } catch { return { ok: false, kode: "tidak_didukung" }; }
  if (!hostDiizinkan(u)) return { ok: false, kode: "tidak_didukung" };

  for (let hop = 0; hop <= MAX_HOPS; hop++) {
    const dariUrl = cariKoordinat(u.toString(), POLA_URL);
    if (dariUrl) return { ok: true, ...dariUrl, sumber: "url" };

    let res: Response;
    try {
      res = await fetchFn(u.toString(), {
        method: "GET",
        redirect: "manual",
        signal: AbortSignal.timeout(HOP_TIMEOUT_MS),
        headers: { "User-Agent": "Mozilla/5.0 (compatible; SulesBooking/1.0)", "Accept-Language": "id,en;q=0.8" },
      });
    } catch { return { ok: false, kode: "gagal_ambil" }; }

    if (res.status >= 300 && res.status < 400) {
      const lokasi = res.headers.get("location");
      try { await res.body?.cancel(); } catch { /* abaikan */ }
      if (!lokasi) return { ok: false, kode: "tidak_ditemukan" };
      let next: URL;
      try { next = new URL(lokasi, u); } catch { return { ok: false, kode: "tidak_ditemukan" }; }
      // Koordinat sering ada di URL tujuan atau di parameter "continue" milik halaman persetujuan Google,
      // jadi cek teksnya dulu walaupun host tujuan tidak akan dikunjungi.
      const dariLokasi = cariKoordinat(next.toString(), POLA_URL);
      if (dariLokasi) return { ok: true, ...dariLokasi, sumber: "url" };
      if (!hostDiizinkan(next)) return { ok: false, kode: "tidak_ditemukan" };
      u = next;
      continue;
    }
    if (res.status === 200) {
      const html = await bacaTerbatas(res);
      const dariHalaman = cariKoordinat(html, POLA_HALAMAN);
      if (dariHalaman) return { ok: true, ...dariHalaman, sumber: "halaman" };
    } else {
      try { await res.body?.cancel(); } catch { /* abaikan */ }
    }
    return { ok: false, kode: "tidak_ditemukan" };
  }
  return { ok: false, kode: "tidak_ditemukan" };
}
