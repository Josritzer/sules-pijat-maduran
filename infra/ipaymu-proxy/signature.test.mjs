import test from "node:test";
import assert from "node:assert/strict";
import { signatureFor } from "./signature.mjs";

const input = {
  method: "POST",
  va: "123456789",
  body: JSON.stringify({ amount: 60000, referenceId: "00000000-0000-4000-8000-000000000001" }),
  apiKey: "sandbox-test-key"
};

test("signature is a deterministic 64-character SHA-256 HMAC hex string", () => {
  const first = signatureFor(input.method, input.va, input.body, input.apiKey);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.equal(signatureFor(input.method, input.va, input.body, input.apiKey), first);
});

test("signature changes when the HTTP method changes", () => {
  assert.notEqual(
    signatureFor("GET", input.va, input.body, input.apiKey),
    signatureFor(input.method, input.va, input.body, input.apiKey)
  );
});

test("signature changes when the merchant VA changes", () => {
  assert.notEqual(
    signatureFor(input.method, "different-va", input.body, input.apiKey),
    signatureFor(input.method, input.va, input.body, input.apiKey)
  );
});

test("signature changes when the exact request body changes", () => {
  assert.notEqual(
    signatureFor(input.method, input.va, input.body + " ", input.apiKey),
    signatureFor(input.method, input.va, input.body, input.apiKey)
  );
});

test("signature changes when the API key changes", () => {
  assert.notEqual(
    signatureFor(input.method, input.va, input.body, "different-test-key"),
    signatureFor(input.method, input.va, input.body, input.apiKey)
  );
});
