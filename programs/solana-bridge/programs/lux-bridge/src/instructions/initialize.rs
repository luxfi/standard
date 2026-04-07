use anchor_lang::prelude::*;
use crate::state::BridgeConfig;
use crate::errors::BridgeError;

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = admin,
        space = BridgeConfig::LEN,
        seeds = [BridgeConfig::SEED],
        bump,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(mut)]
    pub admin: Signer<'info>,

    pub system_program: Program<'info, System>,
}

pub fn handler(
    ctx: Context<Initialize>,
    mpc_signers: [Pubkey; 3],
    threshold: u8,
    fee_bps: u16,
    chain_id: u64,
) -> Result<()> {
    require!(threshold >= 1 && threshold <= 3, BridgeError::UnauthorizedSigner);
    require!(fee_bps <= 500, BridgeError::FeeRateExceedsMax);

    let config = &mut ctx.accounts.bridge_config;
    config.admin = ctx.accounts.admin.key();
    config.mpc_signers = mpc_signers;
    config.threshold = threshold;
    config.fee_bps = fee_bps;
    config.fee_collector = ctx.accounts.admin.key();
    config.paused = false;
    config.outbound_nonce = 0;
    config.chain_id = chain_id;
    config.bump = ctx.bumps.bridge_config;

    Ok(())
}
