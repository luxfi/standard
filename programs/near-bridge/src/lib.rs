/// Lux Bridge — NEAR Protocol native bridge (Rust/WASM)
///
/// NEAR smart contracts compile to WASM and run on the NEAR runtime.
/// Token standard: NEP-141 (fungible tokens).
/// Ed25519 signature verification available natively.
use near_sdk::borsh::{BorshDeserialize, BorshSerialize};
use near_sdk::collections::UnorderedMap;
use near_sdk::{env, near_bindgen, AccountId, Balance, Promise, PanicOnDefault};
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
    total_locked: Balance,
    total_burned: Balance,
    /// "source_chain:nonce" -> processed
    processed_nonces: UnorderedMap<String, bool>,
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
            processed_nonces: UnorderedMap::new(b"n"),
        }
    }

    /// Lock NEAR for bridging. Attach deposit to this call.
    #[payable]
    pub fn lock_and_bridge(&mut self, dest_chain_id: u64, recipient: String) -> u64 {
        assert!(!self.paused, "Bridge is paused");
        let amount = env::attached_deposit();
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
        amount: Balance,
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
        assert!(!self.processed_nonces.get(&nonce_key).unwrap_or(false), "Nonce processed");

        // Verify Ed25519 signature
        let message = self.build_mint_message(source_chain_id, nonce, &recipient, amount);
        let valid = env::ed25519_verify(&signature, &message, &signer_pubkey);
        assert!(valid, "Invalid signature");

        self.processed_nonces.insert(&nonce_key, &true);

        // Transfer NEAR to recipient
        Promise::new(recipient.clone()).transfer(amount);

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
        let amount = env::attached_deposit();
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
        amount: Balance,
        signature: Vec<u8>,
        signer_pubkey: Vec<u8>,
    ) {
        assert!(!self.paused);
        let mut pk = [0u8; 32];
        pk.copy_from_slice(&signer_pubkey);
        assert!(self.mpc_signers.contains(&pk), "Unauthorized");

        let nonce_key = format!("{}:{}", source_chain_id, nonce);
        assert!(!self.processed_nonces.get(&nonce_key).unwrap_or(false), "Nonce processed");

        let message = self.build_release_message(source_chain_id, nonce, &recipient, amount);
        assert!(env::ed25519_verify(&signature, &message, &signer_pubkey), "Invalid sig");

        self.processed_nonces.insert(&nonce_key, &true);
        Promise::new(recipient).transfer(amount);
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

    fn build_mint_message(&self, chain_id: u64, nonce: u64, recipient: &AccountId, amount: Balance) -> Vec<u8> {
        let mut msg = b"LUX_BRIDGE_MINT".to_vec();
        msg.extend_from_slice(&chain_id.to_le_bytes());
        msg.extend_from_slice(&nonce.to_le_bytes());
        msg.extend_from_slice(recipient.as_str().as_bytes());
        msg.extend_from_slice(&amount.to_le_bytes());
        msg
    }

    fn build_release_message(&self, chain_id: u64, nonce: u64, recipient: &AccountId, amount: Balance) -> Vec<u8> {
        let mut msg = b"LUX_BRIDGE_RELEASE".to_vec();
        msg.extend_from_slice(&chain_id.to_le_bytes());
        msg.extend_from_slice(&nonce.to_le_bytes());
        msg.extend_from_slice(recipient.as_str().as_bytes());
        msg.extend_from_slice(&amount.to_le_bytes());
        msg
    }
}
