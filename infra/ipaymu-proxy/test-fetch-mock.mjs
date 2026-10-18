if (process.env.NODE_ENV === "test" && process.env.IPAYMU_TEST_FETCH === "1") {
  globalThis.fetch = async (input) => {
    const url = String(input);
    if (url !== "https://sandbox.ipaymu.com/api/v2/payment") {
      throw new Error("Unexpected external request in proxy test: " + url);
    }
    const checkoutUrl = process.env.IPAYMU_TEST_CHECKOUT_URL || "https://sandbox.ipaymu.com/payment/test-session";
    return new Response(JSON.stringify({
      Status: 200,
      Data: { SessionID: "sandbox-test-session", Url: checkoutUrl }
    }), { status: 200, headers: { "content-type": "application/json" } });
  };
}
