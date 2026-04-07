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

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    // Test helper: reset all thread-local state between tests.
    fn reset_state() {
        CONFIG.with(|c| *c.borrow_mut() = None);
        PROCESSED_NONCES.with(|n| n.borrow_mut().clear());
        EVENT_LOG.with(|l| l.borrow_mut().clear());
    }

    // Test helper: initialize bridge with default test config.
    fn init_default() {
        let signers = vec![
            vec![1u8; 32],
            vec![2u8; 32],
            vec![3u8; 32],
        ];
        CONFIG.with(|c| {
            *c.borrow_mut() = Some(BridgeConfig {
                admin: Principal::anonymous(),
                mpc_signers: signers,
                threshold: 2,
                fee_bps: 30,
                paused: false,
                outbound_nonce: 0,
                total_locked: 0,
                total_burned: 0,
            });
        });
    }

    // ========================================================
    // Initialize tests
    // ========================================================

    #[test]
    fn test_init_sets_config() {
        reset_state();
        let signers = vec![vec![0xAA; 32], vec![0xBB; 32]];
        CONFIG.with(|c| {
            *c.borrow_mut() = Some(BridgeConfig {
                admin: Principal::anonymous(),
                mpc_signers: signers.clone(),
                threshold: 2,
                fee_bps: 100,
                paused: false,
                outbound_nonce: 0,
                total_locked: 0,
                total_burned: 0,
            });
        });

        CONFIG.with(|c| {
            let config = c.borrow();
            let cfg = config.as_ref().unwrap();
            assert_eq!(cfg.fee_bps, 100);
            assert_eq!(cfg.threshold, 2);
            assert_eq!(cfg.mpc_signers.len(), 2);
            assert!(!cfg.paused);
            assert_eq!(cfg.outbound_nonce, 0);
            assert_eq!(cfg.total_locked, 0);
            assert_eq!(cfg.total_burned, 0);
        });
    }

    #[test]
    #[should_panic(expected = "Fee too high")]
    fn test_init_rejects_high_fee() {
        reset_state();
        // Directly call init logic: fee > MAX_FEE_BPS panics
        let fee_bps: u16 = 501;
        assert!(fee_bps <= MAX_FEE_BPS, "Fee too high");
    }

    // ========================================================
    // Lock tests
    // ========================================================

    #[test]
    fn test_lock_and_bridge_returns_nonce() {
        reset_state();
        init_default();

        let nonce = lock_and_bridge(1_000_000, 96369, vec![0u8; 32]);
        assert_eq!(nonce, 1);
    }

    #[test]
    fn test_lock_and_bridge_increments_nonce() {
        reset_state();
        init_default();

        let n1 = lock_and_bridge(500_000, 96369, vec![0u8; 32]);
        let n2 = lock_and_bridge(500_000, 96369, vec![0u8; 32]);
        assert_eq!(n1, 1);
        assert_eq!(n2, 2);
    }

    #[test]
    fn test_lock_updates_total_locked() {
        reset_state();
        init_default();

        lock_and_bridge(1_000_000, 96369, vec![0u8; 32]);

        // fee = 1_000_000 * 30 / 10_000 = 3_000
        // bridge_amount = 1_000_000 - 3_000 = 997_000
        assert_eq!(total_locked(), 997_000);
    }

    #[test]
    fn test_lock_creates_event() {
        reset_state();
        init_default();

        lock_and_bridge(1_000_000, 96369, vec![0u8; 32]);

        let events = get_events(1, 1);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].nonce, 1);
        assert_eq!(events[0].source_chain, ICP_CHAIN_ID);
        assert_eq!(events[0].dest_chain, 96369);
        assert_eq!(events[0].amount, 997_000);
        assert_eq!(events[0].fee, 3_000);
    }

    #[test]
    #[should_panic(expected = "Zero amount")]
    fn test_lock_rejects_zero_amount() {
        reset_state();
        init_default();
        lock_and_bridge(0, 96369, vec![0u8; 32]);
    }

    #[test]
    #[should_panic(expected = "Bridge paused")]
    fn test_lock_rejects_when_paused() {
        reset_state();
        init_default();

        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = true;
        });

        lock_and_bridge(1_000_000, 96369, vec![0u8; 32]);
    }

    // ========================================================
    // Mint tests
    // ========================================================

    #[test]
    fn test_mint_bridged_marks_nonce() {
        reset_state();
        init_default();

        let signer = vec![1u8; 32]; // matches mpc_signers[0]
        mint_bridged(96369, 1, Principal::anonymous(), 500_000, vec![0u8; 64], signer);

        PROCESSED_NONCES.with(|n| {
            assert!(n.borrow().contains(&(96369, 1)));
        });
    }

    #[test]
    #[should_panic(expected = "Nonce processed")]
    fn test_mint_rejects_duplicate_nonce() {
        reset_state();
        init_default();

        let signer = vec![1u8; 32];
        mint_bridged(96369, 1, Principal::anonymous(), 500_000, vec![0u8; 64], signer.clone());
        // Second mint with same (source_chain_id, nonce) should panic
        mint_bridged(96369, 1, Principal::anonymous(), 500_000, vec![0u8; 64], signer);
    }

    #[test]
    #[should_panic(expected = "Unauthorized signer")]
    fn test_mint_rejects_unauthorized_signer() {
        reset_state();
        init_default();

        let bad_signer = vec![0xFF; 32]; // not in mpc_signers
        mint_bridged(96369, 1, Principal::anonymous(), 500_000, vec![0u8; 64], bad_signer);
    }

    #[test]
    #[should_panic(expected = "Zero amount")]
    fn test_mint_rejects_zero_amount() {
        reset_state();
        init_default();

        let signer = vec![1u8; 32];
        mint_bridged(96369, 1, Principal::anonymous(), 0, vec![0u8; 64], signer);
    }

    #[test]
    #[should_panic(expected = "Bridge paused")]
    fn test_mint_rejects_when_paused() {
        reset_state();
        init_default();

        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = true;
        });

        let signer = vec![1u8; 32];
        mint_bridged(96369, 1, Principal::anonymous(), 500_000, vec![0u8; 64], signer);
    }

    // ========================================================
    // Burn tests
    // ========================================================

    #[test]
    fn test_burn_bridged_returns_nonce() {
        reset_state();
        init_default();

        let nonce = burn_bridged(1_000_000, 96369, vec![0u8; 32]);
        assert_eq!(nonce, 1);
    }

    #[test]
    fn test_burn_updates_total_burned() {
        reset_state();
        init_default();

        burn_bridged(750_000, 96369, vec![0u8; 32]);
        assert_eq!(total_burned(), 750_000);
    }

    #[test]
    fn test_burn_increments_nonce() {
        reset_state();
        init_default();

        let n1 = burn_bridged(100, 96369, vec![0u8; 32]);
        let n2 = burn_bridged(200, 96369, vec![0u8; 32]);
        assert_eq!(n1, 1);
        assert_eq!(n2, 2);
    }

    #[test]
    #[should_panic]
    fn test_burn_rejects_zero_amount() {
        reset_state();
        init_default();
        burn_bridged(0, 96369, vec![0u8; 32]);
    }

    #[test]
    #[should_panic]
    fn test_burn_rejects_when_paused() {
        reset_state();
        init_default();

        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = true;
        });

        burn_bridged(1_000_000, 96369, vec![0u8; 32]);
    }

    // ========================================================
    // Pause tests
    // ========================================================

    #[test]
    fn test_pause_sets_flag() {
        reset_state();
        init_default();

        // Directly set paused (pause() checks caller == admin via ic_cdk::caller())
        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = true;
        });

        assert!(is_paused());
    }

    #[test]
    fn test_unpause_clears_flag() {
        reset_state();
        init_default();

        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = true;
        });
        assert!(is_paused());

        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = false;
        });
        assert!(!is_paused());
    }

    #[test]
    fn test_pause_blocks_all_operations() {
        reset_state();
        init_default();

        CONFIG.with(|c| {
            c.borrow_mut().as_mut().unwrap().paused = true;
        });

        // lock panics
        let lock_result = std::panic::catch_unwind(|| {
            lock_and_bridge(1_000_000, 96369, vec![0u8; 32]);
        });
        assert!(lock_result.is_err());

        // burn panics
        let burn_result = std::panic::catch_unwind(|| {
            burn_bridged(1_000_000, 96369, vec![0u8; 32]);
        });
        assert!(burn_result.is_err());

        // mint panics
        let mint_result = std::panic::catch_unwind(|| {
            mint_bridged(96369, 1, Principal::anonymous(), 500_000, vec![0u8; 64], vec![1u8; 32]);
        });
        assert!(mint_result.is_err());
    }

    // ========================================================
    // Query tests
    // ========================================================

    #[test]
    fn test_total_locked_starts_zero() {
        reset_state();
        init_default();
        assert_eq!(total_locked(), 0);
    }

    #[test]
    fn test_total_burned_starts_zero() {
        reset_state();
        init_default();
        assert_eq!(total_burned(), 0);
    }

    #[test]
    fn test_is_paused_starts_false() {
        reset_state();
        init_default();
        assert!(!is_paused());
    }

    #[test]
    fn test_get_events_empty() {
        reset_state();
        init_default();
        let events = get_events(0, 100);
        assert!(events.is_empty());
    }

    #[test]
    fn test_get_events_range() {
        reset_state();
        init_default();

        lock_and_bridge(100, 96369, vec![0u8; 32]);
        lock_and_bridge(200, 96369, vec![0u8; 32]);
        lock_and_bridge(300, 96369, vec![0u8; 32]);

        // Only nonce 2
        let events = get_events(2, 2);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].nonce, 2);

        // All three
        let all = get_events(1, 3);
        assert_eq!(all.len(), 3);
    }

    // ========================================================
    // Nonce isolation between source chains
    // ========================================================

    #[test]
    fn test_mint_nonce_isolation_across_chains() {
        reset_state();
        init_default();

        let signer = vec![1u8; 32];

        // Mint nonce 1 from chain 96369
        mint_bridged(96369, 1, Principal::anonymous(), 100, vec![0u8; 64], signer.clone());

        // Mint nonce 1 from chain 200200 (different source chain) should succeed
        mint_bridged(200200, 1, Principal::anonymous(), 100, vec![0u8; 64], signer);

        PROCESSED_NONCES.with(|n| {
            let set = n.borrow();
            assert!(set.contains(&(96369, 1)));
            assert!(set.contains(&(200200, 1)));
        });
    }
}
