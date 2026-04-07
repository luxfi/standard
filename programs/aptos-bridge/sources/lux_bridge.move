/// Lux Bridge — Aptos native bridge contract (Move)
///
/// Aptos Move differs from Sui Move:
///   - Account-based resources (not object UIDs)
///   - Global storage via move_to/borrow_global
///   - Ed25519 native verification
///   - Coin<T> standard (not sui::coin)
///   - No shared objects — resources stored under bridge account
module lux_bridge::bridge {
    use std::signer;
    use std::vector;
    use std::error;
    use std::bcs;
    use aptos_framework::coin::{Self, Coin, BurnCapability, MintCapability, FreezeCapability};
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::ed25519;
    use aptos_framework::table::{Self, Table};

    // ========================================
    // Error codes
    // ========================================
    const E_NOT_ADMIN: u64 = 1;
    const E_PAUSED: u64 = 2;
    const E_INVALID_SIGNATURE: u64 = 3;
    const E_NONCE_PROCESSED: u64 = 4;
    const E_DAILY_LIMIT: u64 = 5;
    const E_AMOUNT_ZERO: u64 = 6;
    const E_FEE_TOO_HIGH: u64 = 7;
    const E_INSUFFICIENT_VAULT: u64 = 8;
    const E_UNAUTHORIZED_SIGNER: u64 = 9;
    const E_NOT_INITIALIZED: u64 = 10;

    const APTOS_CHAIN_ID: u64 = 1; // Aptos mainnet

    // ========================================
    // Resources (stored under bridge account)
    // ========================================

    /// Global bridge config — stored under the module deployer's account.
    struct BridgeConfig has key {
        admin: address,
        mpc_signers: vector<vector<u8>>, // Ed25519 public keys (32 bytes each)
        threshold: u8,
        fee_bps: u64,
        fee_collector: address,
        paused: bool,
        outbound_nonce: u64,
        total_locked: u64,
        total_burned: u64,
    }

    /// Per-token vault. Stored under bridge account, parameterized by CoinType.
    struct Vault<phantom CoinType> has key {
        coins: Coin<CoinType>,
        daily_mint_limit: u64,
        daily_minted: u64,
        period_start: u64,
    }

    /// Nonce tracking. Stored under bridge account.
    struct NonceRegistry has key {
        processed: Table<u64, Table<u64, bool>>, // source_chain -> nonce -> processed
    }

    /// Wrapped token capabilities. Stored under bridge account.
    struct TokenCaps<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
    }

    // ========================================
    // Events
    // ========================================

    #[event]
    struct LockEvent has drop, store {
        source_chain: u64,
        dest_chain: u64,
        nonce: u64,
        sender: address,
        recipient: vector<u8>, // 32-byte dest address
        amount: u64,
        fee: u64,
    }

    #[event]
    struct MintEvent has drop, store {
        source_chain: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
    }

    #[event]
    struct BurnEvent has drop, store {
        source_chain: u64,
        dest_chain: u64,
        nonce: u64,
        sender: address,
        recipient: vector<u8>,
        amount: u64,
    }

    #[event]
    struct ReleaseEvent has drop, store {
        source_chain: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
    }

    // ========================================
    // Init
    // ========================================

    /// Initialize the bridge. Called once by the deployer.
    public entry fun initialize(
        admin: &signer,
        mpc_signers: vector<vector<u8>>,
        threshold: u8,
        fee_bps: u64,
    ) {
        assert!(fee_bps <= 500, error::invalid_argument(E_FEE_TOO_HIGH));

        let admin_addr = signer::address_of(admin);

        move_to(admin, BridgeConfig {
            admin: admin_addr,
            mpc_signers,
            threshold,
            fee_bps,
            fee_collector: admin_addr,
            paused: false,
            outbound_nonce: 0,
            total_locked: 0,
            total_burned: 0,
        });

        move_to(admin, NonceRegistry {
            processed: table::new(),
        });
    }

    /// Register a vault for a token type. Admin only.
    public entry fun create_vault<CoinType>(
        admin: &signer,
        daily_limit: u64,
    ) acquires BridgeConfig {
        let config = borrow_global<BridgeConfig>(signer::address_of(admin));
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(E_NOT_ADMIN));

        move_to(admin, Vault<CoinType> {
            coins: coin::zero<CoinType>(),
            daily_mint_limit: daily_limit,
            daily_minted: 0,
            period_start: 0,
        });
    }

    /// Register wrapped token capabilities (mint/burn/freeze).
    public entry fun register_token_caps<CoinType>(
        admin: &signer,
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
    ) acquires BridgeConfig {
        let config = borrow_global<BridgeConfig>(signer::address_of(admin));
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(E_NOT_ADMIN));

        move_to(admin, TokenCaps<CoinType> { mint_cap, burn_cap, freeze_cap });
    }

    // ========================================
    // Bridge operations
    // ========================================

    /// Lock native tokens for bridging. Emits LockEvent for MPC watchers.
    public entry fun lock_and_bridge<CoinType>(
        sender: &signer,
        bridge_addr: address,
        amount: u64,
        dest_chain_id: u64,
        recipient: vector<u8>,
    ) acquires BridgeConfig, Vault {
        let config = borrow_global_mut<BridgeConfig>(bridge_addr);
        assert!(!config.paused, error::unavailable(E_PAUSED));
        assert!(amount > 0, error::invalid_argument(E_AMOUNT_ZERO));

        // Calculate fee
        let fee = (amount * config.fee_bps) / 10_000;
        let bridge_amount = amount - fee;

        // Transfer to vault
        let coins = coin::withdraw<CoinType>(sender, amount);
        let vault = borrow_global_mut<Vault<CoinType>>(bridge_addr);
        coin::merge(&mut vault.coins, coins);

        config.total_locked = config.total_locked + bridge_amount;
        config.outbound_nonce = config.outbound_nonce + 1;
        let nonce = config.outbound_nonce;

        event::emit(LockEvent {
            source_chain: APTOS_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            sender: signer::address_of(sender),
            recipient,
            amount: bridge_amount,
            fee,
        });
    }

    /// Mint wrapped tokens with MPC Ed25519 signature verification.
    public entry fun mint_bridged<CoinType>(
        relayer: &signer,
        bridge_addr: address,
        source_chain_id: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
        signature: vector<u8>,
        signer_pubkey: vector<u8>,
    ) acquires BridgeConfig, NonceRegistry, Vault, TokenCaps {
        let config = borrow_global<BridgeConfig>(bridge_addr);
        assert!(!config.paused, error::unavailable(E_PAUSED));
        assert!(amount > 0, error::invalid_argument(E_AMOUNT_ZERO));

        // Verify signer is authorized
        assert!(is_authorized_signer(config, &signer_pubkey), error::permission_denied(E_UNAUTHORIZED_SIGNER));

        // Check nonce
        let registry = borrow_global_mut<NonceRegistry>(bridge_addr);
        assert!(!is_nonce_processed(registry, source_chain_id, nonce), error::already_exists(E_NONCE_PROCESSED));

        // Verify Ed25519 signature
        let message = build_mint_message(source_chain_id, nonce, recipient, amount);
        let sig = ed25519::new_signature_from_bytes(signature);
        let pk = ed25519::new_unvalidated_public_key_from_bytes(signer_pubkey);
        assert!(
            ed25519::signature_verify_strict(&sig, &pk, message),
            error::invalid_argument(E_INVALID_SIGNATURE),
        );

        // Check daily limit
        let vault = borrow_global_mut<Vault<CoinType>>(bridge_addr);
        check_daily_limit(vault, amount);

        // Mint to recipient
        let caps = borrow_global<TokenCaps<CoinType>>(bridge_addr);
        let minted = coin::mint<CoinType>(amount, &caps.mint_cap);
        coin::deposit(recipient, minted);

        // Mark nonce
        mark_nonce_processed(registry, source_chain_id, nonce);

        event::emit(MintEvent { source_chain: source_chain_id, nonce, recipient, amount });
    }

    /// Burn wrapped tokens for withdrawal. Emits BurnEvent.
    public entry fun burn_bridged<CoinType>(
        sender: &signer,
        bridge_addr: address,
        amount: u64,
        dest_chain_id: u64,
        recipient: vector<u8>,
    ) acquires BridgeConfig, TokenCaps {
        let config = borrow_global_mut<BridgeConfig>(bridge_addr);
        assert!(!config.paused, error::unavailable(E_PAUSED));
        assert!(amount > 0, error::invalid_argument(E_AMOUNT_ZERO));

        // Burn
        let coins = coin::withdraw<CoinType>(sender, amount);
        let caps = borrow_global<TokenCaps<CoinType>>(bridge_addr);
        coin::burn(coins, &caps.burn_cap);

        config.total_burned = config.total_burned + amount;
        config.outbound_nonce = config.outbound_nonce + 1;
        let nonce = config.outbound_nonce;

        event::emit(BurnEvent {
            source_chain: APTOS_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            sender: signer::address_of(sender),
            recipient,
            amount,
        });
    }

    /// Release locked tokens with MPC signature.
    public entry fun release<CoinType>(
        relayer: &signer,
        bridge_addr: address,
        source_chain_id: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
        signature: vector<u8>,
        signer_pubkey: vector<u8>,
    ) acquires BridgeConfig, NonceRegistry, Vault {
        let config = borrow_global<BridgeConfig>(bridge_addr);
        assert!(!config.paused, error::unavailable(E_PAUSED));

        assert!(is_authorized_signer(config, &signer_pubkey), error::permission_denied(E_UNAUTHORIZED_SIGNER));

        let registry = borrow_global_mut<NonceRegistry>(bridge_addr);
        assert!(!is_nonce_processed(registry, source_chain_id, nonce), error::already_exists(E_NONCE_PROCESSED));

        let message = build_release_message(source_chain_id, nonce, recipient, amount);
        let sig = ed25519::new_signature_from_bytes(signature);
        let pk = ed25519::new_unvalidated_public_key_from_bytes(signer_pubkey);
        assert!(ed25519::signature_verify_strict(&sig, &pk, message), error::invalid_argument(E_INVALID_SIGNATURE));

        let vault = borrow_global_mut<Vault<CoinType>>(bridge_addr);
        assert!(coin::value(&vault.coins) >= amount, error::resource_exhausted(E_INSUFFICIENT_VAULT));

        let released = coin::extract(&mut vault.coins, amount);
        coin::deposit(recipient, released);

        mark_nonce_processed(registry, source_chain_id, nonce);

        event::emit(ReleaseEvent { source_chain: source_chain_id, nonce, recipient, amount });
    }

    // ========================================
    // Admin
    // ========================================

    public entry fun pause(admin: &signer, bridge_addr: address) acquires BridgeConfig {
        let config = borrow_global_mut<BridgeConfig>(bridge_addr);
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(E_NOT_ADMIN));
        config.paused = true;
    }

    public entry fun unpause(admin: &signer, bridge_addr: address) acquires BridgeConfig {
        let config = borrow_global_mut<BridgeConfig>(bridge_addr);
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(E_NOT_ADMIN));
        config.paused = false;
    }

    public entry fun set_signers(
        admin: &signer,
        bridge_addr: address,
        signers: vector<vector<u8>>,
        threshold: u8,
    ) acquires BridgeConfig {
        let config = borrow_global_mut<BridgeConfig>(bridge_addr);
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(E_NOT_ADMIN));
        config.mpc_signers = signers;
        config.threshold = threshold;
    }

    public entry fun set_fee(admin: &signer, bridge_addr: address, fee_bps: u64) acquires BridgeConfig {
        let config = borrow_global_mut<BridgeConfig>(bridge_addr);
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(E_NOT_ADMIN));
        assert!(fee_bps <= 500, error::invalid_argument(E_FEE_TOO_HIGH));
        config.fee_bps = fee_bps;
    }

    // ========================================
    // Views
    // ========================================

    #[view]
    public fun total_locked(bridge_addr: address): u64 acquires BridgeConfig {
        borrow_global<BridgeConfig>(bridge_addr).total_locked
    }

    #[view]
    public fun total_burned(bridge_addr: address): u64 acquires BridgeConfig {
        borrow_global<BridgeConfig>(bridge_addr).total_burned
    }

    #[view]
    public fun is_paused(bridge_addr: address): bool acquires BridgeConfig {
        borrow_global<BridgeConfig>(bridge_addr).paused
    }

    // ========================================
    // Internal
    // ========================================

    fun is_authorized_signer(config: &BridgeConfig, pubkey: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(&config.mpc_signers);
        while (i < len) {
            if (vector::borrow(&config.mpc_signers, i) == pubkey) { return true };
            i = i + 1;
        };
        false
    }

    fun is_nonce_processed(registry: &NonceRegistry, chain_id: u64, nonce: u64): bool {
        if (!table::contains(&registry.processed, chain_id)) { return false };
        let chain_nonces = table::borrow(&registry.processed, chain_id);
        table::contains(chain_nonces, nonce)
    }

    fun mark_nonce_processed(registry: &mut NonceRegistry, chain_id: u64, nonce: u64) {
        if (!table::contains(&registry.processed, chain_id)) {
            table::add(&mut registry.processed, chain_id, table::new());
        };
        let chain_nonces = table::borrow_mut(&mut registry.processed, chain_id);
        table::add(chain_nonces, nonce, true);
    }

    fun build_mint_message(chain_id: u64, nonce: u64, recipient: address, amount: u64): vector<u8> {
        let msg = b"LUX_BRIDGE_MINT";
        vector::append(&mut msg, bcs::to_bytes(&chain_id));
        vector::append(&mut msg, bcs::to_bytes(&nonce));
        vector::append(&mut msg, bcs::to_bytes(&recipient));
        vector::append(&mut msg, bcs::to_bytes(&amount));
        msg
    }

    fun build_release_message(chain_id: u64, nonce: u64, recipient: address, amount: u64): vector<u8> {
        let msg = b"LUX_BRIDGE_RELEASE";
        vector::append(&mut msg, bcs::to_bytes(&chain_id));
        vector::append(&mut msg, bcs::to_bytes(&nonce));
        vector::append(&mut msg, bcs::to_bytes(&recipient));
        vector::append(&mut msg, bcs::to_bytes(&amount));
        msg
    }

    fun check_daily_limit<CoinType>(vault: &mut Vault<CoinType>, amount: u64) {
        if (vault.daily_mint_limit == 0) return;
        let now = timestamp::now_seconds();
        if (now >= vault.period_start + 86400) {
            vault.daily_minted = 0;
            vault.period_start = now;
        };
        let new_total = vault.daily_minted + amount;
        assert!(new_total <= vault.daily_mint_limit, error::resource_exhausted(E_DAILY_LIMIT));
        vault.daily_minted = new_total;
    }
}
