use anchor_lang::prelude::*;
use anchor_lang::solana_program::sysvar::instructions as ix_sysvar;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};
use crate::state::{BridgeConfig, TokenConfig, NonceTracker};
use crate::errors::BridgeError;
use crate::events::ReleaseEvent;
use crate::instructions::mint_bridged::verify_ed25519_signature;

/// Release locked native tokens after burn on source chain.
/// MPC signs the release; relayer submits with Ed25519 verify instruction.
#[derive(Accounts)]
#[instruction(source_chain_id: u64, nonce: u64)]
pub struct Release<'info> {
    #[account(
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        constraint = !bridge_config.paused @ BridgeError::Paused,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(
        seeds = [TokenConfig::SEED, token_config.mint.as_ref()],
        bump = token_config.bump,
        constraint = token_config.active @ BridgeError::TokenNotRegistered,
        constraint = token_config.is_native @ BridgeError::TokenNotRegistered,
    )]
    pub token_config: Account<'info, TokenConfig>,

    #[account(
        mut,
        seeds = [NonceTracker::SEED, source_chain_id.to_le_bytes().as_ref()],
        bump = nonce_tracker.bump,
    )]
    pub nonce_tracker: Account<'info, NonceTracker>,

    /// PDA vault holding locked native tokens
    #[account(
        mut,
        constraint = vault.key() == token_config.vault,
    )]
    pub vault: Account<'info, TokenAccount>,

    /// CHECK: PDA authority for the vault
    #[account(seeds = [b"vault_authority"], bump)]
    pub vault_authority: UncheckedAccount<'info>,

    /// Recipient's token account
    #[account(mut)]
    pub recipient_token: Account<'info, TokenAccount>,

    /// CHECK: Instructions sysvar for Ed25519 verification
    #[account(address = ix_sysvar::ID)]
    pub instructions_sysvar: UncheckedAccount<'info>,

    pub relayer: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

pub fn handler(
    ctx: Context<Release>,
    source_chain_id: u64,
    nonce: u64,
    recipient: Pubkey,
    amount: u64,
) -> Result<()> {
    // 1. Check nonce
    let tracker = &mut ctx.accounts.nonce_tracker;
    require!(!tracker.is_processed(nonce), BridgeError::NonceAlreadyProcessed);

    // 2. Verify MPC Ed25519 signature (same pattern as mint_bridged, different prefix)
    // Uses "LUX_BRIDGE_RELEASE" prefix to prevent cross-instruction replay
    verify_release_signature(
        &ctx.accounts.instructions_sysvar,
        &ctx.accounts.bridge_config,
        source_chain_id,
        nonce,
        &recipient,
        &ctx.accounts.token_config.mint,
        amount,
    )?;

    // 3. Transfer from vault to recipient
    let seeds = &[b"vault_authority".as_ref(), &[ctx.bumps.vault_authority]];
    let signer = &[&seeds[..]];

    let transfer_ctx = CpiContext::new_with_signer(
        ctx.accounts.token_program.to_account_info(),
        Transfer {
            from: ctx.accounts.vault.to_account_info(),
            to: ctx.accounts.recipient_token.to_account_info(),
            authority: ctx.accounts.vault_authority.to_account_info(),
        },
        signer,
    );
    token::transfer(transfer_ctx, amount)?;

    // 4. Mark nonce
    tracker.mark_processed(nonce)?;

    let clock = Clock::get()?;
    emit!(ReleaseEvent {
        source_chain: source_chain_id,
        nonce,
        token: ctx.accounts.token_config.mint,
        recipient,
        amount,
        timestamp: clock.unix_timestamp,
    });

    Ok(())
}

fn verify_release_signature(
    instructions_sysvar: &AccountInfo,
    config: &BridgeConfig,
    source_chain_id: u64,
    nonce: u64,
    recipient: &Pubkey,
    mint: &Pubkey,
    amount: u64,
) -> Result<()> {
    // Same as mint but with RELEASE prefix
    let mut message = Vec::with_capacity(128);
    message.extend_from_slice(b"LUX_BRIDGE_RELEASE");
    message.extend_from_slice(&source_chain_id.to_le_bytes());
    message.extend_from_slice(&nonce.to_le_bytes());
    message.extend_from_slice(recipient.as_ref());
    message.extend_from_slice(mint.as_ref());
    message.extend_from_slice(&amount.to_le_bytes());

    // Delegate to shared verification logic
    // (inline here for clarity, but could factor into a shared function)
    let ix = anchor_lang::solana_program::sysvar::instructions::load_instruction_at_checked(
        0,
        instructions_sysvar,
    ).map_err(|_| BridgeError::Ed25519InstructionMissing)?;

    require!(
        ix.program_id == anchor_lang::solana_program::ed25519_program::ID,
        BridgeError::Ed25519InstructionMissing
    );

    let data = &ix.data;
    require!(data.len() >= 16 + 64 + 32, BridgeError::Ed25519VerificationFailed);

    let pk_offset = u16::from_le_bytes([data[6], data[7]]) as usize;
    require!(pk_offset + 32 <= data.len(), BridgeError::Ed25519VerificationFailed);
    let pubkey_bytes: [u8; 32] = data[pk_offset..pk_offset + 32].try_into().unwrap();
    let signer_pubkey = Pubkey::from(pubkey_bytes);

    let is_authorized = config.mpc_signers.iter().any(|s| *s == signer_pubkey);
    require!(is_authorized, BridgeError::UnauthorizedSigner);

    let msg_offset = u16::from_le_bytes([data[10], data[11]]) as usize;
    let msg_size = u16::from_le_bytes([data[12], data[13]]) as usize;
    require!(msg_offset + msg_size <= data.len(), BridgeError::Ed25519VerificationFailed);
    let ix_message = &data[msg_offset..msg_offset + msg_size];

    require!(ix_message == message.as_slice(), BridgeError::Ed25519VerificationFailed);

    Ok(())
}
