use anchor_lang::prelude::*;
use crate::state::{BridgeConfig, SIGNER_TIMELOCK_SECONDS};
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
}

/// Queue new signers with a 7-day delay before they can take effect.
pub fn propose_signers(
    ctx: Context<ProposeSigners>,
    new_signers: [Pubkey; 3],
    threshold: u8,
) -> Result<()> {
    require!(threshold >= 1 && threshold <= 3, BridgeError::UnauthorizedSigner);

    let config = &mut ctx.accounts.bridge_config;
    let clock = Clock::get()?;

    config.pending_signers = new_signers;
    config.pending_threshold = threshold;
    config.pending_signers_eta = clock.unix_timestamp + SIGNER_TIMELOCK_SECONDS;

    msg!(
        "Signer rotation proposed. Executable after {}",
        config.pending_signers_eta
    );
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
