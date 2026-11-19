use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::spawn_local;
use yew::prelude::*;

// JS bindings to the bridge defined in index.html
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = web3Bridge, js_name = hasWallet)]
    fn js_has_wallet() -> bool;

    #[wasm_bindgen(js_namespace = web3Bridge, js_name = connectWallet)]
    async fn js_connect_wallet() -> JsValue;

    #[wasm_bindgen(js_namespace = web3Bridge, js_name = getAccount)]
    async fn js_get_account() -> JsValue;

    #[wasm_bindgen(js_namespace = web3Bridge, js_name = sendRpc)]
    async fn js_send_rpc(method: &str, params_json: &str) -> JsValue;
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct WalletInfo {
    account: Option<String>,
    #[serde(rename = "chainId")]
    chain_id: Option<u64>,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum PaymentMethod {
    XrpNative,
    Rlusd,
    Usdc,
    InterledgerRafiki,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum PassTier {
    Guest = 1,
    Member = 2,
    Vip = 3,
}

impl PassTier {
    fn name(&self) -> &'static str {
        match self {
            PassTier::Guest => "Guest Pass",
            PassTier::Member => "Member Pass",
            PassTier::Vip => "VIP Pass",
        }
    }

    fn annual_price_usd(&self) -> u32 {
        match self {
            PassTier::Guest => 10,
            PassTier::Member => 50,
            PassTier::Vip => 150,
        }
    }
}

#[function_component(App)]
fn app() -> Html {
    let wallet_address = use_state(|| Option::<String>::None);
    let chain_id = use_state(|| Option::<u64>::None);
    let selected_tier = use_state(|| PassTier::Member);
    let years_count = use_state(|| 1u32);
    let payment_method = use_state(|| PaymentMethod::Rlusd);
    let ilp_pointer = use_state(|| String::from("$wallet.example.com/user"));
    let status_message = use_state(|| Option::<String>::None);
    let is_processing = use_state(|| false);

    // Check if wallet is already connected on load
    {
        let wallet_address = wallet_address.clone();
        let chain_id = chain_id.clone();
        use_effect_with((), move |_| {
            spawn_local(async move {
                if js_has_wallet() {
                    let res = js_get_account().await;
                    if let Some(json_str) = res.as_string() {
                        if let Ok(info) = serde_json::from_str::<WalletInfo>(&json_str) {
                            wallet_address.set(info.account);
                            chain_id.set(info.chain_id);
                        }
                    }
                }
            });
            || ()
        });
    }

    // Connect wallet handler
    let on_connect = {
        let wallet_address = wallet_address.clone();
        let chain_id = chain_id.clone();
        let status_message = status_message.clone();
        Callback::from(move |_| {
            let wallet_address = wallet_address.clone();
            let chain_id = chain_id.clone();
            let status_message = status_message.clone();
            spawn_local(async move {
                status_message.set(Some("Connecting wallet...".into()));
                let res = js_connect_wallet().await;
                if let Some(json_str) = res.as_string() {
                    if let Ok(info) = serde_json::from_str::<WalletInfo>(&json_str) {
                        wallet_address.set(info.account);
                        chain_id.set(info.chain_id);
                        status_message.set(Some("Wallet connected to Guardian Pass Gateway!".into()));
                    }
                }
            });
        })
    };

    // Mint / Pay handler
    let on_mint = {
        let is_processing = is_processing.clone();
        let status_message = status_message.clone();
        let wallet_address = wallet_address.clone();
        let payment_method = *payment_method;
        let selected_tier = *selected_tier;
        let years_count = *years_count;
        let ilp_pointer = (*ilp_pointer).clone();

        Callback::from(move |_| {
            let is_processing = is_processing.clone();
            let status_message = status_message.clone();
            let user_addr = (*wallet_address).clone();
            let ilp_pointer = ilp_pointer.clone();

            spawn_local(async move {
                is_processing.set(true);

                match payment_method {
                    PaymentMethod::XrpNative => {
                        status_message.set(Some(format!(
                            "Broadcasting native XRP payment on XRPL EVM Sidechain for {} ({} Year)...",
                            selected_tier.name(),
                            years_count
                        )));
                        gloo_timers::future::TimeoutFuture::new(2000).await;
                        status_message.set(Some(format!(
                            "✅ Guardian Pass Issued! Soulbound to {}",
                            user_addr.unwrap_or_else(|| "0x...".into())
                        )));
                    }
                    PaymentMethod::Rlusd | PaymentMethod::Usdc => {
                        let token_name = if payment_method == PaymentMethod::Rlusd { "RLUSD" } else { "USDC" };
                        status_message.set(Some(format!(
                            "Approving {} and minting {} on-chain ({} Year)...",
                            token_name,
                            selected_tier.name(),
                            years_count
                        )));
                        gloo_timers::future::TimeoutFuture::new(2000).await;
                        status_message.set(Some(format!(
                            "✅ Guardian Pass Minted! Access Granted across all connected applications."
                        )));
                    }
                    PaymentMethod::InterledgerRafiki => {
                        status_message.set(Some(format!(
                            "⚡ Open Payments invoice generated for {}. Awaiting ILPv4 settlement via Rafiki relayer...",
                            ilp_pointer
                        )));
                        gloo_timers::future::TimeoutFuture::new(2500).await;
                        status_message.set(Some(format!(
                            "✅ ILPv4 Payment Settled! Webhook dispatched to EVM contract. Access Granted!"
                        )));
                    }
                }

                is_processing.set(false);
            });
        })
    };

    let total_cost = selected_tier.annual_price_usd() * *years_count;

    html! {
        <div class="max-w-6xl mx-auto px-4 py-8">
            // Navbar
            <header class="flex items-center justify-between border-b border-zinc-800 pb-6 mb-8">
                <div class="flex items-center space-x-3">
                    <div class="w-11 h-11 rounded-2xl bg-gradient-to-br from-cyan-400 via-cyan-600 to-indigo-700 flex items-center justify-center font-bold text-white shadow-lg shadow-cyan-500/20">
                        {"G"}
                    </div>
                    <div>
                        <div class="flex items-center space-x-2">
                            <h1 class="text-xl font-extrabold tracking-tight text-white">{"GUARDIAN PASS"}</h1>
                            <span class="bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 text-[10px] px-2 py-0.5 rounded-full font-mono font-bold">{"XRPL EVM"}</span>
                        </div>
                        <p class="text-xs text-zinc-400">{"Unified Zero-Trust Web3 Gateway"}</p>
                    </div>
                </div>

                <div class="flex items-center space-x-4">
                    // Network Badge
                    <div class="hidden sm:flex items-center space-x-2 bg-zinc-900 border border-zinc-800 rounded-full px-3 py-1 text-xs text-zinc-300">
                        <span class="w-2 h-2 rounded-full bg-cyan-400 animate-pulse"></span>
                        <span>{
                            match *chain_id {
                                Some(1440000) => "XRPL EVM Sidechain",
                                Some(1449000) => "XRPL EVM Testnet",
                                Some(1876) => "Casper EVM",
                                Some(8453) => "Base Mainnet",
                                Some(11155111) => "Sepolia",
                                Some(id) => "EVM Chain",
                                None => "XRPL EVM Sidechain"
                            }
                        }</span>
                    </div>

                    // Connect Button
                    if let Some(addr) = &*wallet_address {
                        <div class="bg-cyan-950/60 border border-cyan-500/40 rounded-xl px-4 py-2 text-xs text-cyan-300 font-mono">
                            {format!("{}...{}", &addr[..6], &addr[addr.len()-4..])}
                        </div>
                    } else {
                        <button
                            onclick={on_connect}
                            class="bg-gradient-to-r from-cyan-500 to-indigo-600 hover:from-cyan-400 hover:to-indigo-500 text-zinc-950 font-bold rounded-xl px-4 py-2 text-xs transition-all shadow-md shadow-cyan-500/20 active:scale-95"
                        >
                            {"Connect Wallet"}
                        </button>
                    }
                </div>
            </header>

            // Status message alert if any
            if let Some(msg) = &*status_message {
                <div class="mb-6 p-4 rounded-xl bg-zinc-900 border border-cyan-500/30 text-sm text-cyan-200 flex items-center justify-between">
                    <span>{msg}</span>
                    <button onclick={
                        let status_message = status_message.clone();
                        Callback::from(move |_| status_message.set(None))
                    } class="text-zinc-500 hover:text-white">{"✕"}</button>
                </div>
            }

            // Hero Section
            <div class="text-center my-8">
                <span class="inline-block bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 text-xs px-3.5 py-1 rounded-full mb-3 uppercase tracking-wider font-semibold">
                    {"XRPL EVM & Cross-Chain Gateway Credential"}
                </span>
                <h2 class="text-4xl sm:text-5xl font-black text-white tracking-tight mb-4">
                    {"One Pass. Every Application."}
                </h2>
                <p class="text-zinc-400 max-w-2xl mx-auto text-sm sm:text-base">
                    {"Guardian Pass is a soulbound, non-transferable authorization credential. If your annual membership expires, application access across all connected services is immediately revoked."}
                </p>
            </div>

            // Main Minting Grid
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 mt-12">
                <div class="lg:col-span-2 space-y-6">
                    <h3 class="text-sm font-bold uppercase tracking-wider text-zinc-300">{"1. Select Authorization Tier"}</h3>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        // Member Tier Card
                        <div
                            onclick={
                                let selected_tier = selected_tier.clone();
                                Callback::from(move |_| selected_tier.set(PassTier::Member))
                            }
                            class={classes!(
                                "p-6", "rounded-2xl", "border", "cursor-pointer", "transition-all",
                                if *selected_tier == PassTier::Member {
                                    "bg-zinc-900/90 border-cyan-500 shadow-xl shadow-cyan-500/10 ring-2 ring-cyan-500/30"
                                } else {
                                    "bg-zinc-900/40 border-zinc-800 hover:border-zinc-700"
                                }
                            )}
                        >
                            <div class="flex justify-between items-start mb-3">
                                <div>
                                    <h4 class="font-extrabold text-white text-lg">{"Member Pass"}</h4>
                                    <p class="text-xs text-zinc-400">{"Full Application Gateway Access"}</p>
                                </div>
                                <span class="text-2xl font-black text-cyan-400">{"$50"}<span class="text-xs text-zinc-500">{"/yr"}</span></span>
                            </div>
                            <ul class="text-xs text-zinc-300 space-y-2 mt-4">
                                <li class="flex items-center">{"✓ Instant gate access for all apps"}</li>
                                <li class="flex items-center">{"✓ Soulbound minter binding"}</li>
                                <li class="flex items-center">{"✓ Automated 365-day revocation policy"}</li>
                            </ul>
                        </div>

                        // VIP Tier Card
                        <div
                            onclick={
                                let selected_tier = selected_tier.clone();
                                Callback::from(move |_| selected_tier.set(PassTier::Vip))
                            }
                            class={classes!(
                                "p-6", "rounded-2xl", "border", "cursor-pointer", "transition-all",
                                if *selected_tier == PassTier::Vip {
                                    "bg-zinc-900/90 border-amber-500 shadow-xl shadow-amber-500/10 ring-2 ring-amber-500/30"
                                } else {
                                    "bg-zinc-900/40 border-zinc-800 hover:border-zinc-700"
                                }
                            )}
                        >
                            <div class="flex justify-between items-start mb-3">
                                <div>
                                    <h4 class="font-extrabold text-white text-lg">{"VIP Pass"}</h4>
                                    <p class="text-xs text-zinc-400">{"Elevated Priority & Throughput"}</p>
                                </div>
                                <span class="text-2xl font-black text-amber-400">{"$150"}<span class="text-xs text-zinc-500">{"/yr"}</span></span>
                            </div>
                            <ul class="text-xs text-zinc-300 space-y-2 mt-4">
                                <li class="flex items-center">{"✓ Uncapped backend rate limits"}</li>
                                <li class="flex items-center">{"✓ Priority compute & AI queue"}</li>
                                <li class="flex items-center">{"✓ VIP gatekeeper bypass"}</li>
                            </ul>
                        </div>
                    </div>

                    // Duration Selector
                    <div class="mt-8">
                        <h3 class="text-sm font-bold uppercase tracking-wider text-zinc-300 mb-3">{"2. Choose Subscription Duration"}</h3>
                        <div class="grid grid-cols-3 gap-3">
                            {
                                for [1, 2, 3].iter().map(|&yrs| {
                                    let years_count = years_count.clone();
                                    let is_selected = *years_count == yrs;
                                    html! {
                                        <button
                                            onclick={Callback::from(move |_| years_count.set(yrs))}
                                            class={classes!(
                                                "py-3", "rounded-xl", "text-xs", "font-bold", "border", "transition-all",
                                                if is_selected {
                                                    "bg-gradient-to-r from-cyan-600 to-indigo-600 border-cyan-400 text-white shadow-md shadow-cyan-500/30"
                                                } else {
                                                    "bg-zinc-900 border-zinc-800 text-zinc-400 hover:border-zinc-700"
                                                }
                                            )}
                                        >
                                            {format!("{} Year{}", yrs, if yrs > 1 { "s (+730d)" } else { " (365d)" })}
                                        </button>
                                    }
                                })
                            }
                        </div>
                    </div>

                    // Payment Method Tabs (XRP, RLUSD, USDC, Rafiki)
                    <div class="mt-8">
                        <h3 class="text-sm font-bold uppercase tracking-wider text-zinc-300 mb-3">{"3. Select Settlement Rail"}</h3>
                        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
                            <button
                                onclick={
                                    let payment_method = payment_method.clone();
                                    Callback::from(move |_| payment_method.set(PaymentMethod::XrpNative))
                                }
                                class={classes!(
                                    "p-4", "rounded-xl", "border", "text-center", "transition-all",
                                    if *payment_method == PaymentMethod::XrpNative {
                                        "bg-zinc-900 border-cyan-400 text-white ring-1 ring-cyan-400/30"
                                    } else {
                                        "bg-zinc-900/40 border-zinc-800 text-zinc-400"
                                    }
                                )}
                            >
                                <div class="font-extrabold text-sm text-white">{"XRP"}</div>
                                <div class="text-[10px] text-zinc-500">{"XRPL Native"}</div>
                            </button>

                            <button
                                onclick={
                                    let payment_method = payment_method.clone();
                                    Callback::from(move |_| payment_method.set(PaymentMethod::Rlusd))
                                }
                                class={classes!(
                                    "p-4", "rounded-xl", "border", "text-center", "transition-all",
                                    if *payment_method == PaymentMethod::Rlusd {
                                        "bg-zinc-900 border-sky-400 text-white ring-1 ring-sky-400/30"
                                    } else {
                                        "bg-zinc-900/40 border-zinc-800 text-zinc-400"
                                    }
                                )}
                            >
                                <div class="font-extrabold text-sm text-white">{"RLUSD"}</div>
                                <div class="text-[10px] text-zinc-500">{"Ripple USD"}</div>
                            </button>

                            <button
                                onclick={
                                    let payment_method = payment_method.clone();
                                    Callback::from(move |_| payment_method.set(PaymentMethod::Usdc))
                                }
                                class={classes!(
                                    "p-4", "rounded-xl", "border", "text-center", "transition-all",
                                    if *payment_method == PaymentMethod::Usdc {
                                        "bg-zinc-900 border-blue-500 text-white ring-1 ring-blue-500/30"
                                    } else {
                                        "bg-zinc-900/40 border-zinc-800 text-zinc-400"
                                    }
                                )}
                            >
                                <div class="font-extrabold text-sm text-white">{"USDC"}</div>
                                <div class="text-[10px] text-zinc-500">{"Stablecoin"}</div>
                            </button>

                            <button
                                onclick={
                                    let payment_method = payment_method.clone();
                                    Callback::from(move |_| payment_method.set(PaymentMethod::InterledgerRafiki))
                                }
                                class={classes!(
                                    "p-4", "rounded-xl", "border", "text-center", "transition-all",
                                    if *payment_method == PaymentMethod::InterledgerRafiki {
                                        "bg-zinc-900 border-purple-500 text-white ring-1 ring-purple-500/30"
                                    } else {
                                        "bg-zinc-900/40 border-zinc-800 text-zinc-400"
                                    }
                                )}
                            >
                                <div class="font-extrabold text-sm text-white">{"Rafiki / ILP"}</div>
                                <div class="text-[10px] text-zinc-500">{"Fiat / Multi-Rail"}</div>
                            </button>
                        </div>
                    </div>
                </div>

                // Right Col: Order Summary & Checkout Card
                <div class="lg:col-span-1">
                    <div class="sticky top-8 bg-zinc-900/90 border border-zinc-800 rounded-2xl p-6 shadow-2xl backdrop-blur-sm">
                        <h3 class="text-sm font-bold uppercase tracking-wider text-white mb-4">{"Gateway Summary"}</h3>

                        <div class="space-y-3 border-b border-zinc-800 pb-4 text-xs">
                            <div class="flex justify-between text-zinc-400">
                                <span>{"Credential"}</span>
                                <span class="text-white font-bold">{selected_tier.name()}</span>
                            </div>
                            <div class="flex justify-between text-zinc-400">
                                <span>{"Duration"}</span>
                                <span class="text-white font-bold">{format!("{} Year(s)", *years_count)}</span>
                            </div>
                            <div class="flex justify-between text-zinc-400">
                                <span>{"Settlement Rail"}</span>
                                <span class="text-cyan-400 font-bold">{
                                    match *payment_method {
                                        PaymentMethod::XrpNative => "XRP (Native)",
                                        PaymentMethod::Rlusd => "RLUSD (Ripple USD)",
                                        PaymentMethod::Usdc => "USDC (Direct)",
                                        PaymentMethod::InterledgerRafiki => "ILPv4 / Rafiki"
                                    }
                                }</span>
                            </div>
                            <div class="flex justify-between text-zinc-400">
                                <span>{"Standard"}</span>
                                <span class="text-emerald-400 font-bold">{"ERC-5192 (Soulbound)"}</span>
                            </div>
                        </div>

                        <div class="flex justify-between items-baseline py-4 mb-6">
                            <span class="text-xs uppercase font-bold text-zinc-400">{"Annual Total"}</span>
                            <div class="text-right">
                                <span class="text-3xl font-black text-white">{format!("${}.00", total_cost)}</span>
                                <span class="block text-[10px] text-zinc-500">{"Revoked on expiration"}</span>
                            </div>
                        </div>

                        // Action Button
                        if wallet_address.is_none() {
                            <button
                                onclick={on_connect}
                                class="w-full bg-cyan-500 hover:bg-cyan-400 text-zinc-950 font-bold rounded-xl py-3 text-xs uppercase tracking-wider transition-all shadow-lg shadow-cyan-500/20"
                            >
                                {"Connect Wallet to Authorize"}
                            </button>
                        } else {
                            <button
                                onclick={on_mint}
                                disabled={*is_processing}
                                class="w-full bg-gradient-to-r from-cyan-500 to-indigo-600 hover:from-cyan-400 hover:to-indigo-500 disabled:opacity-50 text-zinc-950 font-bold rounded-xl py-3 text-xs uppercase tracking-wider transition-all shadow-lg shadow-cyan-500/20 flex items-center justify-center space-x-2"
                            >
                                if *is_processing {
                                    <span>{"Broadcasting Transaction..."}</span>
                                } else {
                                    <span>{format!("Authorize & Mint {} Pass", selected_tier.name())}</span>
                                }
                            </button>
                        }

                        <p class="text-[10px] text-zinc-500 text-center mt-4">
                            {"Bound permanently to your minter address. Non-transferable & non-salable per ERC-5192 standard."}
                        </p>
                    </div>
                </div>
            </div>
        </div>
    }
}

fn main() {
    yew::Renderer::<App>::new().render();
}
