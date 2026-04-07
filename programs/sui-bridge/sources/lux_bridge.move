/// Lux Bridge — Sui native bridge contract (Move)
///
/// Implements cross-chain token bridging between Sui and Lux Network.
/// Uses Ed25519 MPC threshold signatures (FROST) for attestation.
/// Token standard: Coin<T> (Sui native fungible tokens)
///
/// Flow:
///   Lock:    User deposits Coin<T> into bridge vault → LockEvent → MPC mints on dest
///   Mint:    MPC signs mint → relayer calls mint_bridged → TreasuryCap mints to recipient
///   Burn:    User burns wrapped coin → BurnEvent → MPC releases on dest
///   Release: MPC signs release → relayer calls release → vault sends Coin<T> to recipient
///
/// Object model:
///   BridgeConfig (shared): global config, MPC signers, fees, pause state
///   Vault<T> (shared): per-token locked balance
///   NonceRegistry (shared): processed nonce tracking per source chain
///   AdminCap (owned): admin capability for config changes
module lux_bridge::bridge {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::ed25519;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::bcs;

    // ========================================
    // Error codes
    // ========================================
    const E_PAUSED: u64 = 0;
    const E_INVALID_SIGNATURE: u64 = 1;
    const E_NONCE_PROCESSED: u64 = 2;
    const E_DAILY_LIMIT: u64 = 3;
    const E_UNAUTHORIZED: u64 = 4;
    const E_AMOUNT_ZERO: u64 = 5;
    const E_FEE_TOO_HIGH: u64 = 6;
    const E_INSUFFICIENT_VAULT: u64 = 7;

    // Sui chain ID in Lux bridge namespace
    const SUI_CHAIN_ID: u64 = 784; // Sui mainnet chain identifier

    // ========================================
    // Structs
    // ========================================

    /// Admin capability — holder can update config, pause, rotate signers.
    /// Created once on publish, transferred to deployer.
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Global bridge configuration. Shared object.
    public struct BridgeConfig has key {
        id: UID,
        /// MPC signer Ed25519 public keys (32 bytes each)
        mpc_signers: vector<vector<u8>>,
        /// Signing threshold (e.g., 2 of 3)
        threshold: u8,
        /// Fee in basis points (0-500 = 0-5%)
        fee_bps: u64,
        /// Fee collector address
        fee_collector: address,
        /// Emergency pause
        paused: bool,
        /// Outbound nonce counter
        outbound_nonce: u64,
        /// Total locked value (for backing attestation, in base units)
        total_locked: u64,
        /// Total burned value
        total_burned: u64,
    }

    /// Per-token vault holding locked native assets. Shared object.
    /// One Vault<T> per bridgeable token type.
    public struct Vault<phantom T> has key {
        id: UID,
        balance: Balance<T>,
        /// Daily mint limit (0 = unlimited)
        daily_mint_limit: u64,
        /// Minted in current period
        daily_minted: u64,
        /// Period start (unix ms)
        period_start: u64,
    }

    /// Tracks processed inbound nonces per source chain. Shared object.
    public struct NonceRegistry has key {
        id: UID,
        /// source_chain_id -> nonce -> processed
        processed: Table<u64, Table<u64, bool>>,
    }

    // ========================================
    // Events (for MPC watchers)
    // ========================================

    public struct LockEvent has copy, drop {
        source_chain: u64,
        dest_chain: u64,
        nonce: u64,
        token_type: vector<u8>, // TypeName of the locked coin
        sender: address,
        recipient: vector<u8>, // 32-byte dest address
        amount: u64,
        fee: u64,
    }

    public struct MintEvent has copy, drop {
        source_chain: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
    }

    public struct BurnEvent has copy, drop {
        source_chain: u64,
        dest_chain: u64,
        nonce: u64,
        token_type: vector<u8>,
        sender: address,
        recipient: vector<u8>,
        amount: u64,
    }

    public struct ReleaseEvent has copy, drop {
        source_chain: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
    }

    // ========================================
    // Init — called once on publish
    // ========================================

    fun init(ctx: &mut TxContext) {
        // Create admin capability
        transfer::transfer(AdminCap { id: object::new(ctx) }, tx_context::sender(ctx));

        // Create shared config with empty signers (admin must initialize)
        transfer::share_object(BridgeConfig {
            id: object::new(ctx),
            mpc_signers: vector::empty(),
            threshold: 2,
            fee_bps: 30, // 0.3% default
            fee_collector: tx_context::sender(ctx),
            paused: true, // Start paused until signers are set
            outbound_nonce: 0,
            total_locked: 0,
            total_burned: 0,
        });

        // Create shared nonce registry
        transfer::share_object(NonceRegistry {
            id: object::new(ctx),
            processed: table::new(ctx),
        });
    }

    // ========================================
    // Bridge operations
    // ========================================

    /// Lock native coins for bridging to another chain.
    /// Emits LockEvent for MPC watchers.
    public entry fun lock_and_bridge<T>(
        config: &mut BridgeConfig,
        vault: &mut Vault<T>,
        coin: Coin<T>,
        dest_chain_id: u64,
        recipient: vector<u8>, // 32-byte destination address
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!config.paused, E_PAUSED);

        let amount = coin::value(&coin);
        assert!(amount > 0, E_AMOUNT_ZERO);

        // Calculate fee
        let fee = (amount * config.fee_bps) / 10_000;
        let bridge_amount = amount - fee;

        // Deposit full amount into vault (fee stays in vault, claimable by admin)
        balance::join(&mut vault.balance, coin::into_balance(coin));

        // Track totals
        config.total_locked = config.total_locked + bridge_amount;
        config.outbound_nonce = config.outbound_nonce + 1;
        let nonce = config.outbound_nonce;

        // Get token type name for event
        let token_type = b""; // In production: std::type_name::get<T>()

        event::emit(LockEvent {
            source_chain: SUI_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            token_type,
            sender: tx_context::sender(ctx),
            recipient,
            amount: bridge_amount,
            fee,
        });
    }

    /// Mint wrapped tokens — called by relayer with MPC Ed25519 signature.
    public entry fun mint_bridged<T>(
        config: &BridgeConfig,
        registry: &mut NonceRegistry,
        vault: &mut Vault<T>,
        treasury_cap: &mut TreasuryCap<T>,
        source_chain_id: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
        signature: vector<u8>, // 64-byte Ed25519 signature
        signer_pubkey: vector<u8>, // 32-byte Ed25519 public key
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!config.paused, E_PAUSED);
        assert!(amount > 0, E_AMOUNT_ZERO);

        // Verify signer is authorized
        assert!(is_authorized_signer(config, &signer_pubkey), E_UNAUTHORIZED);

        // Check nonce not processed
        assert!(!is_nonce_processed(registry, source_chain_id, nonce), E_NONCE_PROCESSED);

        // Verify Ed25519 signature over the bridge message
        let message = build_mint_message(source_chain_id, nonce, recipient, amount);
        assert!(
            ed25519::ed25519_verify(&signature, &signer_pubkey, &message),
            E_INVALID_SIGNATURE,
        );

        // Check daily limit
        check_daily_limit(vault, amount, clock);

        // Mint to recipient
        let minted_coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(minted_coin, recipient);

        // Mark nonce processed
        mark_nonce_processed(registry, source_chain_id, nonce, ctx);

        event::emit(MintEvent {
            source_chain: source_chain_id,
            nonce,
            recipient,
            amount,
        });
    }

    /// Burn wrapped tokens for withdrawal to another chain.
    /// Emits BurnEvent for MPC watchers.
    public entry fun burn_bridged<T>(
        config: &mut BridgeConfig,
        treasury_cap: &mut TreasuryCap<T>,
        coin: Coin<T>,
        dest_chain_id: u64,
        recipient: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(!config.paused, E_PAUSED);

        let amount = coin::value(&coin);
        assert!(amount > 0, E_AMOUNT_ZERO);

        // Burn the wrapped tokens
        coin::burn(treasury_cap, coin);

        config.total_burned = config.total_burned + amount;
        config.outbound_nonce = config.outbound_nonce + 1;
        let nonce = config.outbound_nonce;

        let token_type = b"";

        event::emit(BurnEvent {
            source_chain: SUI_CHAIN_ID,
            dest_chain: dest_chain_id,
            nonce,
            token_type,
            sender: tx_context::sender(ctx),
            recipient,
            amount,
        });
    }

    /// Release locked native tokens — called by relayer with MPC signature.
    public entry fun release<T>(
        config: &BridgeConfig,
        registry: &mut NonceRegistry,
        vault: &mut Vault<T>,
        source_chain_id: u64,
        nonce: u64,
        recipient: address,
        amount: u64,
        signature: vector<u8>,
        signer_pubkey: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(!config.paused, E_PAUSED);

        // Verify signer
        assert!(is_authorized_signer(config, &signer_pubkey), E_UNAUTHORIZED);

        // Check nonce
        assert!(!is_nonce_processed(registry, source_chain_id, nonce), E_NONCE_PROCESSED);

        // Verify signature (different prefix than mint for domain separation)
        let message = build_release_message(source_chain_id, nonce, recipient, amount);
        assert!(
            ed25519::ed25519_verify(&signature, &signer_pubkey, &message),
            E_INVALID_SIGNATURE,
        );

        // Check vault has enough
        assert!(balance::value(&vault.balance) >= amount, E_INSUFFICIENT_VAULT);

        // Transfer from vault to recipient
        let released = coin::from_balance(balance::split(&mut vault.balance, amount), ctx);
        transfer::public_transfer(released, recipient);

        mark_nonce_processed(registry, source_chain_id, nonce, ctx);

        event::emit(ReleaseEvent {
            source_chain: source_chain_id,
            nonce,
            recipient,
            amount,
        });
    }

    // ========================================
    // Admin operations
    // ========================================

    public entry fun set_signers(
        _: &AdminCap,
        config: &mut BridgeConfig,
        signers: vector<vector<u8>>,
        threshold: u8,
    ) {
        config.mpc_signers = signers;
        config.threshold = threshold;
    }

    public entry fun pause(_: &AdminCap, config: &mut BridgeConfig) {
        config.paused = true;
    }

    public entry fun unpause(_: &AdminCap, config: &mut BridgeConfig) {
        config.paused = false;
    }

    public entry fun set_fee(_: &AdminCap, config: &mut BridgeConfig, fee_bps: u64) {
        assert!(fee_bps <= 500, E_FEE_TOO_HIGH);
        config.fee_bps = fee_bps;
    }

    /// Create a new vault for a token type. Called once per bridgeable token.
    public entry fun create_vault<T>(
        _: &AdminCap,
        daily_limit: u64,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(Vault<T> {
            id: object::new(ctx),
            balance: balance::zero(),
            daily_mint_limit: daily_limit,
            daily_minted: 0,
            period_start: 0,
        });
    }

    // ========================================
    // View functions
    // ========================================

    public fun total_locked(config: &BridgeConfig): u64 { config.total_locked }
    public fun total_burned(config: &BridgeConfig): u64 { config.total_burned }
    public fun is_paused(config: &BridgeConfig): bool { config.paused }
    public fun current_nonce(config: &BridgeConfig): u64 { config.outbound_nonce }

    // ========================================
    // Internal helpers
    // ========================================

    fun is_authorized_signer(config: &BridgeConfig, pubkey: &vector<u8>): bool {
        let i = 0;
        let len = vector::length(&config.mpc_signers);
        while (i < len) {
            if (vector::borrow(&config.mpc_signers, i) == pubkey) {
                return true
            };
            i = i + 1;
        };
        false
    }

    fun is_nonce_processed(registry: &NonceRegistry, chain_id: u64, nonce: u64): bool {
        if (!table::contains(&registry.processed, chain_id)) {
            return false
        };
        let chain_nonces = table::borrow(&registry.processed, chain_id);
        table::contains(chain_nonces, nonce)
    }

    fun mark_nonce_processed(
        registry: &mut NonceRegistry,
        chain_id: u64,
        nonce: u64,
        ctx: &mut TxContext,
    ) {
        if (!table::contains(&registry.processed, chain_id)) {
            table::add(&mut registry.processed, chain_id, table::new(ctx));
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

    fun check_daily_limit<T>(vault: &mut Vault<T>, amount: u64, clock: &Clock) {
        if (vault.daily_mint_limit == 0) return; // unlimited

        let now = sui::clock::timestamp_ms(clock);
        let day_ms: u64 = 86_400_000;

        // Reset if new period
        if (now >= vault.period_start + day_ms) {
            vault.daily_minted = 0;
            vault.period_start = now;
        };

        let new_total = vault.daily_minted + amount;
        assert!(new_total <= vault.daily_mint_limit, E_DAILY_LIMIT);
        vault.daily_minted = new_total;
    }
}
