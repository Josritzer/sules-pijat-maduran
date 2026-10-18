import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const directory = fileURLToPath(new URL(".", import.meta.url));
const serverPath = join(directory, "server.mjs");
const mockPath = join(directory, "test-fetch-mock.mjs");

async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => server.listen(0, "127.0.0.1", resolve).once("error", reject));
  const port = server.address().port;
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

async function startServer(overrides = {}) {
  const port = await freePort();
  const child = spawn(process.execPath, ["--import", mockPath, serverPath], {
    cwd: directory,
    env: {
      ...process.env,
      NODE_ENV: "test",
      IPAYMU_TEST_FETCH: "1",
      PORT: String(port),
      PROXY_SHARED_SECRET: "test-shared-secret",
      IPAYMU_VA: "123456789",
      IPAYMU_API_KEY: "sandbox-test-api-key",
      IPAYMU_ENV: "sandbox",
      PUBLIC_BASE_URL: "https://bookingpijat.com",
      IPAYMU_NOTIFY_URL: "https://tzupkourtcmqemymszgt.supabase.co/functions/v1/ipaymu-callback",
      ...overrides
    },
    stdio: ["ignore", "ignore", "pipe"]
  });
  let stderr = "";
  child.stderr.on("data", chunk => { stderr += chunk.toString(); });
  const baseUrl = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`Proxy exited early: ${stderr}`);
    try {
      const response = await fetch(baseUrl + "/health");
      if (response.ok) return { child, baseUrl, stop: () => stopChild(child) };
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 40));
  }
  await stopChild(child);
  throw new Error(`Proxy did not start: ${stderr}`);
}

async function stopChild(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise(resolve => child.once("exit", resolve)),
    new Promise(resolve => setTimeout(resolve, 1500))
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

const validBody = {
  referenceId: "00000000-0000-4000-8000-000000000001",
  amount: 60000,
  productName: "Pijat 90 Menit",
  description: "SL Relax booking test"
};
const headers = { "content-type": "application/json", authorization: "Bearer test-shared-secret" };

test("health endpoint reports sandbox mode", async t => {
  const server = await startServer();
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/health");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, mode: "sandbox" });
});

test("rejects requests without shared-secret authorization", async t => {
  const server = await startServer();
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/v1/redirect-payment", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(validBody)
  });
  assert.equal(response.status, 401);
});

test("production mode remains disabled", async t => {
  const server = await startServer({ IPAYMU_ENV: "production" });
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/v1/redirect-payment", {
    method: "POST", headers, body: JSON.stringify(validBody)
  });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, "production_disabled_until_sandbox_verification");
});

test("rejects malformed JSON", async t => {
  const server = await startServer();
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/v1/redirect-payment", { method: "POST", headers, body: "{bad" });
  assert.equal(response.status, 400);
});

test("rejects invalid UUID and input before calling the provider", async t => {
  const server = await startServer();
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/v1/redirect-payment", {
    method: "POST", headers, body: JSON.stringify({ ...validBody, referenceId: "not-a-uuid" })
  });
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "invalid_payment_request");
});

test("returns only a validated Sandbox checkout URL", async t => {
  const server = await startServer();
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/v1/redirect-payment", {
    method: "POST", headers, body: JSON.stringify(validBody)
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    sessionId: "sandbox-test-session",
    checkoutUrl: "https://sandbox.ipaymu.com/payment/test-session"
  });
});

test("rejects a deceptive checkout hostname", async t => {
  const server = await startServer({ IPAYMU_TEST_CHECKOUT_URL: "https://sandbox.ipaymu.com.attacker.example/pay" });
  t.after(server.stop);
  const response = await fetch(server.baseUrl + "/v1/redirect-payment", {
    method: "POST", headers, body: JSON.stringify(validBody)
  });
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error, "ipaymu_payment_session_failed");
});

test("rate limits repeated requests from one client", async t => {
  const server = await startServer();
  t.after(server.stop);
  const send = () => fetch(server.baseUrl + "/v1/redirect-payment", {
    method: "POST", headers, body: JSON.stringify(validBody)
  });
  for (let i = 0; i < 10; i++) assert.equal((await send()).status, 200);
  const blocked = await send();
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).error, "rate_limit_exceeded");
});
