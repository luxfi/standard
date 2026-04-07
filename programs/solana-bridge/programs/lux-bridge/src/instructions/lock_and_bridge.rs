use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};
use crate::state::{BridgeConfig, TokenConfig};
use crate::errors::BridgeError;
use crate::events::LockEvent;

#[derive(Accounts)]
pub struct LockAndBridge<'info> {
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

    /// User's token account (source of funds)
    #[account(
        mut,
        constraint = user_token.mint == token_config.mint,
    )]
    pub user_token: Account<'info, TokenAccount>,

    /// PDA vault to receive locked tokens
    #[account(
        mut,
        constraint = vault.key() == token_config.vault,
    )]
    pub vault: Account<'info, TokenAccount>,

    /// Optional: fee collector token account
    #[account(mut)]
    pub fee_account: Option<Account<'info, TokenAccount>>,

    #[account(mut)]
    pub sender: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

pub fn handler(
    ctx: Context<LockAndBridge>,
    amount: u64,
    dest_chain_id: u64,
    recipient: [u8; 32],
) -> Result<()> {
    require!(amount > 0, BridgeError::AmountTooSmall);

    let config = &mut ctx.accounts.bridge_config;
    let fee_bps = config.fee_bps as u64;

    // Calculate fee
    let fee = amount.checked_mul(fee_bps).unwrap() / 10_000;
    let bridge_amount = amount.checked_sub(fee).unwrap();

    // Transfer tokens to vault
    let transfer_ctx = CpiContext::new(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.user_token.to_account_info(),
            to: ctx.accounts.vault.to_account_info(),
            authority: ctx.accounts.sender.to_account_info(),
        },
    );
    token::transfer(transfer_ctx, bridge_amount)?;

    // Transfer fee if applicable
    if fee > 0 {
        if let Some(fee_account) = &ctx.accounts.fee_account {
            let fee_ctx = CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.user_token.to_account_info(),
                    to: fee_account.to_account_info(),
                    authority: ctx.accounts.sender.to_account_info(),
                },
            );
            token::transfer(fee_ctx, fee)?;
        }
    }

    let nonce = config.next_nonce();
    let clock = Clock::get()?;

    emit!(LockEvent {
        source_chain: config.chain_id,
        dest_chain: dest_chain_id,
        nonce,
        token: ctx.accounts.token_config.mint,
        sender: ctx.accounts.sender.key(),
        recipient,
        amount: bridge_amount,
        fee,
        timestamp: clock.unix_timestamp,
    });

    Ok(())
}
