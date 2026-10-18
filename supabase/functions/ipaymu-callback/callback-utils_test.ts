import {
  constantTimeEqualHex,
  normalizeCallback,
  hmacSha256Hex,
} from "./callback-utils.ts";

Deno.test("callback normalization removes signature and sorts keys", () => {
  const result = normalizeCallback({
    status: "berhasil",
    signature: "untrusted",
    status_code: "1",
    trx_id: "12345",
    additional_info: "[]",
  });
  assertEquals(Object.keys(result), ["additional_info", "status", "status_code", "trx_id"]);
  assertEquals(result["status_code"], 1);
  assertEquals(result["trx_id"], 12345);
  assertEquals(result["additional_info"], []);
  assertEquals("signature" in result, false);
});

Deno.test("callback normalization converts known boolean strings", () => {
  assertEquals(normalizeCallback({ is_escrow: "true" })["is_escrow"], true);
  assertEquals(normalizeCallback({ is_escrow: "0" })["is_escrow"], false);
});

Deno.test("hex signature comparison accepts equal hex case-insensitively", () => {
  const lower = "a".repeat(64);
  assertEquals(constantTimeEqualHex(lower, lower.toUpperCase()), true);
});

Deno.test("hex signature comparison rejects mismatches and malformed input", () => {
  assertEquals(constantTimeEqualHex("a".repeat(64), "b".repeat(64)), false);
  assertEquals(constantTimeEqualHex("not-a-signature", "not-a-signature"), false);
});

Deno.test("HMAC-SHA256 output is deterministic and secret-sensitive", async () => {
  const first = await hmacSha256Hex('{"status":"berhasil"}', "sandbox-test-va");
  assertEquals(first.length, 64);
  assertEquals(await hmacSha256Hex('{"status":"berhasil"}', "sandbox-test-va"), first);
  assertNotEquals(await hmacSha256Hex('{"status":"berhasil"}', "different-va"), first);
});

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("assertEquals failed: " + JSON.stringify(actual) + " !== " + JSON.stringify(expected));
  }
}
function assertNotEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    throw new Error("assertNotEquals failed: values unexpectedly equal");
  }
}
