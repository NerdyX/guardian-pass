# Rust WebAssembly Minting Portal

A high-performance WebAssembly web application built with **Rust** and **Yew** to interact with the [`AuthSubscriptionNFT`](../auth.sol) contract across **any EVM network** (Casper EVM, Base, Ethereum, etc.) and settle payments via **USDC, RLUSD, or ILPv4 / Rafiki**.

---

## 🚀 Features

* **Pure Rust & Wasm:** Compiled to `wasm32-unknown-unknown` for near-instant load times and zero runtime overhead.
* **Web3 Wallet Bridge:** Connects to MetaMask, Casper EVM, Coinbase Wallet, or any standard EVM provider.
* **Tier & Duration Selection:** Dynamic price calculation for Member ($50/yr) and VIP ($150/yr) passes.
* **Multi-Rail Checkout:**
  * **Crypto Stablecoins:** Direct on-chain approval and payment via USDC or RLUSD.
  * **Interledger / Rafiki:** Open Payments ILPv4 payment pointer checkout.
* **Cloudflare Pages + GitHub Actions:** Zero-downtime automated deployment to your custom subdomain.

---

## 🛠️ Local Development

### Prerequisites
1. Ensure Rust and the wasm target are installed:
   ```bash
   rustup target add wasm32-unknown-unknown
   ```
2. Install **Trunk** (Wasm web bundler for Rust):
   * **macOS (Homebrew):**
     ```bash
     brew install trunk
     ```
   * **Or via Cargo:**
     ```bash
     cargo install trunk
     ```

### Run Locally
From the `portal` directory:
```bash
cd portal
trunk serve
```
Open your browser at `http://localhost:8080`.

### Build for Production
```bash
trunk build --release
```
The optimized static HTML, CSS, and `.wasm` assets will be generated in `portal/dist/`.

---

## ☁️ Deploying to Cloudflare Pages via GitHub

### Step 1: Push Repository to GitHub
```bash
git init
git add .
git commit -m "feat: complete auth nft, rafiki relayer, and rust wasm portal"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

### Step 2: Configure Cloudflare Secrets in GitHub
In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:
* `CLOUDFLARE_API_TOKEN`: Create a token in the [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens) with **Cloudflare Pages (Edit)** permissions.
* `CLOUDFLARE_ACCOUNT_ID`: Found in your Cloudflare dashboard URL or Workers & Pages overview.

The GitHub Actions workflow [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) will automatically compile the Rust Wasm portal and publish it to Cloudflare Pages on every `git push`.

---

## 🌐 Connecting Your Subdomain in Cloudflare

1. Open the [Cloudflare Dashboard](https://dash.cloudflare.com/) and navigate to **Compute (Workers & Pages)**.
2. Select your Pages project: **`auth-id-portal`**.
3. Go to the **Custom Domains** tab.
4. Click **Set up a custom domain**.
5. Enter your subdomain (e.g. `mint.yourdomain.com` or `auth.yourdomain.com`).
6. If your apex domain is already managed by Cloudflare DNS, Cloudflare will automatically add the CNAME record and provision an SSL certificate in seconds.
