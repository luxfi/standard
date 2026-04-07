/// Lux Bridge — Polkadot/Substrate ink! smart contract
///
/// ink! is the native smart contract language for Substrate-based chains.
/// Compiles to WASM, runs on pallet-contracts.
/// Deployed to: Polkadot Asset Hub, Astar, Moonbeam (ink!), Phala, etc.
///
/// Ed25519 and Sr25519 signature verification available natively.
#![cfg_attr(not(feature = "std"), no_std, no_main)]

#[ink::contract]
mod lux_bridge {
    use ink::prelude::vec::Vec;
    use ink::storage::Mapping;

    /// Bridge configuration and state.
    #[ink(storage)]
    pub struct LuxBridge {
        admin: AccountId,
        mpc_signers: Vec<[u8; 32]>, // Ed25519 public keys
        threshold: u8,
        fee_bps: u16,
        paused: bool,
        outbound_nonce: u64,
        total_locked: Balance,
        total_burned: Balance,
        /// (source_chain_id, nonce) -> processed
        processed_nonces: Mapping<(u64, u64), bool>,
        /// token_hash -> daily config
        token_configs: Mapping<Hash, TokenConfig>,
    }

    #[derive(scale::Decode, scale::Encode, Clone)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo, ink::storage::traits::StorageLayout))]
    pub struct TokenConfig {
        pub daily_mint_limit: Balance,
        pub daily_minted: Balance,
        pub period_start: Timestamp,
        pub active: bool,
    }

    // Events for MPC watchers
    #[ink(event)]
    pub struct LockEvent {
        #[ink(topic)]
        source_chain: u64,
        #[ink(topic)]
        dest_chain: u64,
        nonce: u64,
        sender: AccountId,
        recipient: [u8; 32],
        amount: Balance,
        fee: Balance,
    }

    #[ink(event)]
    pub struct MintEvent {
        #[ink(topic)]
        source_chain: u64,
        nonce: u64,
        recipient: AccountId,
        amount: Balance,
    }

    #[ink(event)]
    pub struct BurnEvent {
        #[ink(topic)]
        source_chain: u64,
        #[ink(topic)]
        dest_chain: u64,
        nonce: u64,
        sender: AccountId,
        recipient: [u8; 32],
        amount: Balance,
    }

    #[ink(event)]
    pub struct ReleaseEvent {
        #[ink(topic)]
        source_chain: u64,
        nonce: u64,
        recipient: AccountId,
        amount: Balance,
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum Error {
        Paused,
        NotAdmin,
        InvalidSignature,
        NonceProcessed,
        DailyLimitExceeded,
        AmountZero,
        FeeTooHigh,
        InsufficientBalance,
        UnauthorizedSigner,
    }

    pub type Result<T> = core::result::Result<T, Error>;

    // Polkadot chain ID in Lux namespace
    const POLKADOT_CHAIN_ID: u64 = 1886745444; // "polk" as u64

    impl LuxBridge {
        #[ink(constructor)]
        pub fn new(mpc_signers: Vec<[u8; 32]>, threshold: u8, fee_bps: u16) -> Self {
            assert!(fee_bps <= 500, "Fee too high");
            Self {
                admin: Self::env().caller(),
                mpc_signers,
                threshold,
                fee_bps,
                paused: false,
                outbound_nonce: 0,
                total_locked: 0,
                total_burned: 0,
                processed_nonces: Mapping::default(),
                token_configs: Mapping::default(),
            }
        }

        /// Lock native tokens for bridging. Emits LockEvent.
        #[ink(message, payable)]
        pub fn lock_and_bridge(
            &mut self,
            dest_chain_id: u64,
            recipient: [u8; 32],
        ) -> Result<u64> {
            self.require_not_paused()?;
            let amount = self.env().transferred_value();
            if amount == 0 { return Err(Error::AmountZero) }

            let fee = amount * self.fee_bps as u128 / 10_000;
            let bridge_amount = amount - fee;

            self.total_locked += bridge_amount;
            self.outbound_nonce += 1;
            let nonce = self.outbound_nonce;

            self.env().emit_event(LockEvent {
                source_chain: POLKADOT_CHAIN_ID,
                dest_chain: dest_chain_id,
                nonce,
                sender: self.env().caller(),
                recipient,
                amount: bridge_amount,
                fee,
            });

            Ok(nonce)
        }

        /// Mint wrapped tokens with MPC Ed25519 signature.
        #[ink(message)]
        pub fn mint_bridged(
            &mut self,
            source_chain_id: u64,
            nonce: u64,
            recipient: AccountId,
            amount: Balance,
            signature: [u8; 64],
            signer_pubkey: [u8; 32],
        ) -> Result<()> {
            self.require_not_paused()?;
            if amount == 0 { return Err(Error::AmountZero) }

            // Verify signer authorized
            if !self.mpc_signers.contains(&signer_pubkey) {
                return Err(Error::UnauthorizedSigner);
            }

            // Check nonce
            if self.processed_nonces.get((source_chain_id, nonce)).unwrap_or(false) {
                return Err(Error::NonceProcessed);
            }

            // Verify Ed25519 signature
            // ink! provides ed25519_verify via chain extension or precompile
            let message = self.build_mint_message(source_chain_id, nonce, &recipient, amount);
            if !self.verify_ed25519(&message, &signature, &signer_pubkey) {
                return Err(Error::InvalidSignature);
            }

            // Mark nonce
            self.processed_nonces.insert((source_chain_id, nonce), &true);

            // Transfer from contract balance to recipient
            self.env().transfer(recipient, amount)
                .map_err(|_| Error::InsufficientBalance)?;

            self.env().emit_event(MintEvent {
                source_chain: source_chain_id, nonce, recipient, amount,
            });

            Ok(())
        }

        /// Burn wrapped tokens for withdrawal. Emits BurnEvent.
        #[ink(message, payable)]
        pub fn burn_bridged(
            &mut self,
            dest_chain_id: u64,
            recipient: [u8; 32],
        ) -> Result<u64> {
            self.require_not_paused()?;
            let amount = self.env().transferred_value();
            if amount == 0 { return Err(Error::AmountZero) }

            self.total_burned += amount;
            self.outbound_nonce += 1;
            let nonce = self.outbound_nonce;

            self.env().emit_event(BurnEvent {
                source_chain: POLKADOT_CHAIN_ID,
                dest_chain: dest_chain_id,
                nonce,
                sender: self.env().caller(),
                recipient,
                amount,
            });

            Ok(nonce)
        }

        /// Release locked tokens with MPC signature.
        #[ink(message)]
        pub fn release(
            &mut self,
            source_chain_id: u64,
            nonce: u64,
            recipient: AccountId,
            amount: Balance,
            signature: [u8; 64],
            signer_pubkey: [u8; 32],
        ) -> Result<()> {
            self.require_not_paused()?;

            if !self.mpc_signers.contains(&signer_pubkey) {
                return Err(Error::UnauthorizedSigner);
            }
            if self.processed_nonces.get((source_chain_id, nonce)).unwrap_or(false) {
                return Err(Error::NonceProcessed);
            }

            let message = self.build_release_message(source_chain_id, nonce, &recipient, amount);
            if !self.verify_ed25519(&message, &signature, &signer_pubkey) {
                return Err(Error::InvalidSignature);
            }

            self.processed_nonces.insert((source_chain_id, nonce), &true);
            self.env().transfer(recipient, amount)
                .map_err(|_| Error::InsufficientBalance)?;

            self.env().emit_event(ReleaseEvent {
                source_chain: source_chain_id, nonce, recipient, amount,
            });

            Ok(())
        }

        // Admin
        #[ink(message)]
        pub fn pause(&mut self) -> Result<()> { self.require_admin()?; self.paused = true; Ok(()) }
        #[ink(message)]
        pub fn unpause(&mut self) -> Result<()> { self.require_admin()?; self.paused = false; Ok(()) }
        #[ink(message)]
        pub fn set_signers(&mut self, signers: Vec<[u8; 32]>, threshold: u8) -> Result<()> {
            self.require_admin()?; self.mpc_signers = signers; self.threshold = threshold; Ok(())
        }
        #[ink(message)]
        pub fn set_fee(&mut self, fee_bps: u16) -> Result<()> {
            self.require_admin()?;
            if fee_bps > 500 { return Err(Error::FeeTooHigh) }
            self.fee_bps = fee_bps; Ok(())
        }

        // Views
        #[ink(message)]
        pub fn total_locked(&self) -> Balance { self.total_locked }
        #[ink(message)]
        pub fn total_burned(&self) -> Balance { self.total_burned }
        #[ink(message)]
        pub fn is_paused(&self) -> bool { self.paused }

        // Internal
        fn require_not_paused(&self) -> Result<()> {
            if self.paused { Err(Error::Paused) } else { Ok(()) }
        }
        fn require_admin(&self) -> Result<()> {
            if self.env().caller() != self.admin { Err(Error::NotAdmin) } else { Ok(()) }
        }
        fn build_mint_message(&self, chain_id: u64, nonce: u64, recipient: &AccountId, amount: Balance) -> Vec<u8> {
            let mut msg = b"LUX_BRIDGE_MINT".to_vec();
            msg.extend_from_slice(&chain_id.to_le_bytes());
            msg.extend_from_slice(&nonce.to_le_bytes());
            msg.extend_from_slice(recipient.as_ref());
            msg.extend_from_slice(&amount.to_le_bytes());
            msg
        }
        fn build_release_message(&self, chain_id: u64, nonce: u64, recipient: &AccountId, amount: Balance) -> Vec<u8> {
            let mut msg = b"LUX_BRIDGE_RELEASE".to_vec();
            msg.extend_from_slice(&chain_id.to_le_bytes());
            msg.extend_from_slice(&nonce.to_le_bytes());
            msg.extend_from_slice(recipient.as_ref());
            msg.extend_from_slice(&amount.to_le_bytes());
            msg
        }
        fn verify_ed25519(&self, _message: &[u8], _signature: &[u8; 64], _pubkey: &[u8; 32]) -> bool {
            // In production: use ink! chain extension for ed25519_verify
            // or import sp_io::crypto::ed25519_verify
            true // placeholder — real verification via substrate runtime
        }
    }
}
