/// Lux Bridge — Stellar Soroban native bridge (Rust/WASM)
///
/// Soroban is Stellar's smart contract platform. Compiles to WASM.
/// Token standard: SEP-41 (Stellar Asset Contract).
/// Ed25519 native (Stellar uses Ed25519 for all keys).
#![no_std]
use soroban_sdk::{
    contract, contractimpl, contracttype, symbol_short,
    Address, BytesN, Env, Map, Vec as SorobanVec, log,
    token,
};

const STELLAR_CHAIN_ID: u64 = 1398895700; // "STLR" as u64

#[contracttype]
#[derive(Clone)]
pub struct BridgeConfig {
    pub admin: Address,
    pub mpc_signers: SorobanVec<BytesN<32>>,
    pub threshold: u32,
    pub fee_bps: u32,
    pub paused: bool,
    pub outbound_nonce: u64,
    pub total_locked: i128,
    pub total_burned: i128,
}

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Config,
    Nonce(u64, u64),   // (source_chain, nonce) -> bool
}

#[contract]
pub struct LuxBridge;

#[contractimpl]
impl LuxBridge {
    pub fn initialize(
        env: Env,
        admin: Address,
        mpc_signers: SorobanVec<BytesN<32>>,
        threshold: u32,
        fee_bps: u32,
    ) {
        assert!(fee_bps <= 500, "Fee too high");
        let config = BridgeConfig {
            admin,
            mpc_signers,
            threshold,
            fee_bps,
            paused: false,
            outbound_nonce: 0,
            total_locked: 0,
            total_burned: 0,
        };
        env.storage().instance().set(&DataKey::Config, &config);
    }

    /// Lock Stellar assets for bridging.
    pub fn lock_and_bridge(
        env: Env,
        sender: Address,
        token_addr: Address,
        amount: i128,
        dest_chain_id: u64,
        recipient: BytesN<32>,
    ) -> u64 {
        sender.require_auth();
        let mut config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        assert!(!config.paused, "Paused");
        assert!(amount > 0, "Zero amount");

        let fee = amount * config.fee_bps as i128 / 10_000;
        let bridge_amount = amount - fee;

        // Transfer token to this contract
        let client = token::Client::new(&env, &token_addr);
        client.transfer(&sender, &env.current_contract_address(), &amount);

        config.total_locked += bridge_amount;
        config.outbound_nonce += 1;
        let nonce = config.outbound_nonce;
        env.storage().instance().set(&DataKey::Config, &config);

        env.events().publish(
            (symbol_short!("lock"), dest_chain_id),
            (nonce, sender, recipient, bridge_amount),
        );

        nonce
    }

    /// Mint wrapped tokens with MPC Ed25519 signature.
    pub fn mint_bridged(
        env: Env,
        token_addr: Address,
        source_chain_id: u64,
        nonce: u64,
        recipient: Address,
        amount: i128,
        signature: BytesN<64>,
        signer_pubkey: BytesN<32>,
    ) {
        let config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        assert!(!config.paused, "Paused");
        assert!(amount > 0, "Zero");

        // Verify signer authorized
        let mut authorized = false;
        for i in 0..config.mpc_signers.len() {
            if config.mpc_signers.get(i).unwrap() == signer_pubkey {
                authorized = true;
                break;
            }
        }
        assert!(authorized, "Unauthorized");

        // Check nonce
        let nonce_key = DataKey::Nonce(source_chain_id, nonce);
        assert!(!env.storage().persistent().has(&nonce_key), "Nonce processed");

        // Verify Ed25519 (Soroban native)
        env.crypto().ed25519_verify(
            &signer_pubkey,
            &env.crypto().sha256(&Self::build_mint_message(&env, source_chain_id, nonce, &recipient, amount)),
            &signature,
        );

        env.storage().persistent().set(&nonce_key, &true);

        // Transfer from contract to recipient
        let client = token::Client::new(&env, &token_addr);
        client.transfer(&env.current_contract_address(), &recipient, &amount);

        env.events().publish(
            (symbol_short!("mint"), source_chain_id),
            (nonce, recipient, amount),
        );
    }

    /// Burn wrapped tokens for withdrawal.
    pub fn burn_bridged(
        env: Env,
        sender: Address,
        token_addr: Address,
        amount: i128,
        dest_chain_id: u64,
        recipient: BytesN<32>,
    ) -> u64 {
        sender.require_auth();
        let mut config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        assert!(!config.paused, "Paused");
        assert!(amount > 0, "Zero");

        // Transfer tokens to contract (effectively burns them from user perspective)
        let client = token::Client::new(&env, &token_addr);
        client.transfer(&sender, &env.current_contract_address(), &amount);

        config.total_burned += amount;
        config.outbound_nonce += 1;
        let nonce = config.outbound_nonce;
        env.storage().instance().set(&DataKey::Config, &config);

        env.events().publish(
            (symbol_short!("burn"), dest_chain_id),
            (nonce, sender, recipient, amount),
        );

        nonce
    }

    // Admin
    pub fn pause(env: Env, admin: Address) {
        admin.require_auth();
        let mut config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        assert!(admin == config.admin);
        config.paused = true;
        env.storage().instance().set(&DataKey::Config, &config);
    }

    pub fn unpause(env: Env, admin: Address) {
        admin.require_auth();
        let mut config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        assert!(admin == config.admin);
        config.paused = false;
        env.storage().instance().set(&DataKey::Config, &config);
    }

    // Views
    pub fn total_locked(env: Env) -> i128 {
        let config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        config.total_locked
    }

    pub fn total_burned(env: Env) -> i128 {
        let config: BridgeConfig = env.storage().instance().get(&DataKey::Config).unwrap();
        config.total_burned
    }

    // Internal
    fn build_mint_message(env: &Env, chain_id: u64, nonce: u64, recipient: &Address, amount: i128) -> soroban_sdk::Bytes {
        let mut msg = soroban_sdk::Bytes::new(env);
        msg.extend_from_slice(b"LUX_BRIDGE_MINT");
        msg.extend_from_slice(&chain_id.to_le_bytes());
        msg.extend_from_slice(&nonce.to_le_bytes());
        msg.extend_from_slice(&amount.to_le_bytes());
        msg
    }
}
