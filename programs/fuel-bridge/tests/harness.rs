use fuels::prelude::*;
use fuels::types::{Bits256, Identity};

abigen!(Contract(
    name = "LuxBridge",
    abi = "out/debug/fuel-bridge-abi.json"
));

const MAX_FEE_BPS: u16 = 500;

async fn setup() -> (LuxBridge<WalletUnlocked>, WalletUnlocked, WalletUnlocked) {
    let num_wallets = 3;
    let coins_per_wallet = 1;
    let coin_amount = 1_000_000_000;

    let config = WalletsConfig::new(Some(num_wallets), Some(coins_per_wallet), Some(coin_amount));
    let wallets = launch_custom_provider_and_get_wallets(config, None, None).await.unwrap();

    let admin_wallet = wallets[0].clone();
    let user_wallet = wallets[1].clone();

    let contract_id = Contract::load_from(
        "./out/debug/fuel-bridge.bin",
        LoadConfiguration::default(),
    )
    .unwrap()
    .deploy(&admin_wallet, TxPolicies::default())
    .await
    .unwrap();

    let bridge = LuxBridge::new(contract_id.clone(), admin_wallet.clone());

    (bridge, admin_wallet, user_wallet)
}

fn test_signer() -> Bits256 {
    Bits256([0xAA; 32])
}

fn zero_signer() -> Bits256 {
    Bits256([0x00; 32])
}

fn test_recipient() -> Bits256 {
    Bits256([0xBB; 32])
}

// ================================================================
// Initialize
// ================================================================

#[tokio::test]
async fn test_initialize_succeeds() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();
}

#[tokio::test]
#[should_panic(expected = "Fee too high")]
async fn test_initialize_rejects_high_fee() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), MAX_FEE_BPS + 1)
        .call()
        .await
        .unwrap();
}

#[tokio::test]
async fn test_initialize_accepts_max_fee() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), MAX_FEE_BPS)
        .call()
        .await
        .unwrap();
}

// ================================================================
// Pause / Unpause
// ================================================================

#[tokio::test]
async fn test_pause_by_admin() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge.methods().pause().call().await.unwrap();

    let paused = bridge.methods().is_paused().call().await.unwrap().value;
    assert!(paused, "Bridge should be paused");
}

#[tokio::test]
async fn test_unpause_by_admin() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge.methods().pause().call().await.unwrap();
    bridge.methods().unpause().call().await.unwrap();

    let paused = bridge.methods().is_paused().call().await.unwrap().value;
    assert!(!paused, "Bridge should not be paused");
}

#[tokio::test]
#[should_panic(expected = "Not admin")]
async fn test_pause_by_non_admin_fails() {
    let (bridge, _admin, user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    // Call pause from user wallet (not admin)
    let user_bridge = LuxBridge::new(bridge.contract_id().clone(), user.clone());
    user_bridge.methods().pause().call().await.unwrap();
}

// ================================================================
// Lock and Bridge
// ================================================================

#[tokio::test]
async fn test_lock_and_bridge_returns_nonce() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    let nonce = bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(1000))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(nonce, 1u64, "First nonce should be 1");
}

#[tokio::test]
async fn test_lock_and_bridge_increments_nonce() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 0)
        .call()
        .await
        .unwrap();

    let n1 = bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(1000))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    let n2 = bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(2000))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(n1, 1u64);
    assert_eq!(n2, 2u64);
}

#[tokio::test]
async fn test_lock_and_bridge_updates_total_locked() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 0) // 0 fee
        .call()
        .await
        .unwrap();

    bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(5000))
        .unwrap()
        .call()
        .await
        .unwrap();

    let locked = bridge.methods().total_locked().call().await.unwrap().value;
    assert_eq!(locked, 5000u64, "Total locked should be 5000");
}

#[tokio::test]
#[should_panic(expected = "Zero amount")]
async fn test_lock_and_bridge_rejects_zero_amount() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(0))
        .unwrap()
        .call()
        .await
        .unwrap();
}

#[tokio::test]
#[should_panic(expected = "Paused")]
async fn test_lock_and_bridge_rejects_when_paused() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge.methods().pause().call().await.unwrap();

    bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(1000))
        .unwrap()
        .call()
        .await
        .unwrap();
}

// ================================================================
// Burn Bridged
// ================================================================

#[tokio::test]
async fn test_burn_bridged_returns_nonce() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    let nonce = bridge
        .methods()
        .burn_bridged(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(500))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(nonce, 1u64, "Burn nonce should be 1");
}

#[tokio::test]
async fn test_burn_bridged_updates_total_burned() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge
        .methods()
        .burn_bridged(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(500))
        .unwrap()
        .call()
        .await
        .unwrap();

    let burned = bridge.methods().total_burned().call().await.unwrap().value;
    assert_eq!(burned, 500u64, "Total burned should be 500");
}

#[tokio::test]
#[should_panic(expected = "Zero")]
async fn test_burn_bridged_rejects_zero() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge
        .methods()
        .burn_bridged(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(0))
        .unwrap()
        .call()
        .await
        .unwrap();
}

#[tokio::test]
#[should_panic(expected = "Paused")]
async fn test_burn_bridged_rejects_when_paused() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    bridge.methods().pause().call().await.unwrap();

    bridge
        .methods()
        .burn_bridged(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(500))
        .unwrap()
        .call()
        .await
        .unwrap();
}

// ================================================================
// View functions
// ================================================================

#[tokio::test]
async fn test_initial_totals_are_zero() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 30)
        .call()
        .await
        .unwrap();

    let locked = bridge.methods().total_locked().call().await.unwrap().value;
    let burned = bridge.methods().total_burned().call().await.unwrap().value;
    let paused = bridge.methods().is_paused().call().await.unwrap().value;

    assert_eq!(locked, 0u64);
    assert_eq!(burned, 0u64);
    assert!(!paused);
}

// ================================================================
// Nonce sharing between lock and burn
// ================================================================

#[tokio::test]
async fn test_lock_and_burn_share_nonce_counter() {
    let (bridge, _admin, _user) = setup().await;

    bridge
        .methods()
        .initialize(test_signer(), test_signer(), test_signer(), 0)
        .call()
        .await
        .unwrap();

    let n1 = bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(1000))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    let n2 = bridge
        .methods()
        .burn_bridged(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(500))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    let n3 = bridge
        .methods()
        .lock_and_bridge(96369u64, test_recipient())
        .call_params(CallParameters::default().with_amount(2000))
        .unwrap()
        .call()
        .await
        .unwrap()
        .value;

    assert_eq!(n1, 1u64);
    assert_eq!(n2, 2u64);
    assert_eq!(n3, 3u64);
}
