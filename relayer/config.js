try {
  require("dotenv").config();
} catch (e) {
  // dotenv not installed yet, falls back to process.env
}

/**
 * Minimal ABI for the AuthSubscriptionNFT contract interactions
 */
const AUTH_CONTRACT_ABI = [
  "function processInterledgerPayment(address subscriber, uint8 tier, uint32 yearsCount, string calldata ilpPaymentRef) external returns (uint256 tokenId, uint64 expiresAt)",
  "function processFiatPayment(address subscriber, uint8 tier, uint32 yearsCount, string calldata externalPaymentId) external returns (uint256 tokenId, uint64 expiresAt)",
  "function revokeAccess(uint256 tokenId, string calldata reason) external",
  "function hasAccess(address user) external view returns (bool)",
  "function subscriberTokenId(address user) external view returns (uint256)",
  "function checkAuthorization(address user) external view returns (bool authorized, uint8 tier, uint256 activeAuthId, uint64 expiresAt, string memory statusMessage)",
  "event InterledgerPaymentProcessed(address indexed subscriber, uint256 indexed tokenId, string ilpPaymentId, uint32 yearsCount, uint64 newExpiresAt)",
  "event SubscriptionRevoked(uint256 indexed tokenId, address indexed subscriber, string reason)"
];

/**
 * Multi-EVM Network Configurations
 * The relayer can dispatch mints/renewals to ANY EVM network based on:
 * 1. Webhook payment metadata (e.g., targetChain: "casper" or "base")
 * 2. Fallback default network (DEFAULT_NETWORK in .env)
 */
const NETWORKS = {
  // XRPL EVM Sidechain (Mainnet)
  xrplEvm: {
    name: "XRPL EVM Sidechain",
    chainId: 1440000,
    rpcUrl: process.env.XRPL_EVM_RPC_URL || "https://rpc.xrplevm.org",
    contractAddress: process.env.XRPL_EVM_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000",
    nativeSymbol: "XRP"
  },
  // XRPL EVM Sidechain (Testnet)
  xrplEvmTestnet: {
    name: "XRPL EVM Testnet",
    chainId: 1449000,
    rpcUrl: process.env.XRPL_EVM_TESTNET_RPC_URL || "https://rpc.testnet.xrplevm.org",
    contractAddress: process.env.XRPL_EVM_TESTNET_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000",
    nativeSymbol: "XRP"
  },
  // Casper Network EVM Layer
  casper: {
    name: "Casper EVM",
    chainId: parseInt(process.env.CASPER_CHAIN_ID || "1876", 10),
    rpcUrl: process.env.CASPER_RPC_URL || "https://rpc.casper-evm.testnet.network",
    contractAddress: process.env.CASPER_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000",
    nativeSymbol: "CSPR"
  },
  // Ethereum Sepolia Testnet
  sepolia: {
    name: "Ethereum Sepolia",
    chainId: 11155111,
    rpcUrl: process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org",
    contractAddress: process.env.SEPOLIA_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000"
  },
  // Ethereum Mainnet
  ethereum: {
    name: "Ethereum Mainnet",
    chainId: 1,
    rpcUrl: process.env.ETHEREUM_RPC_URL || "https://eth.llamarpc.com",
    contractAddress: process.env.ETHEREUM_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000"
  },
  // Base Mainnet
  base: {
    name: "Base Mainnet",
    chainId: 8453,
    rpcUrl: process.env.BASE_RPC_URL || "https://mainnet.base.org",
    contractAddress: process.env.BASE_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000"
  },
  // Base Sepolia Testnet
  baseSepolia: {
    name: "Base Sepolia",
    chainId: 84532,
    rpcUrl: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
    contractAddress: process.env.BASE_SEPOLIA_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000"
  },
  // Arbitrum One
  arbitrum: {
    name: "Arbitrum One",
    chainId: 42161,
    rpcUrl: process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc",
    contractAddress: process.env.ARBITRUM_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000"
  },
  // Polygon
  polygon: {
    name: "Polygon PoS",
    chainId: 137,
    rpcUrl: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com",
    contractAddress: process.env.POLYGON_AUTH_CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000"
  }
};

module.exports = {
  PORT: process.env.PORT || 4000,
  DEFAULT_NETWORK: process.env.DEFAULT_NETWORK || "casper",
  RELAYER_PRIVATE_KEY: process.env.RELAYER_PRIVATE_KEY || "",
  RAFIKI_WEBHOOK_SECRET: process.env.RAFIKI_WEBHOOK_SECRET || "rafiki_test_secret_change_me",
  NETWORKS,
  AUTH_CONTRACT_ABI
};
