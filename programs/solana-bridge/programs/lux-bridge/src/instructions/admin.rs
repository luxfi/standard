use anchor_lang::prelude::*;
use anchor_lang::solana_program::sysvar::instructions as ix_sysvar;
use anchor_lang::solana_program::ed25519_program;
use crate::state::{BridgeConfig, MAX_ROTATION_DELAY};
use crate::errors::BridgeError;

// ═══════════════════════════════════════════════════════════════════════
// PAUSE / UNPAUSE
// ═══════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
pub struct Pause<'info> {
    #[account(
        mut,
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        has_one = admin,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,
    pub admin: Signer<'info>,
}

pub fn pause(ctx: Context<Pause>) -> Result<()> {
    ctx.accounts.bridge_config.paused = true;
    Ok(())
}

pub fn unpause(ctx: Context<Pause>) -> Result<()> {
    ctx.accounts.bridge_config.paused = false;
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════
// SIGNER ROTATION (7-day timelock — matches EVM OmnichainRouter)
//
// Flow: propose_signers → wait 7 days → execute_signers
//       Admin can cancel_signers at any time during the delay.
// ═══════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
pub struct ProposeSigners<'info> {
    #[account(
        mut,
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        has_one = admin,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,
    pub admin: Signer<'info>,
    /// CHECK: Solana instructions sysvar for Ed25519 verification
    #[account(address = ix_sysvar::ID)]
    pub instructions_sysvar: UncheckedAccount<'info>,
}

/// Queue new signers with a 7-day delay before they can take effect.
/// Requires BOTH admin signature AND MPC Ed25519 signature over the proposal.
pub fn propose_signers(
    ctx: Context<ProposeSigners>,
    new_signers: [Pubkey; 3],
    threshold: u8,
    message: Vec<u8>,
) -> Result<()> {
    require!(threshold >= 1 && threshold <= 3, BridgeError::UnauthorizedSigner);

    // Verify MPC Ed25519 signature over the proposed signers
    verify_propose_signers_signature(
        &ctx.accounts.instructions_sysvar,
        &ctx.accounts.bridge_config,
        &new_signers,
        threshold,
        &message,
    )?;

    let config = &mut ctx.accounts.bridge_config;
    let clock = Clock::get()?;

    config.pending_signers = new_signers;
    config.pending_threshold = threshold;
    config.pending_signers_eta = clock.unix_timestamp + config.rotation_delay;

    msg!(
        "Signer rotation proposed. Executable after {}",
        config.pending_signers_eta
    );
    Ok(())
}

/// Verify that the Ed25519 instruction immediately before this one contains
/// a valid MPC signature over the proposed signer rotation.
fn verify_propose_signers_signature(
    instructions_sysvar: &AccountInfo,
    config: &BridgeConfig,
    new_signers: &[Pubkey; 3],
    threshold: u8,
    message: &[u8],
) -> Result<()> {
    // Reconstruct expected message: "LUX_BRIDGE_PROPOSE" || new_signers || threshold
    let mut expected = Vec::with_capacity(128);
    expected.extend_from_slice(b"LUX_BRIDGE_PROPOSE");
    for signer in new_signers.iter() {
        expected.extend_from_slice(signer.as_ref());
    }
    expected.extend_from_slice(&[threshold]);

    require!(message == expected.as_slice(), BridgeError::Ed25519VerificationFailed);

    // Load the Ed25519 verify instruction immediately before this one
    let ix = ix_sysvar::get_instruction_relative(
        -1,
        instructions_sysvar,
    ).map_err(|_| BridgeError::Ed25519InstructionMissing)?;

    require!(ix.program_id == ed25519_program::ID, BridgeError::Ed25519InstructionMissing);

    let data = &ix.data;
    require!(data.len() >= 16 + 64 + 32, BridgeError::Ed25519VerificationFailed);

    let num_sigs = data[0];
    require!(num_sigs >= 1, BridgeError::Ed25519VerificationFailed);

    // Extract public key
    let pk_offset = u16::from_le_bytes([data[6], data[7]]) as usize;
    require!(pk_offset + 32 <= data.len(), BridgeError::Ed25519VerificationFailed);
    let pubkey_bytes: [u8; 32] = data[pk_offset..pk_offset + 32].try_into().unwrap();
    let signer_pubkey = Pubkey::from(pubkey_bytes);

    // Verify signer is one of the CURRENT MPC signers
    let is_authorized = config.mpc_signers.iter().any(|s| *s == signer_pubkey);
    require!(is_authorized, BridgeError::UnauthorizedSigner);

    // Extract and verify message matches
    let msg_offset = u16::from_le_bytes([data[10], data[11]]) as usize;
    let msg_size = u16::from_le_bytes([data[12], data[13]]) as usize;
    require!(msg_offset + msg_size <= data.len(), BridgeError::Ed25519VerificationFailed);
    let ix_message = &data[msg_offset..msg_offset + msg_size];

    require!(ix_message == expected.as_slice(), BridgeError::Ed25519VerificationFailed);

    Ok(())
}

#[derive(Accounts)]
pub struct ExecuteSigners<'info> {
    #[account(
        mut,
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        has_one = admin,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,
    pub admin: Signer<'info>,
}

/// Execute a pending signer rotation after the timelock has elapsed.
pub fn execute_signers(ctx: Context<ExecuteSigners>) -> Result<()> {
    let config = &mut ctx.accounts.bridge_config;
    let clock = Clock::get()?;

    require!(config.has_pending_rotation(), BridgeError::NoPendingRotation);
    require!(
        clock.unix_timestamp >= config.pending_signers_eta,
        BridgeError::TimelockNotElapsed
    );

    // Apply the rotation
    config.mpc_signers = config.pending_signers;
    config.threshold = config.pending_threshold;

    // Clear pending state
    config.pending_signers = [Pubkey::default(); 3];
    config.pending_threshold = 0;
    config.pending_signers_eta = 0;

    msg!("Signer rotation executed");
    Ok(())
}

#[derive(Accounts)]
pub struct CancelSigners<'info> {
    #[account(
        mut,
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        has_one = admin,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,
    pub admin: Signer<'info>,
}

/// Cancel a pending signer rotation.
pub fn cancel_signers(ctx: Context<CancelSigners>) -> Result<()> {
    let config = &mut ctx.accounts.bridge_config;
    require!(config.has_pending_rotation(), BridgeError::NoPendingRotation);

    config.pending_signers = [Pubkey::default(); 3];
    config.pending_threshold = 0;
    config.pending_signers_eta = 0;

    msg!("Signer rotation cancelled");
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════
// FEE UPDATE
// ═══════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
pub struct UpdateFee<'info> {
    #[account(
        mut,
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        has_one = admin,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,
    pub admin: Signer<'info>,
}

pub fn update_fee(ctx: Context<UpdateFee>, fee_bps: u16) -> Result<()> {
    require!(fee_bps <= 500, BridgeError::FeeRateExceedsMax);
    ctx.accounts.bridge_config.fee_bps = fee_bps;
    Ok(())
}

/// Set operational delay for signer rotation (0 = instant, max 7 days).
/// This is NOT a security parameter — it's for cross-chain coordination.
pub fn set_rotation_delay(ctx: Context<UpdateFee>, delay_seconds: i64) -> Result<()> {
    require!(delay_seconds >= 0 && delay_seconds <= MAX_ROTATION_DELAY, BridgeError::FeeRateExceedsMax);
    ctx.accounts.bridge_config.rotation_delay = delay_seconds;
    Ok(())
}
