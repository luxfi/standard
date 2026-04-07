use anchor_lang::prelude::*;

#[error_code]
pub enum BridgeError {
    #[msg("Bridge is paused")]
    Paused,
    #[msg("Invalid MPC signature")]
    InvalidSignature,
    #[msg("Nonce already processed")]
    NonceAlreadyProcessed,
    #[msg("Daily mint limit exceeded")]
    DailyMintLimitExceeded,
    #[msg("Unauthorized signer")]
    UnauthorizedSigner,
    #[msg("Invalid source chain")]
    InvalidSourceChain,
    #[msg("Amount too small")]
    AmountTooSmall,
    #[msg("Fee rate exceeds maximum (5%)")]
    FeeRateExceedsMax,
    #[msg("Token not registered")]
    TokenNotRegistered,
    #[msg("Insufficient vault balance")]
    InsufficientVaultBalance,
    #[msg("Ed25519 instruction not found in transaction")]
    Ed25519InstructionMissing,
    #[msg("Ed25519 signature verification failed")]
    Ed25519VerificationFailed,
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("No pending signer rotation")]
    NoPendingRotation,
    #[msg("Timelock has not elapsed (7 days)")]
    TimelockNotElapsed,
}
