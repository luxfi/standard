use anchor_lang::prelude::*;
use anchor_spl::token::{Mint, Token, TokenAccount};
use crate::state::{BridgeConfig, TokenConfig};

#[derive(Accounts)]
pub struct RegisterToken<'info> {
    #[account(
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        has_one = admin,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(
        init,
        payer = admin,
        space = TokenConfig::LEN,
        seeds = [TokenConfig::SEED, mint.key().as_ref()],
        bump,
    )]
    pub token_config: Account<'info, TokenConfig>,

    /// The SPL token mint being registered
    pub mint: Account<'info, Mint>,

    /// PDA-controlled vault for locking native tokens
    #[account(
        init,
        payer = admin,
        token::mint = mint,
        token::authority = vault_authority,
        seeds = [b"vault", mint.key().as_ref()],
        bump,
    )]
    pub vault: Account<'info, TokenAccount>,

    /// CHECK: PDA authority for the vault
    #[account(seeds = [b"vault_authority"], bump)]
    pub vault_authority: UncheckedAccount<'info>,

    /// Optional: wrapped token mint (if this is a native token being bridged OUT)
    /// For tokens being bridged IN, this is the mint the bridge controls
    pub wrapped_mint: Option<Account<'info, Mint>>,

    #[account(mut)]
    pub admin: Signer<'info>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

pub fn handler(
    ctx: Context<RegisterToken>,
    is_native: bool,
    daily_mint_limit: u64,
) -> Result<()> {
    let config = &mut ctx.accounts.token_config;
    config.mint = ctx.accounts.mint.key();
    config.vault = ctx.accounts.vault.key();
    config.wrapped_mint = ctx.accounts.wrapped_mint
        .as_ref()
        .map(|m| m.key())
        .unwrap_or(ctx.accounts.mint.key());
    config.is_native = is_native;
    config.daily_mint_limit = daily_mint_limit;
    config.daily_minted = 0;
    config.period_start = Clock::get()?.unix_timestamp;
    config.active = true;
    config.bump = ctx.bumps.token_config;

    Ok(())
}
