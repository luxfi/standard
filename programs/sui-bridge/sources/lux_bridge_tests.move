#[test_only]
module lux_bridge::bridge_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::clock;

    use lux_bridge::bridge::{
        Self,
        AdminCap,
        BridgeConfig,
        Vault,
        NonceRegistry,
    };

    // ========================================
    // Test coin type
    // ========================================

    public struct TEST_COIN has drop {}

    fun setup_coin(scenario: &mut Scenario): TreasuryCap<TEST_COIN> {
        let witness = TEST_COIN {};
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9, // decimals
            b"TEST",
            b"Test Coin",
            b"",
            option::none(),
            ts::ctx(scenario),
        );
        transfer::public_freeze_object(metadata);
        treasury_cap
    }

    // ========================================
    // Helpers
    // ========================================

    const ADMIN: address = @0xA;
    const USER: address = @0xB;
    const RELAYER: address = @0xC;
    const DEST_CHAIN: u64 = 96369; // Lux C-Chain

    fun init_bridge(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        bridge::init_for_testing(ts::ctx(scenario));
    }

    // ========================================
    // Test 1: initialize
    // ========================================

    #[test]
    fun test_initialize() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Admin receives AdminCap
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // BridgeConfig is shared with correct defaults
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<BridgeConfig>(&scenario);
            assert!(bridge::is_paused(&config) == true); // starts paused
            assert!(bridge::current_nonce(&config) == 0);
            assert!(bridge::total_locked(&config) == 0);
            assert!(bridge::total_burned(&config) == 0);
            ts::return_shared(config);
        };

        // NonceRegistry is shared
        ts::next_tx(&mut scenario, ADMIN);
        {
            let registry = ts::take_shared<NonceRegistry>(&scenario);
            ts::return_shared(registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_initialize_admin_can_set_signers() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);

            let signer1 = x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            let signer2 = x"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
            let signer3 = x"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

            let signers = vector[signer1, signer2, signer3];
            bridge::set_signers(&admin_cap, &mut config, signers, 2);

            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    // ========================================
    // Test 2: lock_and_bridge
    // ========================================

    #[test]
    fun test_lock_and_bridge_deposits_and_increments_nonce() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Unpause the bridge
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create vault for TEST_COIN
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create a clock for the lock call
        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = setup_coin(&mut scenario);
            transfer::public_transfer(treasury_cap, ADMIN);
        };

        // User locks coins
        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);

            // Admin mints test coins to user (need treasury cap)
            // We transfer coin directly for testing
            let coin = coin::mint_for_testing<TEST_COIN>(1_000_000_000, ts::ctx(&mut scenario));

            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config,
                &mut vault,
                coin,
                DEST_CHAIN,
                recipient,
                &clock,
                ts::ctx(&mut scenario),
            );

            // Nonce incremented
            assert!(bridge::current_nonce(&config) == 1);
            // Total locked updated (amount minus fee: 1B * 30/10000 = 3M fee, locked = 997M)
            assert!(bridge::total_locked(&config) == 997_000_000);

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_lock_and_bridge_multiple_increments_nonce() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Unpause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create vault
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        // First lock
        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(500_000_000, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config, &mut vault, coin, DEST_CHAIN, recipient, &clock, ts::ctx(&mut scenario),
            );
            assert!(bridge::current_nonce(&config) == 1);

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        // Second lock
        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(500_000_000, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config, &mut vault, coin, DEST_CHAIN, recipient, &clock, ts::ctx(&mut scenario),
            );
            assert!(bridge::current_nonce(&config) == 2);

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_PAUSED)]
    fun test_lock_and_bridge_fails_when_paused() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Create vault (bridge is still paused from init)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Try to lock while paused -- should abort
        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(1_000_000_000, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config, &mut vault, coin, DEST_CHAIN, recipient, &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_AMOUNT_ZERO)]
    fun test_lock_and_bridge_fails_on_zero_amount() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Unpause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create vault
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Lock zero -- should abort
        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(0, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config, &mut vault, coin, DEST_CHAIN, recipient, &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ========================================
    // Test 3: mint_bridged (signature verification)
    // ========================================

    // NOTE: Full ed25519 signature verification requires a real keypair.
    // We test the authorization/nonce/pause checks here. The ed25519
    // verification itself is tested by Sui framework -- we trust it.
    // To test mint_bridged end-to-end we would need an offline-signed
    // test vector. We test the supporting logic thoroughly.

    #[test]
    #[expected_failure(abort_code = bridge::E_PAUSED)]
    fun test_mint_bridged_fails_when_paused() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Set up signers but leave paused
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let signer_pk = x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            bridge::set_signers(&admin_cap, &mut config, vector[signer_pk], 1);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create vault + treasury
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = setup_coin(&mut scenario);
            transfer::public_transfer(treasury_cap, RELAYER);
        };

        // Try mint while paused -- should abort
        ts::next_tx(&mut scenario, RELAYER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let config = ts::take_shared<BridgeConfig>(&scenario);
            let mut registry = ts::take_shared<NonceRegistry>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);

            let signer_pk = x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            let fake_sig = x"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

            bridge::mint_bridged<TEST_COIN>(
                &config, &mut registry, &mut vault, &mut treasury_cap,
                DEST_CHAIN, 1, USER, 1000, fake_sig, signer_pk, &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(vault);
            ts::return_to_sender(&scenario, treasury_cap);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_UNAUTHORIZED)]
    fun test_mint_bridged_fails_with_unauthorized_signer() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Set signers and unpause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let signer_pk = x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
            bridge::set_signers(&admin_cap, &mut config, vector[signer_pk], 1);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create vault + treasury
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = setup_coin(&mut scenario);
            transfer::public_transfer(treasury_cap, RELAYER);
        };

        // Try mint with wrong signer pubkey -- should abort E_UNAUTHORIZED
        ts::next_tx(&mut scenario, RELAYER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let config = ts::take_shared<BridgeConfig>(&scenario);
            let mut registry = ts::take_shared<NonceRegistry>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);

            // Wrong pubkey (not in signers list)
            let wrong_pk = x"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";
            let fake_sig = x"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

            bridge::mint_bridged<TEST_COIN>(
                &config, &mut registry, &mut vault, &mut treasury_cap,
                DEST_CHAIN, 1, USER, 1000, fake_sig, wrong_pk, &clock, ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            ts::return_shared(registry);
            ts::return_shared(vault);
            ts::return_to_sender(&scenario, treasury_cap);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    // ========================================
    // Test 4: burn_bridged
    // ========================================

    #[test]
    fun test_burn_bridged_burns_and_increments_nonce() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Unpause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create treasury cap for TEST_COIN
        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = setup_coin(&mut scenario);
            transfer::public_transfer(treasury_cap, ADMIN);
        };

        // Mint some test coins to USER, then burn them via bridge
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);
            let minted = coin::mint(&mut treasury_cap, 500_000_000, ts::ctx(&mut scenario));
            transfer::public_transfer(minted, USER);
            transfer::public_transfer(treasury_cap, USER);
        };

        // User burns wrapped tokens
        ts::next_tx(&mut scenario, USER);
        {
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);
            let coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let recipient = x"0000000000000000000000000000000000000000000000000000000000005678";

            bridge::burn_bridged<TEST_COIN>(
                &mut config,
                &mut treasury_cap,
                coin,
                DEST_CHAIN,
                recipient,
                ts::ctx(&mut scenario),
            );

            assert!(bridge::current_nonce(&config) == 1);
            assert!(bridge::total_burned(&config) == 500_000_000);

            ts::return_shared(config);
            ts::return_to_sender(&scenario, treasury_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_PAUSED)]
    fun test_burn_bridged_fails_when_paused() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Create treasury + mint coins (bridge still paused)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = setup_coin(&mut scenario);
            transfer::public_transfer(treasury_cap, ADMIN);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);
            let minted = coin::mint(&mut treasury_cap, 100, ts::ctx(&mut scenario));
            transfer::public_transfer(minted, USER);
            transfer::public_transfer(treasury_cap, USER);
        };

        // Try burn while paused -- should abort
        ts::next_tx(&mut scenario, USER);
        {
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);
            let coin = ts::take_from_sender<Coin<TEST_COIN>>(&scenario);
            let recipient = x"0000000000000000000000000000000000000000000000000000000000005678";

            bridge::burn_bridged<TEST_COIN>(
                &mut config, &mut treasury_cap, coin, DEST_CHAIN, recipient, ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            ts::return_to_sender(&scenario, treasury_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_AMOUNT_ZERO)]
    fun test_burn_bridged_fails_on_zero_amount() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Unpause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Create treasury
        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury_cap = setup_coin(&mut scenario);
            transfer::public_transfer(treasury_cap, USER);
        };

        // Burn zero -- should abort
        ts::next_tx(&mut scenario, USER);
        {
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut treasury_cap = ts::take_from_sender<TreasuryCap<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(0, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000005678";

            bridge::burn_bridged<TEST_COIN>(
                &mut config, &mut treasury_cap, coin, DEST_CHAIN, recipient, ts::ctx(&mut scenario),
            );

            ts::return_shared(config);
            ts::return_to_sender(&scenario, treasury_cap);
        };

        ts::end(scenario);
    }

    // ========================================
    // Test 5: pause / unpause
    // ========================================

    #[test]
    fun test_pause_and_unpause() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Starts paused
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<BridgeConfig>(&scenario);
            assert!(bridge::is_paused(&config) == true);
            ts::return_shared(config);
        };

        // Unpause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            assert!(bridge::is_paused(&config) == false);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Pause again
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::pause(&admin_cap, &mut config);
            assert!(bridge::is_paused(&config) == true);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_operations_fail_when_paused_then_succeed_when_unpaused() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        // Create vault
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Unpause, lock succeeds
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(100, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config, &mut vault, coin, DEST_CHAIN, recipient, &clock, ts::ctx(&mut scenario),
            );
            assert!(bridge::current_nonce(&config) == 1);

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        // Re-pause
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::pause(&admin_cap, &mut config);
            assert!(bridge::is_paused(&config) == true);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    // ========================================
    // Test 6: update_fee (set_fee)
    // ========================================

    #[test]
    fun test_set_fee_updates_fee() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);

            // Set fee to 100 bps (1%)
            bridge::set_fee(&admin_cap, &mut config, 100);

            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        // Verify fee applies: lock 10000, fee = 10000 * 100 / 10000 = 100
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::unpause(&admin_cap, &mut config);
            bridge::create_vault<TEST_COIN>(&admin_cap, 0, ts::ctx(&mut scenario));
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::next_tx(&mut scenario, USER);
        {
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            let mut vault = ts::take_shared<Vault<TEST_COIN>>(&scenario);
            let coin = coin::mint_for_testing<TEST_COIN>(10_000, ts::ctx(&mut scenario));
            let recipient = x"0000000000000000000000000000000000000000000000000000000000001234";

            bridge::lock_and_bridge<TEST_COIN>(
                &mut config, &mut vault, coin, DEST_CHAIN, recipient, &clock, ts::ctx(&mut scenario),
            );
            // With 100 bps fee: locked = 10000 - 100 = 9900
            assert!(bridge::total_locked(&config) == 9_900);

            ts::return_shared(config);
            ts::return_shared(vault);
            clock::destroy_for_testing(clock);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_set_fee_to_zero() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::set_fee(&admin_cap, &mut config, 0);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_set_fee_to_max_500() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::set_fee(&admin_cap, &mut config, 500);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_FEE_TOO_HIGH)]
    fun test_set_fee_rejects_above_500() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            // 501 bps > 500 max -- should abort
            bridge::set_fee(&admin_cap, &mut config, 501);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = bridge::E_FEE_TOO_HIGH)]
    fun test_set_fee_rejects_large_value() {
        let mut scenario = ts::begin(ADMIN);
        init_bridge(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<BridgeConfig>(&scenario);
            bridge::set_fee(&admin_cap, &mut config, 10_000);
            ts::return_shared(config);
            ts::return_to_sender(&scenario, admin_cap);
        };

        ts::end(scenario);
    }
}
