import { createHash, createHmac } from "node:crypto";

export function signatureFor(method, va, rawBody, apiKey) {
  const bodyHash = createHash("sha256").update(rawBody).digest("hex").toLowerCase();
  const stringToSign = method + ":" + va + ":" + bodyHash + ":" + apiKey;
  return createHmac("sha256", apiKey).update(stringToSign).digest("hex");
}
