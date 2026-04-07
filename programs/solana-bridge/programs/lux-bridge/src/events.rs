use anchor_lang::prelude::*;

#[event]
pub struct LockEvent {
    pub source_chain: u64,
    pub dest_chain: u64,
    pub nonce: u64,
    pub token: Pubkey,
    pub sender: Pubkey,
    pub recipient: [u8; 32], // EVM address or other chain address (zero-padded)
    pub amount: u64,
    pub fee: u64,
    pub timestamp: i64,
}

#[event]
pub struct MintEvent {
    pub source_chain: u64,
    pub nonce: u64,
    pub token: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct BurnEvent {
    pub source_chain: u64,
    pub dest_chain: u64,
    pub nonce: u64,
    pub token: Pubkey,
    pub sender: Pubkey,
    pub recipient: [u8; 32],
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct ReleaseEvent {
    pub source_chain: u64,
    pub nonce: u64,
    pub token: Pubkey,
    pub recipient: Pubkey,
    pub amount: u64,
    pub timestamp: i64,
}
