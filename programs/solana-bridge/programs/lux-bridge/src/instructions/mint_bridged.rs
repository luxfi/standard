use anchor_lang::prelude::*;
use anchor_lang::solana_program::sysvar::instructions as ix_sysvar;
use anchor_lang::solana_program::ed25519_program;
use anchor_spl::token::{self, MintTo, Token, Mint, TokenAccount};
use crate::state::{BridgeConfig, TokenConfig, NonceTracker};
use crate::errors::BridgeError;
use crate::events::MintEvent;

#[derive(Accounts)]
#[instruction(source_chain_id: u64, nonce: u64)]
pub struct MintBridged<'info> {
    #[account(
        seeds = [BridgeConfig::SEED],
        bump = bridge_config.bump,
        constraint = !bridge_config.paused @ BridgeError::Paused,
    )]
    pub bridge_config: Account<'info, BridgeConfig>,

    #[account(
        mut,
        seeds = [TokenConfig::SEED, token_config.mint.as_ref()],
        bump = token_config.bump,
        constraint = token_config.active @ BridgeError::TokenNotRegistered,
    )]
    pub token_config: Account<'info, TokenConfig>,

    #[account(
        mut,
        seeds = [NonceTracker::SEED, source_chain_id.to_le_bytes().as_ref()],
        bump = nonce_tracker.bump,
    )]
    pub nonce_tracker: Account<'info, NonceTracker>,

    /// Wrapped token mint — bridge has mint authority via PDA
    #[account(
        mut,
        constraint = wrapped_mint.key() == token_config.wrapped_mint,
    )]
    pub wrapped_mint: Account<'info, Mint>,

    /// Recipient's associated token account
    #[account(mut)]
    pub recipient_token: Account<'info, TokenAccount>,

    /// CHECK: PDA mint authority
    #[account(seeds = [b"mint_authority"], bump)]
    pub mint_authority: UncheckedAccount<'info>,

    /// CHECK: Solana instructions sysvar for Ed25519 verification
    #[account(address = ix_sysvar::ID)]
    pub instructions_sysvar: UncheckedAccount<'info>,

    /// Anyone can relay (typically MPC node or user)
    pub relayer: Signer<'info>,

    pub token_program: Program<'info, Token>,
}

pub fn handler(
    ctx: Context<MintBridged>,
    source_chain_id: u64,
    nonce: u64,
    recipient: Pubkey,
    amount: u64,
) -> Result<()> {
    // 1. Check nonce not already processed (replay prevention)
    let tracker = &mut ctx.accounts.nonce_tracker;
    require!(!tracker.is_processed(nonce), BridgeError::NonceAlreadyProcessed);

    // 2. Verify Ed25519 signature via instruction introspection
    // The transaction MUST include an Ed25519Program instruction before this one
    // that verifies: sign(SHA256("LUX_BRIDGE_MINT" || source_chain_id || nonce || recipient || mint || amount))
    verify_ed25519_signature(
        &ctx.accounts.instructions_sysvar,
        &ctx.accounts.bridge_config,
        source_chain_id,
        nonce,
        &recipient,
        &ctx.accounts.token_config.mint,
        amount,
    )?;

    // 3. Check daily mint limit
    let clock = Clock::get()?;
    ctx.accounts.token_config.check_daily_limit(amount, clock.unix_timestamp)?;

    // 4. Mint wrapped tokens to recipient
    let seeds = &[b"mint_authority".as_ref(), &[ctx.bumps.mint_authority]];
    let signer = &[&seeds[..]];

    let mint_ctx = CpiContext::new_with_signer(
        ctx.accounts.token_program.to_account_info(),
        MintTo {
            mint: ctx.accounts.wrapped_mint.to_account_info(),
            to: ctx.accounts.recipient_token.to_account_info(),
            authority: ctx.accounts.mint_authority.to_account_info(),
        },
        signer,
    );
    token::mint_to(mint_ctx, amount)?;

    // 5. Mark nonce as processed
    tracker.mark_processed(nonce)?;

    emit!(MintEvent {
        source_chain: source_chain_id,
        nonce,
        token: ctx.accounts.token_config.mint,
        recipient,
        amount,
        timestamp: clock.unix_timestamp,
    });

    Ok(())
}

/// Verify that an Ed25519 signature verification instruction exists in the same transaction.
/// The MPC signer produces an Ed25519 signature over the bridge message, and the relayer
/// includes an Ed25519Program.verify instruction before calling mint_bridged.
pub fn verify_ed25519_signature(
    instructions_sysvar: &AccountInfo,
    config: &BridgeConfig,
    source_chain_id: u64,
    nonce: u64,
    recipient: &Pubkey,
    mint: &Pubkey,
    amount: u64,
) -> Result<()> {
    // Reconstruct the expected message
    let mut message = Vec::with_capacity(128);
    message.extend_from_slice(b"LUX_BRIDGE_MINT");
    message.extend_from_slice(&source_chain_id.to_le_bytes());
    message.extend_from_slice(&nonce.to_le_bytes());
    message.extend_from_slice(recipient.as_ref());
    message.extend_from_slice(mint.as_ref());
    message.extend_from_slice(&amount.to_le_bytes());

    // Load previous instruction (must be Ed25519Program)
    let ix = ix_sysvar::load_instruction_at_checked(
        0, // Ed25519 verify instruction should be at index 0
        instructions_sysvar,
    ).map_err(|_| BridgeError::Ed25519InstructionMissing)?;

    require!(ix.program_id == ed25519_program::ID, BridgeError::Ed25519InstructionMissing);

    // The Ed25519 instruction data contains:
    // - num_signatures (1 byte) = 1
    // - padding (1 byte)
    // - signature_offset, signature_ix_index (2+2 bytes)
    // - public_key_offset, public_key_ix_index (2+2 bytes)
    // - message_offset, message_size, message_ix_index (2+2+2 bytes)
    // - signature (64 bytes)
    // - public_key (32 bytes)
    // - message (variable)
    //
    // We verify the public key matches one of our MPC signers
    // and the message matches our reconstructed message.

    let data = &ix.data;
    require!(data.len() >= 16 + 64 + 32, BridgeError::Ed25519VerificationFailed);

    let num_sigs = data[0];
    require!(num_sigs >= 1, BridgeError::Ed25519VerificationFailed);

    // Extract public key from instruction data
    let pk_offset = u16::from_le_bytes([data[6], data[7]]) as usize;
    require!(pk_offset + 32 <= data.len(), BridgeError::Ed25519VerificationFailed);
    let pubkey_bytes: [u8; 32] = data[pk_offset..pk_offset + 32].try_into().unwrap();
    let signer_pubkey = Pubkey::from(pubkey_bytes);

    // Verify signer is an authorized MPC signer
    let is_authorized = config.mpc_signers.iter().any(|s| *s == signer_pubkey);
    require!(is_authorized, BridgeError::UnauthorizedSigner);

    // Extract message from instruction data
    let msg_offset = u16::from_le_bytes([data[10], data[11]]) as usize;
    let msg_size = u16::from_le_bytes([data[12], data[13]]) as usize;
    require!(msg_offset + msg_size <= data.len(), BridgeError::Ed25519VerificationFailed);
    let ix_message = &data[msg_offset..msg_offset + msg_size];

    // Verify message matches
    require!(ix_message == message.as_slice(), BridgeError::Ed25519VerificationFailed);

    Ok(())
}
