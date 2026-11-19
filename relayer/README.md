# Rafiki & ILPv4 Multi-EVM Relayer

This service connects the **Interledger Protocol (ILPv4)** and **Rafiki (Open Payments)** with the **`AuthSubscriptionNFT`** smart contract on **any EVM or Solidity-compatible network** (Casper EVM, Base, Arbitrum, Ethereum, Polygon, etc.).

---

## 🌟 How It Works

```mermaid
sequenceDiagram
    autonumber
    actor Customer
    participant OpenPayments as Rafiki / Open Payments
    participant ILPv4 as Interledger Network (ILPv4)
    participant Relayer as Relayer Server (server.js)
    participant EVM as AuthSubscriptionNFT (EVM / Casper)

    Customer->>OpenPayments: Initiates payment (Bank, MoMo, Card, XRPL/RLUSD, USDC)
    OpenPayments->>ILPv4: Routes & settles packetized STREAM payments
    ILPv4-->>OpenPayments: Settlement confirmed
    OpenPayments->>Relayer: Webhook POST /webhook/rafiki (HMAC signed)
    Note over Relayer: 1. Verifies HMAC-SHA256 signature<br/>2. Extracts subscriber, tier, duration, targetChain<br/>3. Idempotency replay check
    Relayer->>EVM: Calls processInterledgerPayment(subscriber, tier, years, ilpPaymentId)
    EVM-->>EVM: 1. Records ILP ref (replay protection)<br/>2. Mints or renews Soulbound NFT<br/>3. Binds minter & sets expiry (+365 days)
    Relayer-->>OpenPayments: 200 OK (Confirmed with txHash)
```

---

## 🚀 Key Advantages of Rafiki / ILPv4 with EVM

1. **Payment-Rail Agnostic:** Customers can pay via bank transfer (SEPA/ACH), mobile money, or crypto on another ledger (e.g. RLUSD on XRPL, Lightning), and ILPv4 settles it to your Rafiki wallet.
2. **True EVM Interoperability:** The relayer can dispatch the Soulbound NFT to **Casper EVM**, **Base**, **Arbitrum**, **Ethereum**, or any chain specified in the payment metadata or `.env`.
3. **On-Chain Idempotency:** The smart contract stores `processedFiatPayments[keccak256(ilpPaymentRef)]`, guaranteeing that network retries or duplicate webhook delivery will never double-mint or charge twice.
4. **Dispute & Revocation Management:** If a payment is disputed or reversed on the ILP layer, the relayer triggers `revokeAccess(tokenId, reason)` to instantly revoke credentials.

---

## 🛠️ Setup & Running

### 1. Install Dependencies
```bash
cd relayer
npm install
```

### 2. Configure Environment
Copy `.env.example` to `.env` and fill in your values:
```bash
cp .env.example .env
```
Ensure your `RELAYER_PRIVATE_KEY` address has been authorized on the smart contract by calling:
```solidity
authContract.setPaymentProvider(relayerAddress, true);
```

### 3. Start the Relayer Server
```bash
npm start
```
By default, the server listens on `http://localhost:4000`.

### 4. Test Locally with Mock Rafiki Webhook
In a separate terminal, trigger a test payment notification:
```bash
npm run test:mock
```

---

## 🔗 Open Payments Metadata Structure

When creating an **Incoming Payment** in Rafiki / Open Payments for a user subscription, attach the following JSON metadata:

```json
{
  "subscriberAddress": "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
  "tier": 2,
  "yearsCount": 1,
  "targetNetwork": "casper"
}
```

* `subscriberAddress`: The EVM address that will receive and own the Soulbound NFT.
* `tier`: 1 = Guest, 2 = Member, 3 = VIP, 4 = Admin.
* `yearsCount`: Number of years to purchase (1-10).
* `targetNetwork`: The EVM network to mint on (`casper`, `base`, `sepolia`, `ethereum`, etc.).
