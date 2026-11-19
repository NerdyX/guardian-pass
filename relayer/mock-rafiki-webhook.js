/**
 * Mock Rafiki / Open Payments Webhook Dispatcher
 * Simulates a completed ILPv4 STREAM payment notification to test the Relayer.
 */
const http = require("http");
const crypto = require("crypto");

const RELAYER_PORT = process.env.PORT || 4000;
const SECRET = process.env.RAFIKI_WEBHOOK_SECRET || "rafiki_test_secret_change_me";

// Sample test payload representing a Rafiki incoming_payment.completed event
const mockPayload = {
  id: "evt_ilp_" + crypto.randomBytes(8).toString("hex"),
  type: "incoming_payment.completed",
  data: {
    id: "https://rafiki.example.com/incoming-payments/ip_" + crypto.randomBytes(6).toString("hex"),
    walletAddressId: "https://rafiki.example.com/accounts/subscriptions",
    receivedAmount: {
      value: "10000",
      assetCode: "USD",
      assetScale: 2
    },
    metadata: {
      // The subscriber wallet receiving the Soulbound NFT
      subscriberAddress: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
      tier: 2, // 2 = Member, 3 = VIP
      yearsCount: 1,
      targetNetwork: "casper" // e.g. "casper", "base", "sepolia"
    }
  }
};

const rawBody = JSON.stringify(mockPayload);
const timestamp = Math.floor(Date.now() / 1000);
const signature = crypto
  .createHmac("sha256", SECRET)
  .update(`${timestamp}.${rawBody}`, "utf8")
  .digest("hex");

const rafikiHeader = `t=${timestamp},v1=${signature}`;

console.log("📤 Sending Mock Rafiki / ILPv4 Webhook to Relayer...");
console.log(`Target: POST http://localhost:${RELAYER_PORT}/webhook/rafiki`);
console.log(`Payment ID: ${mockPayload.data.id}`);
console.log(`Subscriber: ${mockPayload.data.metadata.subscriberAddress}`);
console.log(`Network:    ${mockPayload.data.metadata.targetNetwork}\n`);

const req = http.request(
  {
    hostname: "localhost",
    port: RELAYER_PORT,
    path: "/webhook/rafiki",
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(rawBody),
      "rafiki-signature": rafikiHeader
    }
  },
  (res) => {
    let responseBody = "";
    res.on("data", (chunk) => {
      responseBody += chunk;
    });
    res.on("end", () => {
      console.log(`Status Code: ${res.statusCode}`);
      console.log("Response:", responseBody);
    });
  }
);

req.on("error", (err) => {
  console.error("❌ Failed to reach relayer. Is the relayer server running?", err.message);
});

req.write(rawBody);
req.end();
