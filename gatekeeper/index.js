/**
 * Guardian Pass Gatekeeper SDK
 * Drop-in access verification middleware for all your web apps and backend services.
 */

const DEFAULT_CONFIG = {
  // Default to XRPL EVM Sidechain (or Casper, Base, etc.)
  rpcUrl: process.env.GUARDIAN_RPC_URL || "https://rpc.testnet.xrplevm.org",
  contractAddress: process.env.GUARDIAN_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000",
  portalUrl: process.env.GUARDIAN_PORTAL_URL || "http://localhost:8080",
  appName: process.env.APP_NAME || "Protected Application",
  requiredTier: 2 // 1 = Guest, 2 = Member, 3 = VIP
};

/**
 * Check if a user's wallet has active, unexpired Guardian Pass authorization
 */
async function checkGuardianAccess(userAddress, customConfig = {}) {
  const config = { ...DEFAULT_CONFIG, ...customConfig };
  
  if (!userAddress || !userAddress.startsWith("0x")) {
    return { authorized: false, reason: "invalid_address" };
  }

  try {
    // ABI signature for hasMinimumTier(address,uint8) -> bool
    // Function selector: keccak256("hasMinimumTier(address,uint8)") = 0x6e2df8a5
    const cleanAddress = userAddress.toLowerCase().replace("0x", "").padStart(64, "0");
    const tierHex = Number(config.requiredTier).toString(16).padStart(64, "0");
    const callData = `0x6e2df8a5${cleanAddress}${tierHex}`;

    const response = await fetch(config.rpcUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_call",
        params: [
          {
            to: config.contractAddress,
            data: callData
          },
          "latest"
        ]
      })
    });

    const json = await response.json();
    if (json.error || !json.result) {
      console.error("RPC Error verifying Guardian Pass:", json.error);
      return { authorized: false, reason: "rpc_error" };
    }

    // A return of 1 (padded) means authorized, 0 means inactive or expired
    const isAuthorized = parseInt(json.result, 16) === 1;

    return {
      authorized: isAuthorized,
      userAddress,
      requiredTier: config.requiredTier,
      reason: isAuthorized ? "active" : "expired_or_not_found"
    };
  } catch (err) {
    console.error("Guardian Gatekeeper exception:", err.message);
    return { authorized: false, reason: "network_exception" };
  }
}

/**
 * Express / Node.js Middleware to protect routes and redirect unauthorized users to Guardian Pass
 */
function guardianGatekeeperMiddleware(customConfig = {}) {
  const config = { ...DEFAULT_CONFIG, ...customConfig };

  return async function(req, res, next) {
    // Look for user wallet address in session, cookie, auth header, or query
    const userAddress =
      req.session?.walletAddress ||
      req.cookies?.walletAddress ||
      req.headers["x-wallet-address"] ||
      req.query.wallet;

    if (!userAddress) {
      const returnUrl = `${req.protocol}://${req.get("host")}${req.originalUrl}`;
      const redirectTarget = `${config.portalUrl}?redirect_uri=${encodeURIComponent(returnUrl)}&app_name=${encodeURIComponent(config.appName)}&required_tier=${config.requiredTier}`;
      return res.redirect(redirectTarget);
    }

    const verification = await checkGuardianAccess(userAddress, config);

    if (verification.authorized) {
      req.guardianPass = verification;
      return next();
    }

    // Access Revoked or Expired -> Redirect to Guardian Pass Portal to mint/renew
    const returnUrl = `${req.protocol}://${req.get("host")}${req.originalUrl}`;
    const redirectTarget = `${config.portalUrl}?redirect_uri=${encodeURIComponent(returnUrl)}&app_name=${encodeURIComponent(config.appName)}&required_tier=${config.requiredTier}&status=expired`;
    return res.redirect(redirectTarget);
  };
}

module.exports = {
  checkGuardianAccess,
  guardianGatekeeperMiddleware,
  DEFAULT_CONFIG
};
