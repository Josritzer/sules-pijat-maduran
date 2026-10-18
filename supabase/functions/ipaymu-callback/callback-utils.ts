export function constantTimeEqualHex(a: string, b: string) {
  if (!/^[0-9a-f]{64}$/i.test(a) || !/^[0-9a-f]{64}$/i.test(b)) return false;
  const left = new TextEncoder().encode(a.toLowerCase());
  const right = new TextEncoder().encode(b.toLowerCase());
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

export function normalizeCallback(input: Record<string, unknown>) {
  const normalized: Record<string, unknown> = { ...input };
  delete normalized.signature;
  for (const key of ["trx_id", "status_code", "transaction_status_code", "paid_off"]) {
    if (typeof normalized[key] === "string" && /^-?\d+$/.test(normalized[key] as string)) {
      normalized[key] = Number(normalized[key]);
    }
  }
  if (typeof normalized.is_escrow === "string") {
    const value = (normalized.is_escrow as string).toLowerCase();
    if (value === "true" || value === "1") normalized.is_escrow = true;
    else if (value === "false" || value === "0") normalized.is_escrow = false;
  }
  if (normalized.additional_info === "[]") normalized.additional_info = [];
  if (!("additional_info" in normalized)) normalized.additional_info = [];
  return Object.fromEntries(Object.keys(normalized).sort((a, b) => a.localeCompare(b)).map((key) => [key, normalized[key]]));
}

export async function hmacSha256Hex(value: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
