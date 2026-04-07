/// Lux Bridge — StarkNet native bridge (Cairo)
///
/// StarkNet uses Cairo language compiled to Sierra/CASM.
/// STARK proofs for validity, no signature verification needed for L1→L2 messages.
/// For L2→L1 and cross-chain: ECDSA over Stark curve (native).
///
/// Token standard: ERC-20 (OpenZeppelin Cairo).

use starknet::ContractAddress;
use starknet::get_caller_address;
use starknet::get_block_timestamp;

#[starknet::interface]
trait ILuxBridge<TContractState> {
    fn lock_and_bridge(
        ref self: TContractState,
        token: ContractAddress,
        amount: u256,
        dest_chain_id: u64,
        recipient: felt252,
    ) -> u64;

    fn mint_bridged(
        ref self: TContractState,
        source_chain_id: u64,
        nonce: u64,
        recipient: ContractAddress,
        amount: u256,
        signature_r: felt252,
        signature_s: felt252,
    );

    fn burn_bridged(
        ref self: TContractState,
        token: ContractAddress,
        amount: u256,
        dest_chain_id: u64,
        recipient: felt252,
    ) -> u64;

    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn set_fee(ref self: TContractState, fee_bps: u16);
    fn set_signer(ref self: TContractState, signer: felt252);
    fn total_locked(self: @TContractState) -> u256;
    fn total_burned(self: @TContractState) -> u256;
    fn is_paused(self: @TContractState) -> bool;
}

#[starknet::contract]
mod LuxBridge {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use core::ecdsa::check_ecdsa_signature;
    use core::poseidon::poseidon_hash_span;

    const STARKNET_CHAIN_ID: u64 = 23448594291968334; // SN_MAIN

    #[storage]
    struct Storage {
        admin: ContractAddress,
        mpc_signer: felt252,        // Stark curve public key
        fee_bps: u16,
        paused: bool,
        outbound_nonce: u64,
        total_locked: u256,
        total_burned: u256,
        processed_nonces: Map<(u64, u64), bool>,  // (source_chain, nonce) -> processed
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Lock: LockEvent,
        Mint: MintEvent,
        Burn: BurnEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct LockEvent {
        #[key]
        source_chain: u64,
        #[key]
        dest_chain: u64,
        nonce: u64,
        sender: ContractAddress,
        recipient: felt252,
        amount: u256,
        fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct MintEvent {
        #[key]
        source_chain: u64,
        nonce: u64,
        recipient: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BurnEvent {
        #[key]
        source_chain: u64,
        #[key]
        dest_chain: u64,
        nonce: u64,
        sender: ContractAddress,
        recipient: felt252,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        mpc_signer: felt252,
        fee_bps: u16,
    ) {
        assert(fee_bps <= 500, 'Fee too high');
        self.admin.write(admin);
        self.mpc_signer.write(mpc_signer);
        self.fee_bps.write(fee_bps);
        self.paused.write(false);
        self.outbound_nonce.write(0);
        self.total_locked.write(0);
        self.total_burned.write(0);
    }

    #[abi(embed_v0)]
    impl LuxBridgeImpl of super::ILuxBridge<ContractState> {
        fn lock_and_bridge(
            ref self: ContractState,
            token: ContractAddress,
            amount: u256,
            dest_chain_id: u64,
            recipient: felt252,
        ) -> u64 {
            assert(!self.paused.read(), 'Bridge paused');
            assert(amount > 0, 'Zero amount');

            let fee_bps: u256 = self.fee_bps.read().into();
            let fee = amount * fee_bps / 10000;
            let bridge_amount = amount - fee;

            let new_nonce = self.outbound_nonce.read() + 1;
            self.outbound_nonce.write(new_nonce);
            self.total_locked.write(self.total_locked.read() + bridge_amount);

            self.emit(LockEvent {
                source_chain: STARKNET_CHAIN_ID,
                dest_chain: dest_chain_id,
                nonce: new_nonce,
                sender: get_caller_address(),
                recipient,
                amount: bridge_amount,
                fee,
            });

            new_nonce
        }

        fn mint_bridged(
            ref self: ContractState,
            source_chain_id: u64,
            nonce: u64,
            recipient: ContractAddress,
            amount: u256,
            signature_r: felt252,
            signature_s: felt252,
        ) {
            assert(!self.paused.read(), 'Bridge paused');
            assert(amount > 0, 'Zero amount');
            assert(!self.processed_nonces.read((source_chain_id, nonce)), 'Nonce processed');

            // Verify ECDSA over Stark curve
            let msg_hash = poseidon_hash_span(
                array![
                    'LUX_BRIDGE_MINT',
                    source_chain_id.into(),
                    nonce.into(),
                    amount.low.into(),
                ].span()
            );
            let valid = check_ecdsa_signature(msg_hash, self.mpc_signer.read(), signature_r, signature_s);
            assert(valid, 'Invalid signature');

            self.processed_nonces.write((source_chain_id, nonce), true);

            self.emit(MintEvent {
                source_chain: source_chain_id,
                nonce,
                recipient,
                amount,
            });
        }

        fn burn_bridged(
            ref self: ContractState,
            token: ContractAddress,
            amount: u256,
            dest_chain_id: u64,
            recipient: felt252,
        ) -> u64 {
            assert(!self.paused.read(), 'Bridge paused');
            assert(amount > 0, 'Zero amount');

            let new_nonce = self.outbound_nonce.read() + 1;
            self.outbound_nonce.write(new_nonce);
            self.total_burned.write(self.total_burned.read() + amount);

            self.emit(BurnEvent {
                source_chain: STARKNET_CHAIN_ID,
                dest_chain: dest_chain_id,
                nonce: new_nonce,
                sender: get_caller_address(),
                recipient,
                amount,
            });

            new_nonce
        }

        fn pause(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), 'Not admin');
            self.paused.write(true);
        }

        fn unpause(ref self: ContractState) {
            assert(get_caller_address() == self.admin.read(), 'Not admin');
            self.paused.write(false);
        }

        fn set_fee(ref self: ContractState, fee_bps: u16) {
            assert(get_caller_address() == self.admin.read(), 'Not admin');
            assert(fee_bps <= 500, 'Fee too high');
            self.fee_bps.write(fee_bps);
        }

        fn set_signer(ref self: ContractState, signer: felt252) {
            assert(get_caller_address() == self.admin.read(), 'Not admin');
            self.mpc_signer.write(signer);
        }

        fn total_locked(self: @ContractState) -> u256 { self.total_locked.read() }
        fn total_burned(self: @ContractState) -> u256 { self.total_burned.read() }
        fn is_paused(self: @ContractState) -> bool { self.paused.read() }
    }
}
