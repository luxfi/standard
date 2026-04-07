use anchor_lang::prelude::*;

/// Default operational delay for signer rotation (cross-chain coordination, NOT security).
/// Configurable by admin. Default 24h gives relayers time to update all chains atomically.
pub const DEFAULT_ROTATION_DELAY: i64 = 24 * 60 * 60; // 24 hours
pub const MAX_ROTATION_DELAY: i64 = 7 * 24 * 60 * 60; // 7 days max

/// Global bridge configuration — one per program deployment.
/// PDA seeds: ["bridge_config"]
#[account]
pub struct BridgeConfig {
    /// Admin who can register tokens, update signers, pause
    pub admin: Pubkey,
    /// MPC threshold signer public keys (Ed25519, 32 bytes each)
    pub mpc_signers: [Pubkey; 3],
    /// Signing threshold (e.g., 2 of 3)
    pub threshold: u8,
    /// Bridge fee in basis points (0-500 = 0-5%)
    pub fee_bps: u16,
    /// Fee collector address
    pub fee_collector: Pubkey,
    /// Emergency pause flag
    pub paused: bool,
    /// Outbound nonce counter (for lock/burn events)
    pub outbound_nonce: u64,
    /// Solana chain ID in the Lux bridge namespace
    pub chain_id: u64,
    /// Bump seed for PDA derivation
    pub bump: u8,
    // ── Signer rotation (operational delay for cross-chain coordination) ──
    /// Operational delay in seconds (default 24h, max 7d, 0 = instant)
    pub rotation_delay: i64,
    /// Pending new signers (zeroed = no pending rotation)
    pub pending_signers: [Pubkey; 3],
    /// Pending new threshold
    pub pending_threshold: u8,
    /// Unix timestamp when pending signers become executable
    pub pending_signers_eta: i64,
}

impl BridgeConfig {
    pub const LEN: usize = 8  // discriminator
        + 32                   // admin
        + 32 * 3               // mpc_signers
        + 1                    // threshold
        + 2                    // fee_bps
        + 32                   // fee_collector
        + 1                    // paused
        + 8                    // outbound_nonce
        + 8                    // chain_id
        + 1                    // bump
        + 8                    // rotation_delay
        + 32 * 3               // pending_signers
        + 1                    // pending_threshold
        + 8;                   // pending_signers_eta

    pub const SEED: &'static [u8] = b"bridge_config";

    pub fn next_nonce(&mut self) -> u64 {
        let nonce = self.outbound_nonce;
        self.outbound_nonce += 1;
        nonce
    }

    pub fn has_pending_rotation(&self) -> bool {
        self.pending_signers_eta > 0
    }
}
