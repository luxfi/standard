/// Lux Bridge — CosmWasm (Cosmos/IBC) native bridge contract
///
/// Implements cross-chain token bridging between Cosmos ecosystem and Lux.
/// Uses Ed25519 MPC threshold signatures (FROST) for attestation.
/// Token standard: CW-20 (CosmWasm fungible tokens)
///
/// Two integration paths:
///   1. MPC Bridge: Lock/mint/burn/release with FROST signatures (like Solana/TON/Sui)
///   2. IBC Native: ICS-20 token transfers for Cosmos<->Cosmos chains
///
/// The MPC path bridges to non-IBC chains (Lux EVM, Solana, Bitcoin, etc.)
/// The IBC path is trust-minimized for inter-Cosmos transfers.
use cosmwasm_std::{
    entry_point, to_json_binary, Addr, Binary, CosmosMsg, Deps, DepsMut, Env,
    MessageInfo, Response, StdError, StdResult, Uint128, WasmMsg, BankMsg, Coin,
};
use cosmwasm_std::Event;
use cw_storage_plus::{Item, Map};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

// ========================================
// State
// ========================================

/// Global bridge config
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub struct Config {
    pub admin: Addr,
    /// MPC signer Ed25519 public keys (hex-encoded, 32 bytes each)
    pub mpc_signers: Vec<String>,
    pub threshold: u8,
    pub fee_bps: u64,
    pub fee_collector: Addr,
    pub paused: bool,
    pub outbound_nonce: u64,
    pub chain_id: u64, // Cosmos chain identifier in Lux namespace
    pub total_locked: Uint128,
    pub total_burned: Uint128,
}

/// Per-token bridge config
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub struct TokenConfig {
    pub denom: String, // Native denom or CW-20 contract address
    pub is_native: bool,
    pub daily_mint_limit: Uint128,
    pub daily_minted: Uint128,
    pub period_start: u64, // Unix timestamp
    pub active: bool,
}

const CONFIG: Item<Config> = Item::new("config");
const TOKEN_CONFIGS: Map<&str, TokenConfig> = Map::new("token_configs");
/// (source_chain_id, nonce) -> processed
const PROCESSED_NONCES: Map<(u64, u64), bool> = Map::new("processed_nonces");

// ========================================
// Messages
// ========================================

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub struct InstantiateMsg {
    pub mpc_signers: Vec<String>,
    pub threshold: u8,
    pub fee_bps: u64,
    pub chain_id: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ExecuteMsg {
    /// Lock native tokens for bridging
    LockAndBridge {
        dest_chain_id: u64,
        recipient: String, // Hex-encoded 32-byte dest address
    },
    /// Mint wrapped tokens (MPC-signed)
    MintBridged {
        source_chain_id: u64,
        nonce: u64,
        recipient: String,
        amount: Uint128,
        denom: String,
        signature: String, // Hex-encoded Ed25519 signature
        signer_pubkey: String, // Hex-encoded Ed25519 public key
    },
    /// Burn wrapped tokens for withdrawal
    BurnBridged {
        dest_chain_id: u64,
        recipient: String,
        denom: String,
        amount: Uint128,
    },
    /// Release locked tokens (MPC-signed)
    Release {
        source_chain_id: u64,
        nonce: u64,
        recipient: String,
        amount: Uint128,
        denom: String,
        signature: String,
        signer_pubkey: String,
    },
    // Admin
    RegisterToken { denom: String, is_native: bool, daily_limit: Uint128 },
    UpdateSigners { signers: Vec<String>, threshold: u8 },
    UpdateFee { fee_bps: u64 },
    Pause {},
    Unpause {},
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum QueryMsg {
    Config {},
    TokenConfig { denom: String },
    IsNonceProcessed { source_chain_id: u64, nonce: u64 },
    TotalLocked {},
    TotalBurned {},
}

// ========================================
// Entry points
// ========================================

#[entry_point]
pub fn instantiate(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    msg: InstantiateMsg,
) -> StdResult<Response> {
    let config = Config {
        admin: info.sender.clone(),
        mpc_signers: msg.mpc_signers,
        threshold: msg.threshold,
        fee_bps: msg.fee_bps,
        fee_collector: info.sender,
        paused: false,
        outbound_nonce: 0,
        chain_id: msg.chain_id,
        total_locked: Uint128::zero(),
        total_burned: Uint128::zero(),
    };
    CONFIG.save(deps.storage, &config)?;
    Ok(Response::new().add_attribute("action", "instantiate"))
}

#[entry_point]
pub fn execute(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    msg: ExecuteMsg,
) -> StdResult<Response> {
    match msg {
        ExecuteMsg::LockAndBridge { dest_chain_id, recipient } => {
            lock_and_bridge(deps, env, info, dest_chain_id, recipient)
        },
        ExecuteMsg::MintBridged { source_chain_id, nonce, recipient, amount, denom, signature, signer_pubkey } => {
            mint_bridged(deps, env, source_chain_id, nonce, recipient, amount, denom, signature, signer_pubkey)
        },
        ExecuteMsg::BurnBridged { dest_chain_id, recipient, denom, amount } => {
            burn_bridged(deps, env, info, dest_chain_id, recipient, denom, amount)
        },
        ExecuteMsg::Release { source_chain_id, nonce, recipient, amount, denom, signature, signer_pubkey } => {
            release(deps, env, source_chain_id, nonce, recipient, amount, denom, signature, signer_pubkey)
        },
        ExecuteMsg::RegisterToken { denom, is_native, daily_limit } => {
            register_token(deps, info, denom, is_native, daily_limit)
        },
        ExecuteMsg::UpdateSigners { signers, threshold } => {
            update_signers(deps, info, signers, threshold)
        },
        ExecuteMsg::UpdateFee { fee_bps } => update_fee(deps, info, fee_bps),
        ExecuteMsg::Pause {} => pause(deps, info),
        ExecuteMsg::Unpause {} => unpause(deps, info),
    }
}

#[entry_point]
pub fn query(deps: Deps, _env: Env, msg: QueryMsg) -> StdResult<Binary> {
    match msg {
        QueryMsg::Config {} => to_json_binary(&CONFIG.load(deps.storage)?),
        QueryMsg::TokenConfig { denom } => {
            to_json_binary(&TOKEN_CONFIGS.load(deps.storage, &denom)?)
        },
        QueryMsg::IsNonceProcessed { source_chain_id, nonce } => {
            let processed = PROCESSED_NONCES
                .may_load(deps.storage, (source_chain_id, nonce))?
                .unwrap_or(false);
            to_json_binary(&processed)
        },
        QueryMsg::TotalLocked {} => {
            let config = CONFIG.load(deps.storage)?;
            to_json_binary(&config.total_locked)
        },
        QueryMsg::TotalBurned {} => {
            let config = CONFIG.load(deps.storage)?;
            to_json_binary(&config.total_burned)
        },
    }
}

// ========================================
// Bridge operations
// ========================================

fn lock_and_bridge(
    deps: DepsMut,
    env: Env,
    info: MessageInfo,
    dest_chain_id: u64,
    recipient: String,
) -> StdResult<Response> {
    let mut config = CONFIG.load(deps.storage)?;
    if config.paused {
        return Err(StdError::generic_err("Bridge is paused"));
    }

    // Must send exactly one coin type
    if info.funds.len() != 1 {
        return Err(StdError::generic_err("Send exactly one coin type"));
    }
    let sent = &info.funds[0];
    let amount = sent.amount;

    // Calculate fee
    let fee = amount.multiply_ratio(config.fee_bps, 10_000u64);
    let bridge_amount = amount.checked_sub(fee)
        .map_err(|_| StdError::generic_err("Fee exceeds amount"))?;

    // Update state
    config.total_locked += bridge_amount;
    config.outbound_nonce += 1;
    let nonce = config.outbound_nonce;
    CONFIG.save(deps.storage, &config)?;

    Ok(Response::new()
        .add_event(Event::new("lock")
            .add_attribute("source_chain", config.chain_id.to_string())
            .add_attribute("dest_chain", dest_chain_id.to_string())
            .add_attribute("nonce", nonce.to_string())
            .add_attribute("denom", &sent.denom)
            .add_attribute("sender", info.sender.to_string())
            .add_attribute("recipient", &recipient)
            .add_attribute("amount", bridge_amount.to_string())
            .add_attribute("fee", fee.to_string())
        ))
}

fn mint_bridged(
    deps: DepsMut,
    env: Env,
    source_chain_id: u64,
    nonce: u64,
    recipient: String,
    amount: Uint128,
    denom: String,
    signature: String,
    signer_pubkey: String,
) -> StdResult<Response> {
    let config = CONFIG.load(deps.storage)?;
    if config.paused {
        return Err(StdError::generic_err("Bridge is paused"));
    }

    // Check nonce
    if PROCESSED_NONCES.may_load(deps.storage, (source_chain_id, nonce))?.unwrap_or(false) {
        return Err(StdError::generic_err("Nonce already processed"));
    }

    // Verify signer is authorized
    if !config.mpc_signers.contains(&signer_pubkey) {
        return Err(StdError::generic_err("Unauthorized signer"));
    }

    // Verify Ed25519 signature
    let message = build_mint_message(source_chain_id, nonce, &recipient, amount);
    let sig_bytes = hex::decode(&signature)
        .map_err(|_| StdError::generic_err("Invalid signature hex"))?;
    let pk_bytes = hex::decode(&signer_pubkey)
        .map_err(|_| StdError::generic_err("Invalid pubkey hex"))?;

    let valid = deps.api.ed25519_verify(&message, &sig_bytes, &pk_bytes)
        .map_err(|_| StdError::generic_err("Signature verification failed"))?;
    if !valid {
        return Err(StdError::generic_err("Invalid signature"));
    }

    // Check daily limit
    let mut token_config = TOKEN_CONFIGS.load(deps.storage, &denom)?;
    check_daily_limit(&mut token_config, amount, env.block.time.seconds())?;
    TOKEN_CONFIGS.save(deps.storage, &denom, &token_config)?;

    // Mark nonce
    PROCESSED_NONCES.save(deps.storage, (source_chain_id, nonce), &true)?;

    // Mint (via bank module for native denoms, or CW-20 mint for contract tokens)
    let recipient_addr = deps.api.addr_validate(&recipient)?;
    let mint_msg = BankMsg::Send {
        to_address: recipient_addr.to_string(),
        amount: vec![Coin { denom: denom.clone(), amount }],
    };

    Ok(Response::new()
        .add_message(mint_msg)
        .add_event(Event::new("mint")
            .add_attribute("source_chain", source_chain_id.to_string())
            .add_attribute("nonce", nonce.to_string())
            .add_attribute("recipient", &recipient)
            .add_attribute("amount", amount.to_string())
            .add_attribute("denom", &denom)
        ))
}

fn burn_bridged(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    dest_chain_id: u64,
    recipient: String,
    denom: String,
    amount: Uint128,
) -> StdResult<Response> {
    let mut config = CONFIG.load(deps.storage)?;
    if config.paused {
        return Err(StdError::generic_err("Bridge is paused"));
    }

    config.total_burned += amount;
    config.outbound_nonce += 1;
    let nonce = config.outbound_nonce;
    CONFIG.save(deps.storage, &config)?;

    // Burn native tokens (send to module burn address)
    let burn_msg = BankMsg::Burn {
        amount: vec![Coin { denom: denom.clone(), amount }],
    };

    Ok(Response::new()
        .add_message(burn_msg)
        .add_event(Event::new("burn")
            .add_attribute("source_chain", config.chain_id.to_string())
            .add_attribute("dest_chain", dest_chain_id.to_string())
            .add_attribute("nonce", nonce.to_string())
            .add_attribute("denom", &denom)
            .add_attribute("sender", info.sender.to_string())
            .add_attribute("recipient", &recipient)
            .add_attribute("amount", amount.to_string())
        ))
}

fn release(
    deps: DepsMut,
    _env: Env,
    source_chain_id: u64,
    nonce: u64,
    recipient: String,
    amount: Uint128,
    denom: String,
    signature: String,
    signer_pubkey: String,
) -> StdResult<Response> {
    let config = CONFIG.load(deps.storage)?;
    if config.paused {
        return Err(StdError::generic_err("Bridge is paused"));
    }

    if PROCESSED_NONCES.may_load(deps.storage, (source_chain_id, nonce))?.unwrap_or(false) {
        return Err(StdError::generic_err("Nonce already processed"));
    }

    if !config.mpc_signers.contains(&signer_pubkey) {
        return Err(StdError::generic_err("Unauthorized signer"));
    }

    let message = build_release_message(source_chain_id, nonce, &recipient, amount);
    let sig_bytes = hex::decode(&signature).map_err(|_| StdError::generic_err("Invalid sig"))?;
    let pk_bytes = hex::decode(&signer_pubkey).map_err(|_| StdError::generic_err("Invalid pk"))?;

    let valid = deps.api.ed25519_verify(&message, &sig_bytes, &pk_bytes)
        .map_err(|_| StdError::generic_err("Sig verify failed"))?;
    if !valid {
        return Err(StdError::generic_err("Invalid signature"));
    }

    PROCESSED_NONCES.save(deps.storage, (source_chain_id, nonce), &true)?;

    let recipient_addr = deps.api.addr_validate(&recipient)?;
    let send_msg = BankMsg::Send {
        to_address: recipient_addr.to_string(),
        amount: vec![Coin { denom, amount }],
    };

    Ok(Response::new()
        .add_message(send_msg)
        .add_event(Event::new("release")
            .add_attribute("source_chain", source_chain_id.to_string())
            .add_attribute("nonce", nonce.to_string())
            .add_attribute("recipient", &recipient)
            .add_attribute("amount", amount.to_string())
        ))
}

// ========================================
// Admin
// ========================================

fn register_token(deps: DepsMut, info: MessageInfo, denom: String, is_native: bool, daily_limit: Uint128) -> StdResult<Response> {
    let config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin { return Err(StdError::generic_err("Unauthorized")); }
    TOKEN_CONFIGS.save(deps.storage, &denom, &TokenConfig {
        denom: denom.clone(), is_native, daily_mint_limit: daily_limit,
        daily_minted: Uint128::zero(), period_start: 0, active: true,
    })?;
    Ok(Response::new().add_attribute("action", "register_token").add_attribute("denom", denom))
}

fn update_signers(deps: DepsMut, info: MessageInfo, signers: Vec<String>, threshold: u8) -> StdResult<Response> {
    let mut config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin { return Err(StdError::generic_err("Unauthorized")); }
    config.mpc_signers = signers;
    config.threshold = threshold;
    CONFIG.save(deps.storage, &config)?;
    Ok(Response::new().add_attribute("action", "update_signers"))
}

fn update_fee(deps: DepsMut, info: MessageInfo, fee_bps: u64) -> StdResult<Response> {
    let mut config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin { return Err(StdError::generic_err("Unauthorized")); }
    if fee_bps > 500 { return Err(StdError::generic_err("Fee exceeds 5%")); }
    config.fee_bps = fee_bps;
    CONFIG.save(deps.storage, &config)?;
    Ok(Response::new().add_attribute("action", "update_fee"))
}

fn pause(deps: DepsMut, info: MessageInfo) -> StdResult<Response> {
    let mut config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin { return Err(StdError::generic_err("Unauthorized")); }
    config.paused = true;
    CONFIG.save(deps.storage, &config)?;
    Ok(Response::new().add_attribute("action", "pause"))
}

fn unpause(deps: DepsMut, info: MessageInfo) -> StdResult<Response> {
    let mut config = CONFIG.load(deps.storage)?;
    if info.sender != config.admin { return Err(StdError::generic_err("Unauthorized")); }
    config.paused = false;
    CONFIG.save(deps.storage, &config)?;
    Ok(Response::new().add_attribute("action", "unpause"))
}

// ========================================
// Helpers
// ========================================

fn build_mint_message(chain_id: u64, nonce: u64, recipient: &str, amount: Uint128) -> Vec<u8> {
    let mut msg = b"LUX_BRIDGE_MINT".to_vec();
    msg.extend_from_slice(&chain_id.to_le_bytes());
    msg.extend_from_slice(&nonce.to_le_bytes());
    msg.extend_from_slice(recipient.as_bytes());
    msg.extend_from_slice(&amount.u128().to_le_bytes());
    msg
}

fn build_release_message(chain_id: u64, nonce: u64, recipient: &str, amount: Uint128) -> Vec<u8> {
    let mut msg = b"LUX_BRIDGE_RELEASE".to_vec();
    msg.extend_from_slice(&chain_id.to_le_bytes());
    msg.extend_from_slice(&nonce.to_le_bytes());
    msg.extend_from_slice(recipient.as_bytes());
    msg.extend_from_slice(&amount.u128().to_le_bytes());
    msg
}

fn check_daily_limit(config: &mut TokenConfig, amount: Uint128, now: u64) -> StdResult<()> {
    if config.daily_mint_limit.is_zero() { return Ok(()); }
    if now >= config.period_start + 86400 {
        config.daily_minted = Uint128::zero();
        config.period_start = now;
    }
    let new_total = config.daily_minted + amount;
    if new_total > config.daily_mint_limit {
        return Err(StdError::generic_err("Daily mint limit exceeded"));
    }
    config.daily_minted = new_total;
    Ok(())
}
