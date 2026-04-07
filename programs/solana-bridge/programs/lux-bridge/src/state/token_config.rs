use anchor_lang::prelude::*;

/// Per-token bridge configuration.
/// PDA seeds: ["token_config", token_mint.key()]
#[account]
pub struct TokenConfig {
    /// SPL token mint address
    pub mint: Pubkey,
    /// PDA-controlled vault holding locked native tokens
    pub vault: Pubkey,
    /// Wrapped token mint (for minting bridged representations)
    pub wrapped_mint: Pubkey,
    /// Whether this is a native token (lock/release) or wrapped (mint/burn)
    pub is_native: bool,
    /// Daily mint limit (0 = unlimited)
    pub daily_mint_limit: u64,
    /// Amount minted in current period
    pub daily_minted: u64,
    /// Period start timestamp (resets every 86400 seconds)
    pub period_start: i64,
    /// Whether this token is active
    pub active: bool,
    /// Bump seed
    pub bump: u8,
}

impl TokenConfig {
    pub const LEN: usize = 8  // discriminator
        + 32                   // mint
        + 32                   // vault
        + 32                   // wrapped_mint
        + 1                    // is_native
        + 8                    // daily_mint_limit
        + 8                    // daily_minted
        + 8                    // period_start
        + 1                    // active
        + 1;                   // bump

    pub const SEED: &'static [u8] = b"token_config";

    /// Check and update daily mint tracking. Returns error if limit exceeded.
    pub fn check_daily_limit(&mut self, amount: u64, now: i64) -> Result<()> {
        if self.daily_mint_limit == 0 {
            return Ok(()); // unlimited
        }
        // Reset period if 24h passed
        if now >= self.period_start + 86400 {
            self.daily_minted = 0;
            self.period_start = now;
        }
        let new_total = self.daily_minted.checked_add(amount)
            .ok_or(error!(crate::errors::BridgeError::Overflow))?;
        if new_total > self.daily_mint_limit {
            return Err(error!(crate::errors::BridgeError::DailyMintLimitExceeded));
        }
        self.daily_minted = new_total;
        Ok(())
    }
}

/// Tracks processed inbound nonces to prevent replay.
/// PDA seeds: ["nonce_tracker", source_chain_id.to_le_bytes()]
#[account]
pub struct NonceTracker {
    pub source_chain_id: u64,
    /// Bitmap of processed nonces (supports up to 256 * 32 = 8192 nonces per account)
    /// For higher nonce counts, create additional NonceTracker accounts with offset.
    pub bitmap: [u8; 1024],
    pub bump: u8,
}

impl NonceTracker {
    pub const LEN: usize = 8 + 8 + 1024 + 1;
    pub const SEED: &'static [u8] = b"nonce_tracker";

    pub fn is_processed(&self, nonce: u64) -> bool {
        let idx = (nonce as usize) / 8;
        let bit = (nonce as usize) % 8;
        if idx >= self.bitmap.len() {
            return false;
        }
        (self.bitmap[idx] >> bit) & 1 == 1
    }

    pub fn mark_processed(&mut self, nonce: u64) -> Result<()> {
        let idx = (nonce as usize) / 8;
        let bit = (nonce as usize) % 8;
        if idx >= self.bitmap.len() {
            return Err(error!(crate::errors::BridgeError::Overflow));
        }
        self.bitmap[idx] |= 1 << bit;
        Ok(())
    }
}
