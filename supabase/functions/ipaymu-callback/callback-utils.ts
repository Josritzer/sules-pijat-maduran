export function constantTimeEqualHex(a: string, b: string) {
  if (!/^[0-9a-f]{64}$/i.test(a) || !/^[0-9a-f]{64}$/i.test(b)) return false;
  const left = new TextEncoder().encode(a.toLowerCase());
  const right = new TextEncoder().encode(b.toLowerCase());
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

export function normalizeCallback(input: Record<string, unknown>) {
  const normalized: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(input)) {
    if (key === "signature") continue;
    if (key === "is_escrow") {
      normalized[key] = raw === true || raw === 1 || raw === "true" || raw === "1";
    } else if (["trx_id", "status_code", "transaction_status_code", "paid_off"].includes(key)) {
      const value = typeof raw === "string" ? Number.parseInt(raw, 10) : raw;
      normalized[key] = value;
    } else if (key === "additional_info") {
      normalized[key] = raw === "[]" ? [] : raw;
    } else {
      normalized[key] = String(raw);
    }
  }
  if (!("additional_info" in normalized)) normalized.additional_info = [];
  return Object.fromEntries(Object.keys(normalized).sort((a, b) => a < b ? -1 : a > b ? 1 : 0).map((key) => [key, normalized[key]]));
}

export async function hmacSha256Hex(value: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
