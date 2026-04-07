use anchor_lang::prelude::*;
use anchor_spl::token::{self, Burn, Token, Mint, TokenAccount};
use crate::state::{BridgeConfig, TokenConfig};
use crate::errors::BridgeError;
use crate::events::BurnEvent;

#[derive(Accounts)]
pub struct BurnBridged<'info> {
    #[account(
        mut,
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        constraint = !bridge_config.paused @ BridgeError::Paused,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(
        seeds = [TokenConfig::SEED, token_config.mint.as_ref()],
        bump = token_config.bump,
        constraint = token_config.active @ BridgeError::TokenNotRegistered,
    )]
    pub token_config: Account<'info, TokenConfig>,

    /// Wrapped token mint to burn from
    #[account(
        mut,
        constraint = wrapped_mint.key() == token_config.wrapped_mint,
    )]
    pub wrapped_mint: Account<'info, Mint>,

    /// User's wrapped token account
    #[account(
        mut,
        constraint = user_token.mint == wrapped_mint.key(),
    )]
    pub user_token: Account<'info, TokenAccount>,

    #[account(mut)]
    pub sender: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

pub fn handler(
    ctx: Context<BurnBridged>,
    amount: u64,
    dest_chain_id: u64,
    recipient: [u8; 32],
) -> Result<()> {
    require!(amount > 0, BridgeError::AmountTooSmall);

    // Burn wrapped tokens
    let burn_ctx = CpiContext::new(
        ctx.accounts.token_program.to_account_info(),
        Burn {
            mint: ctx.accounts.wrapped_mint.to_account_info(),
            from: ctx.accounts.user_token.to_account_info(),
            authority: ctx.accounts.sender.to_account_info(),
        },
    );
    token::burn(burn_ctx, amount)?;

    let config = &mut ctx.accounts.bridge_config;
    let nonce = config.next_nonce();
    let clock = Clock::get()?;

    emit!(BurnEvent {
        source_chain: config.chain_id,
        dest_chain: dest_chain_id,
        nonce,
        token: ctx.accounts.token_config.mint,
        sender: ctx.accounts.sender.key(),
        recipient,
        amount,
        timestamp: clock.unix_timestamp,
    });

    Ok(())
}
