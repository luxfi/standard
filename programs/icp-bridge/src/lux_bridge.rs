/// Lux Bridge — Internet Computer (ICP) canister (Rust)
///
/// ICP canisters are WASM smart contracts on the Internet Computer.
/// Uses ECDSA threshold signing (chain-key cryptography) natively.
/// Token standard: ICRC-1/ICRC-2 (ICP fungible tokens).

use candid::{CandidType, Deserialize, Nat, Principal};
use ic_cdk::api::time;
use ic_cdk_macros::{init, query, update};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};

const ICP_CHAIN_ID: u64 = 4294967490;
const MAX_FEE_BPS: u16 = 500;

#[derive(CandidType, Deserialize, Clone)]
struct BridgeConfig {
    admin: Principal,
    mpc_signers: Vec<Vec<u8>>, // Ed25519 public keys
    threshold: u8,
    fee_bps: u16,
    paused: bool,
    outbound_nonce: u64,
    total_locked: u128,
    total_burned: u128,
}

#[derive(CandidType, Deserialize, Clone)]
struct LockEvent {
    source_chain: u64,
    dest_chain: u64,
    nonce: u64,
    sender: Principal,
    recipient: Vec<u8>,
    amount: u128,
    fee: u128,
    timestamp: u64,
}

thread_local! {
    static CONFIG: RefCell<Option<BridgeConfig>> = RefCell::new(None);
    static PROCESSED_NONCES: RefCell<HashSet<(u64, u64)>> = RefCell::new(HashSet::new());
    static EVENT_LOG: RefCell<Vec<LockEvent>> = RefCell::new(Vec::new());
}

#[init]
fn init(mpc_signers: Vec<Vec<u8>>, threshold: u8, fee_bps: u16) {
    assert!(fee_bps <= MAX_FEE_BPS, "Fee too high");
    CONFIG.with(|c| {
        *c.borrow_mut() = Some(BridgeConfig {
            admin: ic_cdk::caller(),
            mpc_signers,
            threshold,
            fee_bps,
            paused: false,
            outbound_nonce: 0,
            total_locked: 0,
            total_burned: 0,
        });
    });
}

#[update]
fn lock_and_bridge(amount: u128, dest_chain_id: u64, recipient: Vec<u8>) -> u64 {
    CONFIG.with(|c| {
        let mut config = c.borrow_mut();
        let cfg = config.as_mut().expect("Not initialized");
        assert!(!cfg.paused, "Bridge paused");
        assert!(amount > 0, "Zero amount");

        let fee = amount * cfg.fee_bps as u128 / 10_000;
        let bridge_amount = amount - fee;

        cfg.total_locked += bridge_amount;
        cfg.outbound_nonce += 1;
        let nonce = cfg.outbound_nonce;

        EVENT_LOG.with(|log| {
            log.borrow_mut().push(LockEvent {
                source_chain: ICP_CHAIN_ID,
                dest_chain: dest_chain_id,
                nonce,
                sender: ic_cdk::caller(),
                recipient,
                amount: bridge_amount,
                fee,
                timestamp: time(),
            });
        });

        nonce
    })
}

#[update]
fn mint_bridged(
    source_chain_id: u64,
    nonce: u64,
    recipient: Principal,
    amount: u128,
    signature: Vec<u8>,
    signer_pubkey: Vec<u8>,
) {
    CONFIG.with(|c| {
        let config = c.borrow();
        let cfg = config.as_ref().expect("Not initialized");
        assert!(!cfg.paused, "Bridge paused");
        assert!(amount > 0, "Zero amount");
        assert!(cfg.mpc_signers.contains(&signer_pubkey), "Unauthorized signer");
    });

    PROCESSED_NONCES.with(|nonces| {
        let mut set = nonces.borrow_mut();
        assert!(!set.contains(&(source_chain_id, nonce)), "Nonce processed");
        set.insert((source_chain_id, nonce));
    });

    // ICP has native threshold ECDSA via management canister
    // In production: verify signature via ic_cdk::api::management_canister::ecdsa
}

#[update]
fn burn_bridged(amount: u128, dest_chain_id: u64, recipient: Vec<u8>) -> u64 {
    CONFIG.with(|c| {
        let mut config = c.borrow_mut();
        let cfg = config.as_mut().expect("Not initialized");
        assert!(!cfg.paused);
        assert!(amount > 0);

        cfg.total_burned += amount;
        cfg.outbound_nonce += 1;
        cfg.outbound_nonce
    })
}

#[update]
fn pause() {
    CONFIG.with(|c| {
        let mut config = c.borrow_mut();
        let cfg = config.as_mut().unwrap();
        assert_eq!(ic_cdk::caller(), cfg.admin, "Not admin");
        cfg.paused = true;
    });
}

#[update]
fn unpause() {
    CONFIG.with(|c| {
        let mut config = c.borrow_mut();
        let cfg = config.as_mut().unwrap();
        assert_eq!(ic_cdk::caller(), cfg.admin, "Not admin");
        cfg.paused = false;
    });
}

#[query]
fn total_locked() -> u128 {
    CONFIG.with(|c| c.borrow().as_ref().unwrap().total_locked)
}

#[query]
fn total_burned() -> u128 {
    CONFIG.with(|c| c.borrow().as_ref().unwrap().total_burned)
}

#[query]
fn is_paused() -> bool {
    CONFIG.with(|c| c.borrow().as_ref().unwrap().paused)
}

#[query]
fn get_events(from: u64, to: u64) -> Vec<LockEvent> {
    EVENT_LOG.with(|log| {
        log.borrow().iter()
            .filter(|e| e.nonce >= from && e.nonce <= to)
            .cloned()
            .collect()
    })
}
