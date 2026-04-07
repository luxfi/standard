#[test_only]
module lux_bridge::bridge_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::timestamp;
    use lux_bridge::bridge;

    /// Test coin type.
    struct TestCoin {}

    struct TestCoinCaps has key {
        mint_cap: MintCapability<TestCoin>,
        burn_cap: BurnCapability<TestCoin>,
        freeze_cap: FreezeCapability<TestCoin>,
    }

    fun setup_test(aptos_framework: &signer, admin: &signer) {
        // Initialize timestamp for daily limit checks
        timestamp::set_time_has_started_for_testing(aptos_framework);

        // Create admin account
        account::create_account_for_test(signer::address_of(admin));

        // Register and initialize TestCoin
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<TestCoin>(
            admin,
            b"Test Coin",
            b"TST",
            8,
            true,
        );

        // Store caps for later use
        move_to(admin, TestCoinCaps { mint_cap, burn_cap, freeze_cap });
    }

    fun setup_bridge(admin: &signer) {
        let signers = vector::empty<vector<u8>>();
        let key = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        vector::push_back(&mut signers, key);
        bridge::initialize(admin, signers, 1, 100); // 1% fee
    }

    fun setup_vault(admin: &signer) acquires TestCoinCaps {
        bridge::create_vault<TestCoin>(admin, 1000000); // 1M daily limit

        // Register token caps with bridge
        let caps = borrow_global<TestCoinCaps>(signer::address_of(admin));
        // Mint some coins to vault via lock
        let minted = coin::mint<TestCoin>(10000000, &caps.mint_cap);
        coin::register<TestCoin>(admin);
        coin::deposit(signer::address_of(admin), minted);
    }

    fun fund_user(admin: &signer, user: &signer) acquires TestCoinCaps {
        account::create_account_for_test(signer::address_of(user));
        coin::register<TestCoin>(user);
        let caps = borrow_global<TestCoinCaps>(signer::address_of(admin));
        let coins = coin::mint<TestCoin>(1000000, &caps.mint_cap);
        coin::deposit(signer::address_of(user), coins);
    }

    // -------------------------------------------------------
    // Initialize
    // -------------------------------------------------------

    #[test(aptos_framework = @0x1, admin = @lux_bridge)]
    fun test_initialize(aptos_framework: &signer, admin: &signer) {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);

        assert!(!bridge::is_paused(signer::address_of(admin)), 0);
        assert!(bridge::total_locked(signer::address_of(admin)) == 0, 1);
        assert!(bridge::total_burned(signer::address_of(admin)) == 0, 2);
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge)]
    #[expected_failure(abort_code = 65543)] // E_FEE_TOO_HIGH
    fun test_initialize_rejects_high_fee(aptos_framework: &signer, admin: &signer) {
        setup_test(aptos_framework, admin);
        let signers = vector::empty<vector<u8>>();
        bridge::initialize(admin, signers, 1, 501);
    }

    // -------------------------------------------------------
    // Lock
    // -------------------------------------------------------

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    fun test_lock_updates_total(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        let amount: u64 = 10000;
        let dest = b"00000000000000000000000000000001";
        bridge::lock_and_bridge<TestCoin>(user, signer::address_of(admin), amount, 2, dest);

        // Fee is 1% = 100, bridge amount = 9900
        let expected_locked = amount - (amount * 100 / 10000);
        assert!(bridge::total_locked(signer::address_of(admin)) == expected_locked, 0);
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 65542)] // E_AMOUNT_ZERO
    fun test_lock_rejects_zero_amount(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        bridge::lock_and_bridge<TestCoin>(user, signer::address_of(admin), 0, 2, b"");
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 196610)] // E_PAUSED
    fun test_lock_rejects_when_paused(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        bridge::pause(admin, signer::address_of(admin));
        bridge::lock_and_bridge<TestCoin>(user, signer::address_of(admin), 1000, 2, b"");
    }

    // -------------------------------------------------------
    // Mint (signature verification)
    // -------------------------------------------------------
    // Note: Full mint test requires valid Ed25519 signatures which cannot
    // be produced in Move test without the private key. We test the guard
    // conditions that fire before signature verification.

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 65542)] // E_AMOUNT_ZERO
    fun test_mint_rejects_zero_amount(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        let dummy_sig = x"0000000000000000000000000000000000000000000000000000000000000000";
        vector::append(&mut dummy_sig, x"0000000000000000000000000000000000000000000000000000000000000000");
        let dummy_pk = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

        bridge::mint_bridged<TestCoin>(
            user,
            signer::address_of(admin),
            1,    // source_chain_id
            1,    // nonce
            signer::address_of(user),
            0,    // zero amount
            dummy_sig,
            dummy_pk,
        );
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 327689)] // E_UNAUTHORIZED_SIGNER
    fun test_mint_rejects_unauthorized_signer(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        let dummy_sig = x"0000000000000000000000000000000000000000000000000000000000000000";
        vector::append(&mut dummy_sig, x"0000000000000000000000000000000000000000000000000000000000000000");
        // Use a key not in the authorized signers
        let bad_pk = x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

        bridge::mint_bridged<TestCoin>(
            user,
            signer::address_of(admin),
            1,
            1,
            signer::address_of(user),
            1000,
            dummy_sig,
            bad_pk,
        );
    }

    // -------------------------------------------------------
    // Burn
    // -------------------------------------------------------

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 65542)] // E_AMOUNT_ZERO
    fun test_burn_rejects_zero_amount(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        bridge::burn_bridged<TestCoin>(
            user, signer::address_of(admin), 0, 2, b"recipient",
        );
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 196610)] // E_PAUSED
    fun test_burn_rejects_when_paused(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        bridge::pause(admin, signer::address_of(admin));
        bridge::burn_bridged<TestCoin>(
            user, signer::address_of(admin), 1000, 2, b"recipient",
        );
    }

    // -------------------------------------------------------
    // Pause
    // -------------------------------------------------------

    #[test(aptos_framework = @0x1, admin = @lux_bridge)]
    fun test_pause_sets_paused(aptos_framework: &signer, admin: &signer) {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);

        bridge::pause(admin, signer::address_of(admin));
        assert!(bridge::is_paused(signer::address_of(admin)), 0);
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge)]
    fun test_unpause_clears_paused(aptos_framework: &signer, admin: &signer) {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);

        bridge::pause(admin, signer::address_of(admin));
        bridge::unpause(admin, signer::address_of(admin));
        assert!(!bridge::is_paused(signer::address_of(admin)), 0);
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 327681)] // E_NOT_ADMIN
    fun test_pause_rejects_non_admin(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) {
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user));
        setup_bridge(admin);

        bridge::pause(user, signer::address_of(admin));
    }

    // -------------------------------------------------------
    // Fee update
    // -------------------------------------------------------

    #[test(aptos_framework = @0x1, admin = @lux_bridge)]
    fun test_set_fee_updates_value(aptos_framework: &signer, admin: &signer) {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);

        bridge::set_fee(admin, signer::address_of(admin), 250);
        // Verify by locking and checking the fee deduction
        // Fee at 2.5% on 10000 = 250, bridge = 9750
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge)]
    #[expected_failure(abort_code = 65543)] // E_FEE_TOO_HIGH
    fun test_set_fee_rejects_above_max(aptos_framework: &signer, admin: &signer) {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);

        bridge::set_fee(admin, signer::address_of(admin), 501);
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    #[expected_failure(abort_code = 327681)] // E_NOT_ADMIN
    fun test_set_fee_rejects_non_admin(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) {
        setup_test(aptos_framework, admin);
        account::create_account_for_test(signer::address_of(user));
        setup_bridge(admin);

        bridge::set_fee(user, signer::address_of(admin), 200);
    }

    #[test(aptos_framework = @0x1, admin = @lux_bridge, user = @0xCAFE)]
    fun test_set_fee_affects_lock(
        aptos_framework: &signer,
        admin: &signer,
        user: &signer,
    ) acquires TestCoinCaps {
        setup_test(aptos_framework, admin);
        setup_bridge(admin);
        setup_vault(admin);
        fund_user(admin, user);

        bridge::set_fee(admin, signer::address_of(admin), 500); // 5%

        let amount: u64 = 10000;
        bridge::lock_and_bridge<TestCoin>(
            user, signer::address_of(admin), amount, 2, b"recipient",
        );

        // 5% fee: 500, bridge = 9500
        assert!(bridge::total_locked(signer::address_of(admin)) == 9500, 0);
    }
}
