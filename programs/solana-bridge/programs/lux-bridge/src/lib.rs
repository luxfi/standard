use anchor_lang::prelude::*;

pub mod errors;
pub mod events;
pub mod instructions;
pub mod state;

use instructions::*;

declare_id!("BRDGLux1111111111111111111111111111111111111");

#[program]
pub mod lux_bridge {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        mpc_signers: [Pubkey; 3],
        threshold: u8,
        fee_bps: u16,
        chain_id: u64,
    ) -> Result<()> {
        instructions::initialize::handler(ctx, mpc_signers, threshold, fee_bps, chain_id)
    }

    pub fn register_token(
        ctx: Context<RegisterToken>,
        is_native: bool,
        daily_mint_limit: u64,
    ) -> Result<()> {
        instructions::register_token::handler(ctx, is_native, daily_mint_limit)
    }

    pub fn lock_and_bridge(
        ctx: Context<LockAndBridge>,
        amount: u64,
        dest_chain_id: u64,
        recipient: [u8; 32],
    ) -> Result<()> {
        instructions::lock_and_bridge::handler(ctx, amount, dest_chain_id, recipient)
    }

    pub fn mint_bridged(
        ctx: Context<MintBridged>,
        source_chain_id: u64,
        nonce: u64,
        recipient: Pubkey,
        amount: u64,
    ) -> Result<()> {
        instructions::mint_bridged::handler(ctx, source_chain_id, nonce, recipient, amount)
    }

    pub fn burn_bridged(
        ctx: Context<BurnBridged>,
        amount: u64,
        dest_chain_id: u64,
        recipient: [u8; 32],
    ) -> Result<()> {
        instructions::burn_bridged::handler(ctx, amount, dest_chain_id, recipient)
    }

    pub fn release(
        ctx: Context<Release>,
        source_chain_id: u64,
        nonce: u64,
        recipient: Pubkey,
        amount: u64,
    ) -> Result<()> {
        instructions::release::handler(ctx, source_chain_id, nonce, recipient, amount)
    }

    pub fn pause(ctx: Context<Pause>) -> Result<()> {
        instructions::admin::pause(ctx)
    }

    pub fn unpause(ctx: Context<Pause>) -> Result<()> {
        instructions::admin::unpause(ctx)
    }

    /// Queue new MPC signers with 7-day timelock (H-06 fix)
    /// Requires admin key AND MPC Ed25519 signature (M-RED-04 fix)
    pub fn propose_signers(
        ctx: Context<ProposeSigners>,
        new_signers: [Pubkey; 3],
        threshold: u8,
        message: Vec<u8>,
    ) -> Result<()> {
        instructions::admin::propose_signers(ctx, new_signers, threshold, message)
    }

    /// Execute queued signer rotation after 7 days
    pub fn execute_signers(ctx: Context<ExecuteSigners>) -> Result<()> {
        instructions::admin::execute_signers(ctx)
    }

    /// Cancel pending signer rotation
    pub fn cancel_signers(ctx: Context<CancelSigners>) -> Result<()> {
        instructions::admin::cancel_signers(ctx)
    }

    pub fn update_fee(ctx: Context<UpdateFee>, fee_bps: u16) -> Result<()> {
        instructions::admin::update_fee(ctx, fee_bps)
    }

    /// Set operational delay for signer rotation (0 = instant, max 7 days)
    pub fn set_rotation_delay(ctx: Context<UpdateFee>, delay_seconds: i64) -> Result<()> {
        instructions::admin::set_rotation_delay(ctx, delay_seconds)
    }
}
