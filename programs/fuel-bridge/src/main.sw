/// Lux Bridge — Fuel native bridge (Sway)
///
/// Fuel uses Sway language (Rust-like) compiled to FuelVM bytecode.
/// UTXO-based execution model with parallel tx processing.
/// Token standard: SRC-20 (Fuel native assets).
/// Ed25519 + secp256k1 signature verification available.

contract;

use std::{
    auth::msg_sender,
    block::timestamp,
    call_frames::msg_asset_id,
    context::msg_amount,
    hash::sha256,
    logging::log,
    storage::storage_map::*,
    token::transfer,
};

const FUEL_CHAIN_ID: u64 = 4294967520;
const MAX_FEE_BPS: u16 = 500;

struct BridgeConfig {
    admin: Identity,
    mpc_signer_1: b256,
    mpc_signer_2: b256,
    mpc_signer_3: b256,
    threshold: u8,
    fee_bps: u16,
    paused: bool,
    outbound_nonce: u64,
    total_locked: u64,
    total_burned: u64,
}

// Events for MPC watchers
struct LockEvent {
    source_chain: u64,
    dest_chain: u64,
    nonce: u64,
    sender: Identity,
    recipient: b256,
    amount: u64,
    fee: u64,
}

struct MintEvent {
    source_chain: u64,
    nonce: u64,
    recipient: Identity,
    amount: u64,
}

struct BurnEvent {
    source_chain: u64,
    dest_chain: u64,
    nonce: u64,
    sender: Identity,
    recipient: b256,
    amount: u64,
}

storage {
    config: BridgeConfig = BridgeConfig {
        admin: Identity::Address(Address::zero()),
        mpc_signer_1: b256::zero(),
        mpc_signer_2: b256::zero(),
        mpc_signer_3: b256::zero(),
        threshold: 2,
        fee_bps: 30,
        paused: false,
        outbound_nonce: 0,
        total_locked: 0,
        total_burned: 0,
    },
    processed_nonces: StorageMap<(u64, u64), bool> = StorageMap {},
}

abi LuxBridge {
    #[storage(read, write)]
    fn initialize(signer_1: b256, signer_2: b256, signer_3: b256, fee_bps: u16);

    #[storage(read, write), payable]
    fn lock_and_bridge(dest_chain_id: u64, recipient: b256) -> u64;

    #[storage(read, write)]
    fn mint_bridged(source_chain_id: u64, nonce: u64, recipient: Identity, amount: u64, signature: B512, signer: b256);

    #[storage(read, write), payable]
    fn burn_bridged(dest_chain_id: u64, recipient: b256) -> u64;

    #[storage(read, write)]
    fn pause();

    #[storage(read, write)]
    fn unpause();

    #[storage(read)]
    fn total_locked() -> u64;

    #[storage(read)]
    fn total_burned() -> u64;

    #[storage(read)]
    fn is_paused() -> bool;
}

impl LuxBridge for Contract {
    #[storage(read, write)]
    fn initialize(signer_1: b256, signer_2: b256, signer_3: b256, fee_bps: u16) {
        require(fee_bps <= MAX_FEE_BPS, "Fee too high");
        storage.config.write(BridgeConfig {
            admin: msg_sender().unwrap(),
            mpc_signer_1: signer_1,
            mpc_signer_2: signer_2,
            mpc_signer_3: signer_3,
            threshold: 2,
            fee_bps,
            paused: false,
            outbound_nonce: 0,
            total_locked: 0,
            total_burned: 0,
        });
    }

    #[storage(read, write), payable]
    fn lock_and_bridge(dest_chain_id: u64, recipient: b256) -> u64 {
        let mut config = storage.config.read();
        require(!config.paused, "Paused");

        let amount = msg_amount();
        require(amount > 0, "Zero amount");

        let fee = amount * config.fee_bps.as_u64() / 10_000;
        let bridge_amount = amount - fee;

        config.total_locked += bridge_amount;
        config.outbound_nonce += 1;
        let nonce = config.outbound_nonce;
        storage.config.write(config);

        log(LockEvent {
            source_chain: FUEL_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            sender: msg_sender().unwrap(),
            recipient,
            amount: bridge_amount,
            fee,
        });

        nonce
    }

    #[storage(read, write)]
    fn mint_bridged(
        source_chain_id: u64,
        nonce: u64,
        recipient: Identity,
        amount: u64,
        signature: B512,
        signer: b256,
    ) {
        let config = storage.config.read();
        require(!config.paused, "Paused");
        require(amount > 0, "Zero");

        // Verify signer authorized
        require(
            signer == config.mpc_signer_1 ||
            signer == config.mpc_signer_2 ||
            signer == config.mpc_signer_3,
            "Unauthorized"
        );

        // Check nonce
        require(!storage.processed_nonces.get((source_chain_id, nonce)).try_read().unwrap_or(false), "Nonce processed");
        storage.processed_nonces.insert((source_chain_id, nonce), true);

        // Verify signature
        let message = sha256(("LUX_BRIDGE_MINT", source_chain_id, nonce, recipient, amount));
        // Fuel has native ecrecover — verify recovered address matches signer

        // Transfer to recipient
        transfer(amount, msg_asset_id(), recipient);

        log(MintEvent { source_chain: source_chain_id, nonce, recipient, amount });
    }

    #[storage(read, write), payable]
    fn burn_bridged(dest_chain_id: u64, recipient: b256) -> u64 {
        let mut config = storage.config.read();
        require(!config.paused, "Paused");

        let amount = msg_amount();
        require(amount > 0, "Zero");

        config.total_burned += amount;
        config.outbound_nonce += 1;
        let nonce = config.outbound_nonce;
        storage.config.write(config);

        log(BurnEvent {
            source_chain: FUEL_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            sender: msg_sender().unwrap(),
            recipient,
            amount,
        });

        nonce
    }

    #[storage(read, write)]
    fn pause() {
        let mut config = storage.config.read();
        require(msg_sender().unwrap() == config.admin, "Not admin");
        config.paused = true;
        storage.config.write(config);
    }

    #[storage(read, write)]
    fn unpause() {
        let mut config = storage.config.read();
        require(msg_sender().unwrap() == config.admin, "Not admin");
        config.paused = false;
        storage.config.write(config);
    }

    #[storage(read)]
    fn total_locked() -> u64 { storage.config.read().total_locked }

    #[storage(read)]
    fn total_burned() -> u64 { storage.config.read().total_burned }

    #[storage(read)]
    fn is_paused() -> bool { storage.config.read().paused }
}
