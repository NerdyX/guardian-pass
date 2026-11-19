const http = require("http");
const crypto = require("crypto");
const {
  PORT,
  DEFAULT_NETWORK,
  RELAYER_PRIVATE_KEY,
  RAFIKI_WEBHOOK_SECRET,
  NETWORKS,
  AUTH_CONTRACT_ABI
} = require("./config");

// In-memory set for local webhook idempotency cache
const processedPayments = new Set();

/**
 * Validate HMAC-SHA256 signature from Rafiki / Open Payments webhook
 * Supports standard format: "t=TIMESTAMP,v1=HEX_DIGEST" or raw hex HMAC
 */
function verifyRafikiSignature(rawBody, signatureHeader, secret) {
  if (!signatureHeader || !secret) {
    console.warn("⚠️ Warning: Webhook signature verification bypassed (missing header or secret).");
    return true; // Set to false in strict production
  }

  try {
    let signatureToVerify = signatureHeader;
    let payloadToSign = rawBody;

    // Standard Rafiki signature format: t=TIMESTAMP,v1=HASH
    if (signatureHeader.includes("t=") && signatureHeader.includes("v1=")) {
      const parts = signatureHeader.split(",");
      const timestampPart = parts.find((p) => p.trim().startsWith("t="));
      const hashPart = parts.find((p) => p.trim().startsWith("v1="));

      if (timestampPart && hashPart) {
        const timestamp = timestampPart.trim().substring(2);
        signatureToVerify = hashPart.trim().substring(3);
        payloadToSign = `${timestamp}.${rawBody}`;
      }
    }

    const expectedSignature = crypto
      .createHmac("sha256", secret)
      .update(payloadToSign, "utf8")
      .digest("hex");

    return crypto.timingSafeEqual(
      Buffer.from(signatureToVerify, "hex"),
      Buffer.from(expectedSignature, "hex")
    );
  } catch (err) {
    console.error("Signature verification error:", err.message);
    return false;
  }
}

/**
 * Get ethers Contract instance for a specific EVM network
 */
function getContractForNetwork(networkKey) {
  let ethers;
  try {
    ethers = require("ethers");
  } catch (err) {
    throw new Error("Package 'ethers' is not installed. Run 'npm install' in the relayer directory.");
  }

  const networkConfig = NETWORKS[networkKey] || NETWORKS[DEFAULT_NETWORK];
  if (!networkConfig) {
    throw new Error(`Unknown network: ${networkKey}. Available: ${Object.keys(NETWORKS).join(", ")}`);
  }

  if (!RELAYER_PRIVATE_KEY) {
    throw new Error("RELAYER_PRIVATE_KEY is not configured in .env");
  }

  const provider = new ethers.JsonRpcProvider(networkConfig.rpcUrl);
  const signer = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);
  const contract = new ethers.Contract(networkConfig.contractAddress, AUTH_CONTRACT_ABI, signer);

  return { contract, signer, provider, networkConfig };
}

/**
 * Process a completed Rafiki / ILPv4 incoming payment event
 */
async function handleIncomingPaymentCompleted(event) {
  const paymentData = event.data || {};
  const ilpPaymentId = paymentData.id || event.id;

  if (!ilpPaymentId) {
    throw new Error("Missing payment ID in Rafiki event payload.");
  }

  if (processedPayments.has(ilpPaymentId)) {
    console.log(`ℹ️ Payment ${ilpPaymentId} was already processed locally. Skipping.`);
    return { status: "already_processed", ilpPaymentId };
  }

  // Extract metadata passed when the Open Payments Incoming Payment was created
  const metadata = paymentData.metadata || {};
  const subscriberAddress =
    metadata.subscriberAddress ||
    metadata.walletAddress ||
    metadata.subscriber ||
    paymentData.subscriberAddress;

  if (!subscriberAddress) {
    throw new Error("Missing subscriberAddress in payment metadata. Cannot bind NFT to subscriber.");
  }

  const tier = parseInt(metadata.tier || "2", 10); // Default: Member (2)
  const yearsCount = parseInt(metadata.yearsCount || "1", 10); // Default: 1 year
  const targetNetworkKey = metadata.targetNetwork || metadata.network || DEFAULT_NETWORK;

  console.log(`\n======================================================`);
  console.log(`⚡ [ILPv4 / Rafiki Settlement Received]`);
  console.log(`   Payment ID:    ${ilpPaymentId}`);
  console.log(`   Subscriber:    ${subscriberAddress}`);
  console.log(`   Tier:          ${tier}`);
  console.log(`   Duration:      ${yearsCount} Year(s)`);
  console.log(`   Target EVM:    ${targetNetworkKey.toUpperCase()}`);
  console.log(`======================================================\n`);

  // Connect to target EVM chain and dispatch transaction
  const { contract, signer, networkConfig } = getContractForNetwork(targetNetworkKey);

  console.log(`Relaying to ${networkConfig.name} (${networkConfig.contractAddress})...`);
  console.log(`Relayer Wallet: ${await signer.getAddress()}`);

  const tx = await contract.processInterledgerPayment(
    subscriberAddress,
    tier,
    yearsCount,
    ilpPaymentId
  );

  console.log(`🚀 Transaction submitted on ${networkConfig.name}: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`✅ Confirmed in block ${receipt.blockNumber} on ${networkConfig.name}!`);

  processedPayments.add(ilpPaymentId);

  return {
    success: true,
    txHash: tx.hash,
    blockNumber: receipt.blockNumber,
    network: networkConfig.name,
    subscriberAddress,
    tier,
    yearsCount,
    ilpPaymentId
  };
}

/**
 * Process a dispute or reversal event from payment provider
 */
async function handlePaymentDisputed(event) {
  const paymentData = event.data || {};
  const tokenId = paymentData.tokenId || paymentData.metadata?.tokenId;
  const targetNetworkKey = paymentData.metadata?.targetNetwork || DEFAULT_NETWORK;
  const reason = paymentData.reason || "Interledger payment disputed or reversed";

  if (!tokenId) {
    console.warn("⚠️ Disputed event received but no tokenId provided to revoke.");
    return;
  }

  console.log(`🚨 Revoking access for Token #${tokenId} on ${targetNetworkKey} due to: ${reason}`);
  const { contract, networkConfig } = getContractForNetwork(targetNetworkKey);

  const tx = await contract.revokeAccess(tokenId, reason);
  console.log(`Revoke transaction submitted: ${tx.hash}`);
  await tx.wait();
  console.log(`❌ Access revoked on-chain for Token #${tokenId} on ${networkConfig.name}.`);
}

/**
 * Native HTTP Request Handler
 */
const server = http.createServer(async (req, res) => {
  // CORS Headers
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, rafiki-signature, authorization");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check endpoint
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        status: "healthy",
        service: "Rafiki / ILPv4 Multi-EVM Relayer",
        defaultNetwork: DEFAULT_NETWORK,
        supportedNetworks: Object.keys(NETWORKS)
      })
    );
    return;
  }

  // Query user subscription status across an EVM network
  if (req.method === "GET" && req.url.startsWith("/status/")) {
    try {
      const url = new URL(req.url, `http://${req.headers.host}`);
      const userAddress = url.pathname.replace("/status/", "");
      const networkKey = url.searchParams.get("network") || DEFAULT_NETWORK;

      const { contract, networkConfig } = getContractForNetwork(networkKey);
      const [authorized, tier, activeAuthId, expiresAt, statusMessage] =
        await contract.checkAuthorization(userAddress);

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          network: networkConfig.name,
          userAddress,
          authorized,
          tier: Number(tier),
          activeAuthId: Number(activeAuthId),
          expiresAt: Number(expiresAt),
          expiresAtFormatted: expiresAt > 0 ? new Date(Number(expiresAt) * 1000).toISOString() : null,
          statusMessage
        })
      );
      return;
    } catch (err) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: err.message }));
      return;
    }
  }

  // Rafiki Webhook Handler: POST /webhook/rafiki or POST /webhook/ilp
  if (req.method === "POST" && (req.url === "/webhook/rafiki" || req.url === "/webhook/ilp")) {
    let rawBody = "";

    req.on("data", (chunk) => {
      rawBody += chunk.toString();
    });

    req.on("end", async () => {
      try {
        const signature =
          req.headers["rafiki-signature"] ||
          req.headers["x-rafiki-signature"] ||
          req.headers["signature"];

        if (!verifyRafikiSignature(rawBody, signature, RAFIKI_WEBHOOK_SECRET)) {
          res.writeHead(401, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Invalid webhook signature" }));
          return;
        }

        const event = JSON.parse(rawBody);
        console.log(`\n📥 Received Rafiki Webhook Event: [${event.type || "unknown"}] (ID: ${event.id})`);

        let result;
        if (event.type === "incoming_payment.completed" || event.type === "payment.completed") {
          result = await handleIncomingPaymentCompleted(event);
        } else if (event.type === "incoming_payment.expired" || event.type === "payment.disputed") {
          result = await handlePaymentDisputed(event);
        } else {
          console.log(`ℹ️ Ignored unhandled event type: ${event.type}`);
          result = { status: "ignored", eventType: event.type };
        }

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true, result }));
      } catch (err) {
        console.error("❌ Error processing webhook:", err);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: false, error: err.message }));
      }
    });
    return;
  }

  // Route not found
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Not found" }));
});

server.listen(PORT, () => {
  console.log(`
============================================================
🌐 Rafiki / ILPv4 Webhook & Multi-EVM Relayer Active
============================================================
📡 Listening on:         http://localhost:${PORT}
🎯 Webhook Endpoint:    POST http://localhost:${PORT}/webhook/rafiki
🔍 Status Endpoint:     GET  http://localhost:${PORT}/status/:userAddress
🔗 Default EVM Network: ${DEFAULT_NETWORK.toUpperCase()}
🌍 Supported Networks:  ${Object.keys(NETWORKS).join(", ")}
============================================================
`);
});
