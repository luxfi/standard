#[cfg(test)]
mod tests {
    use super::LuxBridge;
    use super::ILuxBridge;
    use super::ILuxBridgeDispatcher;
    use super::ILuxBridgeDispatcherTrait;
    use starknet::{ContractAddress, contract_address_const, testing};
    use starknet::testing::{set_caller_address, set_block_timestamp};

    const ADMIN: felt252 = 0x1;
    const USER: felt252 = 0x2;
    const SIGNER: felt252 = 0xABCDEF;
    const TOKEN: felt252 = 0x100;

    fn admin_addr() -> ContractAddress {
        contract_address_const::<ADMIN>()
    }

    fn user_addr() -> ContractAddress {
        contract_address_const::<USER>()
    }

    fn token_addr() -> ContractAddress {
        contract_address_const::<TOKEN>()
    }

    fn deploy_bridge(fee_bps: u16) -> ILuxBridgeDispatcher {
        let contract = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref contract, admin_addr(), SIGNER, fee_bps);
        // Return dispatcher wrapping the test contract state
        ILuxBridgeDispatcher { contract_address: contract_address_const::<0x999>() }
    }

    // ================================================================
    // Constructor
    // ================================================================

    #[test]
    fn test_constructor_sets_initial_state() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        assert(bridge.is_paused(@state) == false, 'Should not be paused');
        assert(bridge.total_locked(@state) == 0, 'Locked should be 0');
        assert(bridge.total_burned(@state) == 0, 'Burned should be 0');
    }

    #[test]
    #[should_panic(expected: ('Fee too high',))]
    fn test_constructor_rejects_fee_above_500() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 501);
    }

    #[test]
    fn test_constructor_accepts_max_fee() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 500);
        // Should not panic
    }

    // ================================================================
    // Pause / Unpause
    // ================================================================

    #[test]
    fn test_admin_can_pause() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);
        assert(bridge.is_paused(@state) == true, 'Should be paused');
    }

    #[test]
    fn test_admin_can_unpause() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);
        bridge.unpause(ref state);
        assert(bridge.is_paused(@state) == false, 'Should not be paused');
    }

    #[test]
    #[should_panic(expected: ('Not admin',))]
    fn test_non_admin_cannot_pause() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);
    }

    #[test]
    #[should_panic(expected: ('Not admin',))]
    fn test_non_admin_cannot_unpause() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);

        set_caller_address(user_addr());
        bridge.unpause(ref state);
    }

    // ================================================================
    // Set Fee
    // ================================================================

    #[test]
    fn test_admin_can_set_fee() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.set_fee(ref state, 100);
        // No panic means success
    }

    #[test]
    #[should_panic(expected: ('Fee too high',))]
    fn test_set_fee_rejects_above_max() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.set_fee(ref state, 501);
    }

    #[test]
    #[should_panic(expected: ('Not admin',))]
    fn test_non_admin_cannot_set_fee() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.set_fee(ref state, 100);
    }

    // ================================================================
    // Set Signer
    // ================================================================

    #[test]
    fn test_admin_can_set_signer() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.set_signer(ref state, 0xDEADBEEF);
    }

    #[test]
    #[should_panic(expected: ('Not admin',))]
    fn test_non_admin_cannot_set_signer() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.set_signer(ref state, 0xDEADBEEF);
    }

    // ================================================================
    // Lock and Bridge
    // ================================================================

    #[test]
    fn test_lock_and_bridge_returns_nonce() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        let nonce = bridge.lock_and_bridge(ref state, token_addr(), 1000, 96369, 0xCAFE);
        assert(nonce == 1, 'First nonce should be 1');
    }

    #[test]
    fn test_lock_and_bridge_increments_nonce() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 0);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);

        let n1 = bridge.lock_and_bridge(ref state, token_addr(), 1000, 96369, 0xCAFE);
        let n2 = bridge.lock_and_bridge(ref state, token_addr(), 2000, 96369, 0xCAFE);
        assert(n1 == 1, 'First nonce');
        assert(n2 == 2, 'Second nonce');
    }

    #[test]
    fn test_lock_and_bridge_updates_total_locked() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 0); // 0 fee

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.lock_and_bridge(ref state, token_addr(), 5000, 96369, 0xCAFE);
        assert(bridge.total_locked(@state) == 5000, 'Should lock 5000');
    }

    #[test]
    fn test_lock_and_bridge_deducts_fee() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 100); // 1% fee

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.lock_and_bridge(ref state, token_addr(), 10000, 96369, 0xCAFE);
        // fee = 10000 * 100 / 10000 = 100, bridge_amount = 9900
        assert(bridge.total_locked(@state) == 9900, 'Should lock 9900 after fee');
    }

    #[test]
    #[should_panic(expected: ('Zero amount',))]
    fn test_lock_and_bridge_rejects_zero() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.lock_and_bridge(ref state, token_addr(), 0, 96369, 0xCAFE);
    }

    #[test]
    #[should_panic(expected: ('Bridge paused',))]
    fn test_lock_and_bridge_rejects_when_paused() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);

        set_caller_address(user_addr());
        bridge.lock_and_bridge(ref state, token_addr(), 1000, 96369, 0xCAFE);
    }

    // ================================================================
    // Burn Bridged
    // ================================================================

    #[test]
    fn test_burn_bridged_returns_nonce() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        let nonce = bridge.burn_bridged(ref state, token_addr(), 500, 96369, 0xBEEF);
        assert(nonce == 1, 'Burn nonce should be 1');
    }

    #[test]
    fn test_burn_bridged_updates_total_burned() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.burn_bridged(ref state, token_addr(), 500, 96369, 0xBEEF);
        assert(bridge.total_burned(@state) == 500, 'Should burn 500');
    }

    #[test]
    #[should_panic(expected: ('Zero amount',))]
    fn test_burn_bridged_rejects_zero() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.burn_bridged(ref state, token_addr(), 0, 96369, 0xBEEF);
    }

    #[test]
    #[should_panic(expected: ('Bridge paused',))]
    fn test_burn_bridged_rejects_when_paused() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);

        set_caller_address(user_addr());
        bridge.burn_bridged(ref state, token_addr(), 500, 96369, 0xBEEF);
    }

    // ================================================================
    // Mint Bridged
    // ================================================================

    #[test]
    #[should_panic(expected: ('Zero amount',))]
    fn test_mint_bridged_rejects_zero_amount() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.mint_bridged(ref state, 1, 1, user_addr(), 0, 0x0, 0x0);
    }

    #[test]
    #[should_panic(expected: ('Bridge paused',))]
    fn test_mint_bridged_rejects_when_paused() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 30);

        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);
        bridge.pause(ref state);

        set_caller_address(user_addr());
        bridge.mint_bridged(ref state, 1, 1, user_addr(), 1000, 0x0, 0x0);
    }

    // ================================================================
    // Shared nonce counter
    // ================================================================

    #[test]
    fn test_lock_and_burn_share_nonce_counter() {
        let mut state = LuxBridge::contract_state_for_testing();
        set_caller_address(admin_addr());
        LuxBridge::constructor(ref state, admin_addr(), SIGNER, 0);

        set_caller_address(user_addr());
        let mut bridge = LuxBridge::LuxBridgeImpl::new(ref state);

        let n1 = bridge.lock_and_bridge(ref state, token_addr(), 1000, 96369, 0xCAFE);
        let n2 = bridge.burn_bridged(ref state, token_addr(), 500, 96369, 0xBEEF);
        let n3 = bridge.lock_and_bridge(ref state, token_addr(), 2000, 96369, 0xCAFE);

        assert(n1 == 1, 'First op nonce');
        assert(n2 == 2, 'Second op nonce');
        assert(n3 == 3, 'Third op nonce');
    }
}
