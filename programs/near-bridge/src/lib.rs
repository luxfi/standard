/// Lux Bridge — NEAR Protocol native bridge (Rust/WASM)
///
/// NEAR smart contracts compile to WASM and run on the NEAR runtime.
/// Token standard: NEP-141 (fungible tokens).
/// Ed25519 signature verification available natively.
use near_sdk::borsh::{BorshDeserialize, BorshSerialize};
use near_sdk::store::IterableMap;
use near_sdk::{env, near_bindgen, AccountId, NearToken, Promise, PanicOnDefault};
use near_sdk::serde::{Deserialize, Serialize};

const NEAR_CHAIN_ID: u64 = 1313161554; // "NEAR" as u64-ish (Aurora chain ID used as reference)
const MAX_FEE_BPS: u16 = 500;

#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
pub struct LuxBridge {
    admin: AccountId,
    mpc_signers: Vec<[u8; 32]>,
    threshold: u8,
    fee_bps: u16,
    paused: bool,
    outbound_nonce: u64,
    total_locked: u128,
    total_burned: u128,
    /// "source_chain:nonce" -> processed
    processed_nonces: IterableMap<String, bool>,
}

#[derive(Serialize, Deserialize)]
#[serde(crate = "near_sdk::serde")]
pub struct BridgeEvent {
    pub event_type: String,
    pub source_chain: u64,
    pub dest_chain: u64,
    pub nonce: u64,
    pub sender: String,
    pub recipient: String,
    pub amount: String,
}

#[near_bindgen]
impl LuxBridge {
    #[init]
    pub fn new(
        mpc_signers: Vec<Vec<u8>>,
        threshold: u8,
        fee_bps: u16,
    ) -> Self {
        assert!(fee_bps <= MAX_FEE_BPS, "Fee too high");
        let signers: Vec<[u8; 32]> = mpc_signers.iter().map(|s| {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(s);
            arr
        }).collect();

        Self {
            admin: env::predecessor_account_id(),
            mpc_signers: signers,
            threshold,
            fee_bps,
            paused: false,
            outbound_nonce: 0,
            total_locked: 0,
            total_burned: 0,
            processed_nonces: IterableMap::new(b"n"),
        }
    }

    /// Lock NEAR for bridging. Attach deposit to this call.
    #[payable]
    pub fn lock_and_bridge(&mut self, dest_chain_id: u64, recipient: String) -> u64 {
        assert!(!self.paused, "Bridge is paused");
        let amount = env::attached_deposit().as_yoctonear();
        assert!(amount > 0, "Zero amount");

        let fee = amount * self.fee_bps as u128 / 10_000;
        let bridge_amount = amount - fee;

        self.total_locked += bridge_amount;
        self.outbound_nonce += 1;
        let nonce = self.outbound_nonce;

        // Emit NEP-297 event for MPC watchers
        let event = BridgeEvent {
            event_type: "lock".to_string(),
            source_chain: NEAR_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            sender: env::predecessor_account_id().to_string(),
            recipient,
            amount: bridge_amount.to_string(),
        };
        env::log_str(&format!("EVENT_JSON:{}", near_sdk::serde_json::to_string(&event).unwrap()));

        nonce
    }

    /// Mint wrapped tokens with MPC Ed25519 signature.
    pub fn mint_bridged(
        &mut self,
        source_chain_id: u64,
        nonce: u64,
        recipient: AccountId,
        amount: u128,
        signature: Vec<u8>,
        signer_pubkey: Vec<u8>,
    ) {
        assert!(!self.paused, "Bridge is paused");
        assert!(amount > 0, "Zero amount");

        // Verify signer
        let mut pk = [0u8; 32];
        pk.copy_from_slice(&signer_pubkey);
        assert!(self.mpc_signers.contains(&pk), "Unauthorized signer");

        // Check nonce
        let nonce_key = format!("{}:{}", source_chain_id, nonce);
        assert!(!self.processed_nonces.get(&nonce_key).copied().unwrap_or(false), "Nonce processed");

        // Verify Ed25519 signature
        let message = self.build_mint_message(source_chain_id, nonce, &recipient, amount);
        let mut sig = [0u8; 64];
        sig.copy_from_slice(&signature);
        let valid = env::ed25519_verify(&sig, &message, &pk);
        assert!(valid, "Invalid signature");

        self.processed_nonces.insert(nonce_key, true);

        // Transfer NEAR to recipient
        Promise::new(recipient.clone()).transfer(NearToken::from_yoctonear(amount)).detach();

        let event = BridgeEvent {
            event_type: "mint".to_string(),
            source_chain: source_chain_id,
            dest_chain: NEAR_CHAIN_ID,
            nonce,
            sender: "bridge".to_string(),
            recipient: recipient.to_string(),
            amount: amount.to_string(),
        };
        env::log_str(&format!("EVENT_JSON:{}", near_sdk::serde_json::to_string(&event).unwrap()));
    }

    /// Burn wrapped tokens for withdrawal. Attach deposit.
    #[payable]
    pub fn burn_bridged(&mut self, dest_chain_id: u64, recipient: String) -> u64 {
        assert!(!self.paused, "Bridge is paused");
        let amount = env::attached_deposit().as_yoctonear();
        assert!(amount > 0, "Zero amount");

        self.total_burned += amount;
        self.outbound_nonce += 1;
        let nonce = self.outbound_nonce;

        let event = BridgeEvent {
            event_type: "burn".to_string(),
            source_chain: NEAR_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            sender: env::predecessor_account_id().to_string(),
            recipient,
            amount: amount.to_string(),
        };
        env::log_str(&format!("EVENT_JSON:{}", near_sdk::serde_json::to_string(&event).unwrap()));

        nonce
    }

    /// Release locked tokens with MPC signature.
    pub fn release(
        &mut self,
        source_chain_id: u64,
        nonce: u64,
        recipient: AccountId,
        amount: u128,
        signature: Vec<u8>,
        signer_pubkey: Vec<u8>,
    ) {
        assert!(!self.paused);
        let mut pk = [0u8; 32];
        pk.copy_from_slice(&signer_pubkey);
        assert!(self.mpc_signers.contains(&pk), "Unauthorized");

        let nonce_key = format!("{}:{}", source_chain_id, nonce);
        assert!(!self.processed_nonces.get(&nonce_key).copied().unwrap_or(false), "Nonce processed");

        let message = self.build_release_message(source_chain_id, nonce, &recipient, amount);
        let mut sig = [0u8; 64];
        sig.copy_from_slice(&signature);
        assert!(env::ed25519_verify(&sig, &message, &pk), "Invalid sig");

        self.processed_nonces.insert(nonce_key, true);
        Promise::new(recipient).transfer(NearToken::from_yoctonear(amount)).detach();
    }

    // Admin
    pub fn pause(&mut self) { self.assert_admin(); self.paused = true; }
    pub fn unpause(&mut self) { self.assert_admin(); self.paused = false; }
    pub fn set_signers(&mut self, signers: Vec<Vec<u8>>, threshold: u8) {
        self.assert_admin();
        self.mpc_signers = signers.iter().map(|s| { let mut a = [0u8; 32]; a.copy_from_slice(s); a }).collect();
        self.threshold = threshold;
    }
    pub fn set_fee(&mut self, fee_bps: u16) {
        self.assert_admin();
        assert!(fee_bps <= MAX_FEE_BPS);
        self.fee_bps = fee_bps;
    }

    // Views
    pub fn total_locked(&self) -> String { self.total_locked.to_string() }
    pub fn total_burned(&self) -> String { self.total_burned.to_string() }
    pub fn is_paused(&self) -> bool { self.paused }

    // Internal
    fn assert_admin(&self) { assert_eq!(env::predecessor_account_id(), self.admin, "Not admin"); }

    fn build_mint_message(&self, chain_id: u64, nonce: u64, recipient: &AccountId, amount: u128) -> Vec<u8> {
        let mut msg = b"LUX_BRIDGE_MINT".to_vec();
        msg.extend_from_slice(&chain_id.to_le_bytes());
        msg.extend_from_slice(&nonce.to_le_bytes());
        msg.extend_from_slice(recipient.as_str().as_bytes());
        msg.extend_from_slice(&amount.to_le_bytes());
        msg
    }

    fn build_release_message(&self, chain_id: u64, nonce: u64, recipient: &AccountId, amount: u128) -> Vec<u8> {
        let mut msg = b"LUX_BRIDGE_RELEASE".to_vec();
        msg.extend_from_slice(&chain_id.to_le_bytes());
        msg.extend_from_slice(&nonce.to_le_bytes());
        msg.extend_from_slice(recipient.as_str().as_bytes());
        msg.extend_from_slice(&amount.to_le_bytes());
        msg
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::VMContextBuilder;
    use near_sdk::testing_env;

    fn admin() -> AccountId {
        "admin.near".parse().unwrap()
    }

    fn user() -> AccountId {
        "user.near".parse().unwrap()
    }

    fn recipient() -> AccountId {
        "recipient.near".parse().unwrap()
    }

    fn signer_key() -> Vec<u8> {
        vec![1u8; 32]
    }

    fn setup_context(predecessor: &AccountId, deposit_yocto: u128) {
        let ctx = VMContextBuilder::new()
            .predecessor_account_id(predecessor.clone())
            .attached_deposit(NearToken::from_yoctonear(deposit_yocto))
            .build();
        testing_env!(ctx);
    }

    fn new_bridge() -> LuxBridge {
        setup_context(&admin(), 0);
        LuxBridge::new(vec![signer_key()], 1, 100)
    }

    // 1. initialize -- sets admin, signers, threshold, fee_bps
    #[test]
    fn test_initialize() {
        let bridge = new_bridge();

        assert_eq!(bridge.admin, admin());
        assert_eq!(bridge.mpc_signers.len(), 1);
        assert_eq!(bridge.mpc_signers[0], [1u8; 32]);
        assert_eq!(bridge.threshold, 1);
        assert_eq!(bridge.fee_bps, 100);
        assert!(!bridge.paused);
        assert_eq!(bridge.outbound_nonce, 0);
        assert_eq!(bridge.total_locked, 0);
        assert_eq!(bridge.total_burned, 0);
    }

    #[test]
    #[should_panic(expected = "Fee too high")]
    fn test_initialize_rejects_high_fee() {
        setup_context(&admin(), 0);
        LuxBridge::new(vec![signer_key()], 1, 501);
    }

    // 2. lock_and_bridge -- transfers tokens, increments nonce
    #[test]
    fn test_lock_and_bridge() {
        let mut bridge = new_bridge();

        setup_context(&user(), 1_000_000);
        let nonce = bridge.lock_and_bridge(96369, "0xdead".to_string());

        assert_eq!(nonce, 1);
        assert_eq!(bridge.outbound_nonce, 1);
        // fee = 1_000_000 * 100 / 10_000 = 10_000
        // bridge_amount = 1_000_000 - 10_000 = 990_000
        assert_eq!(bridge.total_locked, 990_000);
    }

    #[test]
    fn test_lock_and_bridge_increments_nonce() {
        let mut bridge = new_bridge();

        setup_context(&user(), 500);
        let n1 = bridge.lock_and_bridge(96369, "0xaaa".to_string());

        setup_context(&user(), 500);
        let n2 = bridge.lock_and_bridge(96369, "0xbbb".to_string());

        assert_eq!(n1, 1);
        assert_eq!(n2, 2);
        assert_eq!(bridge.outbound_nonce, 2);
    }

    #[test]
    #[should_panic(expected = "Zero amount")]
    fn test_lock_and_bridge_rejects_zero() {
        let mut bridge = new_bridge();
        setup_context(&user(), 0);
        bridge.lock_and_bridge(96369, "0xdead".to_string());
    }

    #[test]
    #[should_panic(expected = "Bridge is paused")]
    fn test_lock_and_bridge_rejects_when_paused() {
        let mut bridge = new_bridge();

        setup_context(&admin(), 0);
        bridge.pause();

        setup_context(&user(), 1_000);
        bridge.lock_and_bridge(96369, "0xdead".to_string());
    }

    // 3. mint_bridged -- verifies ed25519 signature via env, mints
    #[test]
    #[should_panic(expected = "Unauthorized signer")]
    fn test_mint_bridged_rejects_unknown_signer() {
        let mut bridge = new_bridge();
        let bad_key = vec![99u8; 32];

        setup_context(&user(), 0);
        bridge.mint_bridged(96369, 1, recipient(), 1000, vec![0u8; 64], bad_key);
    }

    #[test]
    #[should_panic(expected = "Zero amount")]
    fn test_mint_bridged_rejects_zero_amount() {
        let mut bridge = new_bridge();

        setup_context(&user(), 0);
        bridge.mint_bridged(96369, 1, recipient(), 0, vec![0u8; 64], signer_key());
    }

    #[test]
    #[should_panic(expected = "Bridge is paused")]
    fn test_mint_bridged_rejects_when_paused() {
        let mut bridge = new_bridge();

        setup_context(&admin(), 0);
        bridge.pause();

        setup_context(&user(), 0);
        bridge.mint_bridged(96369, 1, recipient(), 1000, vec![0u8; 64], signer_key());
    }

    // 4. burn_bridged -- burns tokens
    #[test]
    fn test_burn_bridged() {
        let mut bridge = new_bridge();

        setup_context(&user(), 500_000);
        let nonce = bridge.burn_bridged(96369, "0xdead".to_string());

        assert_eq!(nonce, 1);
        assert_eq!(bridge.total_burned, 500_000);
        assert_eq!(bridge.outbound_nonce, 1);
    }

    #[test]
    #[should_panic(expected = "Zero amount")]
    fn test_burn_bridged_rejects_zero() {
        let mut bridge = new_bridge();
        setup_context(&user(), 0);
        bridge.burn_bridged(96369, "0xdead".to_string());
    }

    // 5. pause/unpause -- admin toggles
    #[test]
    fn test_pause_unpause() {
        let mut bridge = new_bridge();

        assert!(!bridge.is_paused());

        setup_context(&admin(), 0);
        bridge.pause();
        assert!(bridge.is_paused());

        setup_context(&admin(), 0);
        bridge.unpause();
        assert!(!bridge.is_paused());
    }

    // 6. unauthorized -- non-admin rejected
    #[test]
    #[should_panic(expected = "Not admin")]
    fn test_pause_rejects_non_admin() {
        let mut bridge = new_bridge();
        setup_context(&user(), 0);
        bridge.pause();
    }

    #[test]
    #[should_panic(expected = "Not admin")]
    fn test_unpause_rejects_non_admin() {
        let mut bridge = new_bridge();

        setup_context(&admin(), 0);
        bridge.pause();

        setup_context(&user(), 0);
        bridge.unpause();
    }

    #[test]
    #[should_panic(expected = "Not admin")]
    fn test_set_signers_rejects_non_admin() {
        let mut bridge = new_bridge();
        setup_context(&user(), 0);
        bridge.set_signers(vec![vec![2u8; 32]], 1);
    }

    #[test]
    #[should_panic(expected = "Not admin")]
    fn test_set_fee_rejects_non_admin() {
        let mut bridge = new_bridge();
        setup_context(&user(), 0);
        bridge.set_fee(50);
    }

    // 7. nonce replay -- same nonce rejected
    #[test]
    #[should_panic(expected = "Nonce processed")]
    fn test_nonce_replay_rejected() {
        let mut bridge = new_bridge();
        let nonce_key = format!("{}:{}", 96369u64, 1u64);

        // Simulate a processed nonce by inserting directly
        bridge.processed_nonces.insert(nonce_key, true);

        setup_context(&user(), 0);
        bridge.mint_bridged(96369, 1, recipient(), 1000, vec![0u8; 64], signer_key());
    }

    // View functions
    #[test]
    fn test_view_functions() {
        let mut bridge = new_bridge();

        assert_eq!(bridge.total_locked(), "0");
        assert_eq!(bridge.total_burned(), "0");

        setup_context(&user(), 1_000);
        bridge.lock_and_bridge(96369, "0xdead".to_string());

        // locked = 1000 - (1000 * 100 / 10000) = 1000 - 10 = 990
        assert_eq!(bridge.total_locked(), "990");

        setup_context(&user(), 2_000);
        bridge.burn_bridged(96369, "0xdead".to_string());
        assert_eq!(bridge.total_burned(), "2000");
    }

    // Admin can update signers and fee
    #[test]
    fn test_set_signers() {
        let mut bridge = new_bridge();
        let new_key = vec![42u8; 32];

        setup_context(&admin(), 0);
        bridge.set_signers(vec![new_key.clone()], 2);

        assert_eq!(bridge.mpc_signers.len(), 1);
        assert_eq!(bridge.mpc_signers[0], [42u8; 32]);
        assert_eq!(bridge.threshold, 2);
    }

    #[test]
    fn test_set_fee() {
        let mut bridge = new_bridge();

        setup_context(&admin(), 0);
        bridge.set_fee(250);
        assert_eq!(bridge.fee_bps, 250);
    }

    #[test]
    #[should_panic]
    fn test_set_fee_rejects_above_max() {
        let mut bridge = new_bridge();
        setup_context(&admin(), 0);
        bridge.set_fee(501);
    }
}
