#![no_std]
// Lux Bridge -- Stellar Soroban native bridge (Rust/WASM)
//
// Soroban is Stellar's smart contract platform. Compiles to WASM.
// Token standard: SEP-41 (Stellar Asset Contract).
// Ed25519 native (Stellar uses Ed25519 for all keys).

use soroban_sdk::{
    contract, contractimpl, contracttype, symbol_short,
    Address, Bytes, BytesN, Env, Vec, log,
    token,
};

const STELLAR_CHAIN_ID: u64 = 1398895700; // "STLR" as u64

#[contracttype]
#[derive(Clone)]
pub struct BridgeConfig {
    pub admin: Address,
    pub mpc_signers: Vec<BytesN<32>>,
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
        mpc_signers: Vec<BytesN<32>>,
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
        let msg_hash = env.crypto().sha256(&Self::build_mint_message(&env, source_chain_id, nonce, &recipient, amount));
        env.crypto().ed25519_verify(
            &signer_pubkey,
            &msg_hash.into(),
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
    fn build_mint_message(env: &Env, chain_id: u64, nonce: u64, _recipient: &Address, amount: i128) -> Bytes {
        let mut msg = Bytes::new(env);
        msg.extend_from_slice(b"LUX_BRIDGE_MINT");
        msg.extend_from_slice(&chain_id.to_le_bytes());
        msg.extend_from_slice(&nonce.to_le_bytes());
        msg.extend_from_slice(&amount.to_le_bytes());
        msg
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use soroban_sdk::testutils::Address as _;
    use soroban_sdk::{vec, Env};

    use ed25519_dalek::{Signer, SigningKey};
    use rand::rngs::OsRng;

    fn setup_env() -> (Env, Address, Address) {
        let env = Env::default();
        env.mock_all_auths();
        let contract_id = env.register(LuxBridge, ());
        let admin = Address::generate(&env);
        (env, contract_id, admin)
    }

    fn create_test_token(env: &Env, admin: &Address) -> Address {
        let token = env.register_stellar_asset_contract_v2(admin.clone());
        token.address().clone()
    }

    fn mint_token(env: &Env, token_addr: &Address, admin: &Address, to: &Address, amount: i128) {
        let sac = token::StellarAssetClient::new(env, token_addr);
        sac.mint(to, &amount);
    }

    fn make_signer(env: &Env) -> (SigningKey, BytesN<32>) {
        let sk = SigningKey::generate(&mut OsRng);
        let pk_bytes: [u8; 32] = sk.verifying_key().to_bytes();
        let pubkey = BytesN::from_array(env, &pk_bytes);
        (sk, pubkey)
    }

    fn init_bridge(env: &Env, contract_id: &Address, admin: &Address, signers: Vec<BytesN<32>>) {
        let client = LuxBridgeClient::new(env, contract_id);
        client.initialize(admin, &signers, &2, &100); // threshold=2, fee=1%
    }

    // ---------------------------------------------------------------
    // 1. Initialize
    // ---------------------------------------------------------------

    #[test]
    fn test_initialize_sets_config() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk.clone()];

        init_bridge(&env, &contract_id, &admin, signers);

        let client = LuxBridgeClient::new(&env, &contract_id);
        assert_eq!(client.total_locked(), 0);
        assert_eq!(client.total_burned(), 0);
    }

    #[test]
    #[should_panic(expected = "Fee too high")]
    fn test_initialize_rejects_high_fee() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        let client = LuxBridgeClient::new(&env, &contract_id);
        client.initialize(&admin, &signers, &2, &501);
    }

    // ---------------------------------------------------------------
    // 2. Lock
    // ---------------------------------------------------------------

    #[test]
    fn test_lock_and_bridge() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &sender, 10_000);

        let client = LuxBridgeClient::new(&env, &contract_id);
        let dest_chain: u64 = 1;
        let recipient = BytesN::from_array(&env, &[0u8; 32]);

        let nonce = client.lock_and_bridge(&sender, &token_addr, &5_000, &dest_chain, &recipient);
        assert_eq!(nonce, 1);

        // fee = 5000 * 100 / 10000 = 50, bridge_amount = 4950
        assert_eq!(client.total_locked(), 4950);
    }

    #[test]
    fn test_lock_increments_nonce() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &sender, 20_000);

        let client = LuxBridgeClient::new(&env, &contract_id);
        let recipient = BytesN::from_array(&env, &[0u8; 32]);

        let n1 = client.lock_and_bridge(&sender, &token_addr, &5_000, &1, &recipient);
        let n2 = client.lock_and_bridge(&sender, &token_addr, &5_000, &1, &recipient);
        assert_eq!(n1, 1);
        assert_eq!(n2, 2);
    }

    #[test]
    #[should_panic(expected = "Zero amount")]
    fn test_lock_rejects_zero_amount() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        let client = LuxBridgeClient::new(&env, &contract_id);
        let recipient = BytesN::from_array(&env, &[0u8; 32]);
        client.lock_and_bridge(&sender, &token_addr, &0, &1, &recipient);
    }

    // ---------------------------------------------------------------
    // 3. Mint (ed25519 verification)
    // ---------------------------------------------------------------

    #[test]
    fn test_mint_bridged_with_valid_signature() {
        let (env, contract_id, admin) = setup_env();
        let (sk, pk) = make_signer(&env);
        let signers = vec![&env, pk.clone()];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let recipient = Address::generate(&env);

        // Fund the contract so it can transfer to recipient
        mint_token(&env, &token_addr, &admin, &contract_id, 10_000);

        let source_chain: u64 = 42;
        let nonce: u64 = 1;
        let amount: i128 = 1_000;

        // Build the same message the contract builds
        let msg = LuxBridge::build_mint_message(&env, source_chain, nonce, &recipient, amount);
        let msg_hash = env.crypto().sha256(&msg);
        let hash_bytes: [u8; 32] = msg_hash.to_array();

        // Sign with ed25519-dalek
        let sig = sk.sign(&hash_bytes);
        let sig_bytes: BytesN<64> = BytesN::from_array(&env, &sig.to_bytes());

        let client = LuxBridgeClient::new(&env, &contract_id);
        client.mint_bridged(
            &token_addr,
            &source_chain,
            &nonce,
            &recipient,
            &amount,
            &sig_bytes,
            &pk,
        );

        // Verify recipient received tokens
        let tok = token::Client::new(&env, &token_addr);
        assert_eq!(tok.balance(&recipient), 1_000);
    }

    #[test]
    #[should_panic(expected = "Unauthorized")]
    fn test_mint_rejects_unknown_signer() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let recipient = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &contract_id, 10_000);

        // Use a different signer not in the config
        let (rogue_sk, rogue_pk) = make_signer(&env);

        let source_chain: u64 = 42;
        let nonce: u64 = 1;
        let amount: i128 = 1_000;

        let msg = LuxBridge::build_mint_message(&env, source_chain, nonce, &recipient, amount);
        let msg_hash = env.crypto().sha256(&msg);
        let hash_bytes: [u8; 32] = msg_hash.to_array();
        let sig = rogue_sk.sign(&hash_bytes);
        let sig_bytes: BytesN<64> = BytesN::from_array(&env, &sig.to_bytes());

        let client = LuxBridgeClient::new(&env, &contract_id);
        client.mint_bridged(
            &token_addr,
            &source_chain,
            &nonce,
            &recipient,
            &amount,
            &sig_bytes,
            &rogue_pk,
        );
    }

    #[test]
    #[should_panic(expected = "Nonce processed")]
    fn test_mint_rejects_replay() {
        let (env, contract_id, admin) = setup_env();
        let (sk, pk) = make_signer(&env);
        let signers = vec![&env, pk.clone()];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let recipient = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &contract_id, 20_000);

        let source_chain: u64 = 42;
        let nonce: u64 = 1;
        let amount: i128 = 1_000;

        let msg = LuxBridge::build_mint_message(&env, source_chain, nonce, &recipient, amount);
        let msg_hash = env.crypto().sha256(&msg);
        let hash_bytes: [u8; 32] = msg_hash.to_array();
        let sig = sk.sign(&hash_bytes);
        let sig_bytes: BytesN<64> = BytesN::from_array(&env, &sig.to_bytes());

        let client = LuxBridgeClient::new(&env, &contract_id);

        // First mint succeeds
        client.mint_bridged(&token_addr, &source_chain, &nonce, &recipient, &amount, &sig_bytes, &pk);

        // Replay panics
        client.mint_bridged(&token_addr, &source_chain, &nonce, &recipient, &amount, &sig_bytes, &pk);
    }

    // ---------------------------------------------------------------
    // 4. Burn
    // ---------------------------------------------------------------

    #[test]
    fn test_burn_bridged() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &sender, 10_000);

        let client = LuxBridgeClient::new(&env, &contract_id);
        let recipient = BytesN::from_array(&env, &[1u8; 32]);

        let nonce = client.burn_bridged(&sender, &token_addr, &3_000, &1, &recipient);
        assert_eq!(nonce, 1);
        assert_eq!(client.total_burned(), 3_000);

        // Verify sender balance decreased
        let tok = token::Client::new(&env, &token_addr);
        assert_eq!(tok.balance(&sender), 7_000);
    }

    #[test]
    #[should_panic(expected = "Zero")]
    fn test_burn_rejects_zero() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        let client = LuxBridgeClient::new(&env, &contract_id);
        let recipient = BytesN::from_array(&env, &[0u8; 32]);
        client.burn_bridged(&sender, &token_addr, &0, &1, &recipient);
    }

    // ---------------------------------------------------------------
    // 5. Pause / Unpause
    // ---------------------------------------------------------------

    #[test]
    fn test_pause_and_unpause() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &sender, 10_000);

        let client = LuxBridgeClient::new(&env, &contract_id);

        // Pause
        client.pause(&admin);

        // Lock should fail while paused
        let paused = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let recipient = BytesN::from_array(&env, &[0u8; 32]);
            client.lock_and_bridge(&sender, &token_addr, &1_000, &1, &recipient);
        }));
        assert!(paused.is_err());

        // Unpause
        client.unpause(&admin);

        // Lock should work again
        let recipient = BytesN::from_array(&env, &[0u8; 32]);
        let nonce = client.lock_and_bridge(&sender, &token_addr, &1_000, &1, &recipient);
        assert_eq!(nonce, 1);
    }

    #[test]
    #[should_panic(expected = "Paused")]
    fn test_lock_while_paused() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &sender, 10_000);

        let client = LuxBridgeClient::new(&env, &contract_id);
        client.pause(&admin);

        let recipient = BytesN::from_array(&env, &[0u8; 32]);
        client.lock_and_bridge(&sender, &token_addr, &1_000, &1, &recipient);
    }

    #[test]
    #[should_panic(expected = "Paused")]
    fn test_burn_while_paused() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let token_addr = create_test_token(&env, &admin);
        let sender = Address::generate(&env);
        mint_token(&env, &token_addr, &admin, &sender, 10_000);

        let client = LuxBridgeClient::new(&env, &contract_id);
        client.pause(&admin);

        let recipient = BytesN::from_array(&env, &[0u8; 32]);
        client.burn_bridged(&sender, &token_addr, &1_000, &1, &recipient);
    }

    // ---------------------------------------------------------------
    // 6. Unauthorized access
    // ---------------------------------------------------------------

    #[test]
    #[should_panic]
    fn test_pause_rejects_non_admin() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let impostor = Address::generate(&env);
        let client = LuxBridgeClient::new(&env, &contract_id);
        client.pause(&impostor);
    }

    #[test]
    #[should_panic]
    fn test_unpause_rejects_non_admin() {
        let (env, contract_id, admin) = setup_env();
        let (_, pk) = make_signer(&env);
        let signers = vec![&env, pk];
        init_bridge(&env, &contract_id, &admin, signers);

        let client = LuxBridgeClient::new(&env, &contract_id);
        client.pause(&admin);

        let impostor = Address::generate(&env);
        client.unpause(&impostor);
    }
}
