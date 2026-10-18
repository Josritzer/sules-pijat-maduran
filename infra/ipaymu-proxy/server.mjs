import http from "node:http";
import { timingSafeEqual } from "node:crypto";
import { signatureFor } from "./signature.mjs";

const PORT = Number(process.env.PORT || 8080);
const SHARED_SECRET = process.env.PROXY_SHARED_SECRET || "";
const IPAYMU_VA = process.env.IPAYMU_VA || "";
const IPAYMU_API_KEY = process.env.IPAYMU_API_KEY || "";
const IPAYMU_ENV = process.env.IPAYMU_ENV || "sandbox";
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "https://bookingpijat.com").replace(/\/+$/, "");
const IPAYMU_NOTIFY_URL = process.env.IPAYMU_NOTIFY_URL || "";
const MAX_BODY_BYTES = 16 * 1024;
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" };

function respond(res, status, body) {
  res.writeHead(status, JSON_HEADERS);
  res.end(JSON.stringify(body));
}
function safeEqual(left, right) {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}
function timestamp14() {
  const d = new Date();
  return d.getUTCFullYear().toString() + String(d.getUTCMonth() + 1).padStart(2, "0") +
    String(d.getUTCDate()).padStart(2, "0") + String(d.getUTCHours()).padStart(2, "0") +
    String(d.getUTCMinutes()).padStart(2, "0") + String(d.getUTCSeconds()).padStart(2, "0");
}
async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error("BODY_TOO_LARGE");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") return respond(res, 200, { ok: true, mode: IPAYMU_ENV });
  if (req.method !== "POST" || req.url !== "/v1/redirect-payment") return respond(res, 404, { error: "not_found" });
  if (!SHARED_SECRET || !IPAYMU_VA || !IPAYMU_API_KEY || !IPAYMU_NOTIFY_URL) return respond(res, 503, { error: "proxy_not_configured" });
  if (IPAYMU_ENV !== "sandbox") return respond(res, 503, { error: "production_disabled_until_sandbox_verification" });

  const authorization = req.headers.authorization || "";
  if (!authorization.startsWith("Bearer ") || !safeEqual(authorization.slice(7), SHARED_SECRET)) {
    return respond(res, 401, { error: "unauthorized" });
  }

  let input;
  try { input = await readJson(req); }
  catch (error) { return respond(res, error && error.message === "BODY_TOO_LARGE" ? 413 : 400, { error: "invalid_json" }); }

  const referenceId = typeof input?.referenceId === "string" ? input.referenceId : "";
  const amount = Number(input?.amount);
  const productName = typeof input?.productName === "string" ? input.productName.trim() : "";
  const description = typeof input?.description === "string" ? input.description.trim() : "";
  if (!/^[0-9a-f-]{36}$/i.test(referenceId) || !Number.isSafeInteger(amount) || amount < 1 ||
      !productName || productName.length > 120 || !description || description.length > 250) {
    return respond(res, 400, { error: "invalid_payment_request" });
  }

  const timestamp = timestamp14();
  const body = {
    product: [productName], qty: ["1"], price: [String(amount)], description: [description],
    returnUrl: PUBLIC_BASE_URL + "/?payment=return",
    notifyUrl: IPAYMU_NOTIFY_URL,
    cancelUrl: PUBLIC_BASE_URL + "/?payment=cancel",
    referenceId
  };
  const rawBody = JSON.stringify(body);
  const signature = signatureFor("POST", IPAYMU_VA, rawBody, IPAYMU_API_KEY);

  let response;
  try {
    response = await fetch("https://sandbox.ipaymu.com/api/v2/payment", {
      method: "POST", signal: AbortSignal.timeout(15000),
      headers: { "content-type": "application/json", va: IPAYMU_VA, signature, timestamp },
      body: rawBody
    });
  } catch { return respond(res, 502, { error: "ipaymu_unreachable" }); }

  let result;
  try { result = await response.json(); }
  catch { return respond(res, 502, { error: "ipaymu_invalid_response" }); }

  const status = Number(result?.Status);
  const sessionId = result?.Data?.SessionID;
  const checkoutUrl = result?.Data?.Url;
  if (!response.ok || status !== 200 || typeof sessionId !== "string" ||
      typeof checkoutUrl !== "string" || !checkoutUrl.startsWith("https://sandbox.ipaymu.com/")) {
    return respond(res, 502, { error: "ipaymu_payment_session_failed" });
  }
  return respond(res, 200, { sessionId, checkoutUrl });
});

server.listen(PORT, "0.0.0.0", () => console.log("iPaymu sandbox proxy listening on port " + PORT));
