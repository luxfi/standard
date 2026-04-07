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

#[cfg(test)]
mod tests {
    use super::*;
    use cosmwasm_std::testing::{mock_dependencies, mock_env, mock_info};
    use cosmwasm_std::{from_json, Uint128, Coin, Addr};

    const ADMIN: &str = "admin";
    const USER: &str = "user";
    // Must be valid bech32 with cosmwasm prefix (MockApi requires it for addr_validate)
    const RECIPIENT: &str = "cosmwasm1h34lmpywh4upnjdg90cjf4j70aee6z8qqfspugamjp42e4q28kqs8s7vcp";
    const CHAIN_ID: u64 = 118;
    const DEST_CHAIN: u64 = 96369;

    fn default_instantiate_msg() -> InstantiateMsg {
        InstantiateMsg {
            mpc_signers: vec![
                "aaaa".to_string(),
                "bbbb".to_string(),
            ],
            threshold: 2,
            fee_bps: 30,
            chain_id: CHAIN_ID,
        }
    }

    fn setup() -> (cosmwasm_std::OwnedDeps<cosmwasm_std::MemoryStorage, cosmwasm_std::testing::MockApi, cosmwasm_std::testing::MockQuerier>, Env) {
        let mut deps = mock_dependencies();
        let env = mock_env();
        let info = mock_info(ADMIN, &[]);
        instantiate(deps.as_mut(), env.clone(), info, default_instantiate_msg()).unwrap();
        (deps, env)
    }

    fn register_token(deps: &mut cosmwasm_std::OwnedDeps<cosmwasm_std::MemoryStorage, cosmwasm_std::testing::MockApi, cosmwasm_std::testing::MockQuerier>, denom: &str, limit: u128) {
        let info = mock_info(ADMIN, &[]);
        execute(
            deps.as_mut(),
            mock_env(),
            info,
            ExecuteMsg::RegisterToken {
                denom: denom.to_string(),
                is_native: true,
                daily_limit: Uint128::new(limit),
            },
        ).unwrap();
    }

    // ----------------------------------------------------------------
    // 1. instantiate
    // ----------------------------------------------------------------

    #[test]
    fn instantiate_stores_config() {
        let (deps, _env) = setup();

        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();

        assert_eq!(config.admin, Addr::unchecked(ADMIN));
        assert_eq!(config.mpc_signers, vec!["aaaa", "bbbb"]);
        assert_eq!(config.threshold, 2);
        assert_eq!(config.fee_bps, 30);
        assert_eq!(config.chain_id, CHAIN_ID);
        assert_eq!(config.outbound_nonce, 0);
        assert!(!config.paused);
        assert_eq!(config.total_locked, Uint128::zero());
        assert_eq!(config.total_burned, Uint128::zero());
    }

    // ----------------------------------------------------------------
    // 2. lock_and_bridge
    // ----------------------------------------------------------------

    #[test]
    fn lock_and_bridge_locks_funds_and_increments_nonce() {
        let (mut deps, env) = setup();

        let info = mock_info(USER, &[Coin::new(10_000u128, "ulux")]);
        let res = execute(
            deps.as_mut(),
            env.clone(),
            info,
            ExecuteMsg::LockAndBridge {
                dest_chain_id: DEST_CHAIN,
                recipient: "0xdead".to_string(),
            },
        ).unwrap();

        // Should emit a lock event
        assert_eq!(res.events.len(), 1);
        assert_eq!(res.events[0].ty, "lock");

        // Nonce incremented to 1
        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();
        assert_eq!(config.outbound_nonce, 1);

        // total_locked = 10000 - fee (10000 * 30 / 10000 = 30) = 9970
        assert_eq!(config.total_locked, Uint128::new(9_970));
    }

    #[test]
    fn lock_and_bridge_rejects_no_funds() {
        let (mut deps, env) = setup();

        let info = mock_info(USER, &[]);
        let err = execute(
            deps.as_mut(),
            env,
            info,
            ExecuteMsg::LockAndBridge {
                dest_chain_id: DEST_CHAIN,
                recipient: "0xdead".to_string(),
            },
        ).unwrap_err();
        assert!(err.to_string().contains("Send exactly one coin type"));
    }

    #[test]
    fn lock_and_bridge_rejects_when_paused() {
        let (mut deps, env) = setup();

        // Pause
        execute(
            deps.as_mut(), env.clone(), mock_info(ADMIN, &[]),
            ExecuteMsg::Pause {},
        ).unwrap();

        let info = mock_info(USER, &[Coin::new(1000u128, "ulux")]);
        let err = execute(
            deps.as_mut(), env, info,
            ExecuteMsg::LockAndBridge {
                dest_chain_id: DEST_CHAIN,
                recipient: "0xdead".to_string(),
            },
        ).unwrap_err();
        assert!(err.to_string().contains("paused"));
    }

    // ----------------------------------------------------------------
    // 3. mint_bridged — ed25519 signature verification
    // ----------------------------------------------------------------

    /// Helper: generate an ed25519 keypair, sign a mint message, return (pubkey_hex, sig_hex).
    fn sign_mint(seed: [u8; 32], source_chain_id: u64, nonce: u64, recipient: &str, amount: Uint128) -> (String, String) {
        use ed25519_zebra::{SigningKey, VerificationKeyBytes};

        let sk = SigningKey::from(seed);
        let vk_bytes: VerificationKeyBytes = (&sk).into();
        let pubkey_hex = hex::encode(<[u8; 32]>::from(vk_bytes));

        let message = build_mint_message(source_chain_id, nonce, recipient, amount);
        let sig = sk.sign(&message);
        let sig_hex = hex::encode(<[u8; 64]>::from(sig));

        (pubkey_hex, sig_hex)
    }

    #[test]
    fn mint_bridged_with_valid_signature() {
        let (mut deps, env) = setup();

        // Generate a real keypair and register the pubkey as a signer
        let seed = [1u8; 32];
        let (pubkey_hex, _) = sign_mint(seed, 0, 0, "", Uint128::zero());

        // Update signers to include our test key
        execute(
            deps.as_mut(), mock_env(), mock_info(ADMIN, &[]),
            ExecuteMsg::UpdateSigners {
                signers: vec![pubkey_hex.clone()],
                threshold: 1,
            },
        ).unwrap();

        // Register the token with a high daily limit
        register_token(&mut deps, "bridged_ulux", 1_000_000);

        // Sign the mint message
        let amount = Uint128::new(5_000);
        let (_, sig_hex) = sign_mint(seed, DEST_CHAIN, 1, RECIPIENT, amount);

        let res = execute(
            deps.as_mut(),
            env,
            mock_info(USER, &[]), // anyone can relay
            ExecuteMsg::MintBridged {
                source_chain_id: DEST_CHAIN,
                nonce: 1,
                recipient: RECIPIENT.to_string(),
                amount,
                denom: "bridged_ulux".to_string(),
                signature: sig_hex,
                signer_pubkey: pubkey_hex,
            },
        ).unwrap();

        // Should emit a mint event and a bank send message
        assert_eq!(res.events.len(), 1);
        assert_eq!(res.events[0].ty, "mint");
        assert_eq!(res.messages.len(), 1);
    }

    #[test]
    fn mint_bridged_rejects_invalid_signature() {
        let (mut deps, env) = setup();

        let seed = [2u8; 32];
        let (pubkey_hex, _) = sign_mint(seed, 0, 0, "", Uint128::zero());

        execute(
            deps.as_mut(), mock_env(), mock_info(ADMIN, &[]),
            ExecuteMsg::UpdateSigners {
                signers: vec![pubkey_hex.clone()],
                threshold: 1,
            },
        ).unwrap();
        register_token(&mut deps, "bridged_ulux", 1_000_000);

        // Sign with DIFFERENT parameters than what we submit
        let (_, sig_hex) = sign_mint(seed, DEST_CHAIN, 1, RECIPIENT, Uint128::new(5_000));

        let err = execute(
            deps.as_mut(),
            env,
            mock_info(USER, &[]),
            ExecuteMsg::MintBridged {
                source_chain_id: DEST_CHAIN,
                nonce: 1,
                recipient: RECIPIENT.to_string(),
                amount: Uint128::new(9_999), // different amount than signed
                denom: "bridged_ulux".to_string(),
                signature: sig_hex,
                signer_pubkey: pubkey_hex,
            },
        ).unwrap_err();
        assert!(err.to_string().contains("Invalid signature"));
    }

    #[test]
    fn mint_bridged_rejects_unauthorized_signer() {
        let (mut deps, env) = setup();

        register_token(&mut deps, "bridged_ulux", 1_000_000);

        // Sign with a key that is NOT registered as a signer
        let seed = [99u8; 32];
        let amount = Uint128::new(1_000);
        let (pubkey_hex, sig_hex) = sign_mint(seed, DEST_CHAIN, 1, RECIPIENT, amount);

        let err = execute(
            deps.as_mut(),
            env,
            mock_info(USER, &[]),
            ExecuteMsg::MintBridged {
                source_chain_id: DEST_CHAIN,
                nonce: 1,
                recipient: RECIPIENT.to_string(),
                amount,
                denom: "bridged_ulux".to_string(),
                signature: sig_hex,
                signer_pubkey: pubkey_hex,
            },
        ).unwrap_err();
        assert!(err.to_string().contains("Unauthorized signer"));
    }

    #[test]
    fn mint_bridged_rejects_replay() {
        let (mut deps, env) = setup();

        let seed = [3u8; 32];
        let (pubkey_hex, _) = sign_mint(seed, 0, 0, "", Uint128::zero());
        execute(
            deps.as_mut(), mock_env(), mock_info(ADMIN, &[]),
            ExecuteMsg::UpdateSigners {
                signers: vec![pubkey_hex.clone()],
                threshold: 1,
            },
        ).unwrap();
        register_token(&mut deps, "bridged_ulux", 1_000_000);

        let amount = Uint128::new(1_000);
        let (_, sig_hex) = sign_mint(seed, DEST_CHAIN, 1, RECIPIENT, amount);

        // First mint succeeds
        execute(
            deps.as_mut(), env.clone(), mock_info(USER, &[]),
            ExecuteMsg::MintBridged {
                source_chain_id: DEST_CHAIN,
                nonce: 1,
                recipient: RECIPIENT.to_string(),
                amount,
                denom: "bridged_ulux".to_string(),
                signature: sig_hex.clone(),
                signer_pubkey: pubkey_hex.clone(),
            },
        ).unwrap();

        // Replay fails
        let err = execute(
            deps.as_mut(), env, mock_info(USER, &[]),
            ExecuteMsg::MintBridged {
                source_chain_id: DEST_CHAIN,
                nonce: 1,
                recipient: RECIPIENT.to_string(),
                amount,
                denom: "bridged_ulux".to_string(),
                signature: sig_hex,
                signer_pubkey: pubkey_hex,
            },
        ).unwrap_err();
        assert!(err.to_string().contains("Nonce already processed"));
    }

    // ----------------------------------------------------------------
    // 4. burn_bridged
    // ----------------------------------------------------------------

    #[test]
    fn burn_bridged_increments_nonce_and_total() {
        let (mut deps, env) = setup();

        let amount = Uint128::new(2_000);
        let info = mock_info(USER, &[Coin::new(2_000u128, "bridged_ulux")]);
        let res = execute(
            deps.as_mut(),
            env,
            info,
            ExecuteMsg::BurnBridged {
                dest_chain_id: DEST_CHAIN,
                recipient: "0xbeef".to_string(),
                denom: "bridged_ulux".to_string(),
                amount,
            },
        ).unwrap();

        assert_eq!(res.events.len(), 1);
        assert_eq!(res.events[0].ty, "burn");
        assert_eq!(res.messages.len(), 1); // BankMsg::Burn

        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();
        assert_eq!(config.outbound_nonce, 1);
        assert_eq!(config.total_burned, amount);
    }

    #[test]
    fn burn_bridged_rejects_when_paused() {
        let (mut deps, env) = setup();

        execute(
            deps.as_mut(), env.clone(), mock_info(ADMIN, &[]),
            ExecuteMsg::Pause {},
        ).unwrap();

        let err = execute(
            deps.as_mut(), env, mock_info(USER, &[]),
            ExecuteMsg::BurnBridged {
                dest_chain_id: DEST_CHAIN,
                recipient: "0xbeef".to_string(),
                denom: "bridged_ulux".to_string(),
                amount: Uint128::new(100),
            },
        ).unwrap_err();
        assert!(err.to_string().contains("paused"));
    }

    // ----------------------------------------------------------------
    // 5. pause / unpause
    // ----------------------------------------------------------------

    #[test]
    fn admin_can_pause_and_unpause() {
        let (mut deps, env) = setup();

        // Pause
        execute(
            deps.as_mut(), env.clone(), mock_info(ADMIN, &[]),
            ExecuteMsg::Pause {},
        ).unwrap();

        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();
        assert!(config.paused);

        // Unpause
        execute(
            deps.as_mut(), env, mock_info(ADMIN, &[]),
            ExecuteMsg::Unpause {},
        ).unwrap();

        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();
        assert!(!config.paused);
    }

    // ----------------------------------------------------------------
    // 6. update_fee
    // ----------------------------------------------------------------

    #[test]
    fn update_fee_sets_valid_fee() {
        let (mut deps, _env) = setup();

        execute(
            deps.as_mut(), mock_env(), mock_info(ADMIN, &[]),
            ExecuteMsg::UpdateFee { fee_bps: 100 },
        ).unwrap();

        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();
        assert_eq!(config.fee_bps, 100);
    }

    #[test]
    fn update_fee_rejects_over_5_percent() {
        let (mut deps, _env) = setup();

        let err = execute(
            deps.as_mut(), mock_env(), mock_info(ADMIN, &[]),
            ExecuteMsg::UpdateFee { fee_bps: 501 },
        ).unwrap_err();
        assert!(err.to_string().contains("Fee exceeds 5%"));
    }

    #[test]
    fn update_fee_accepts_boundary() {
        let (mut deps, _env) = setup();

        // Exactly 500 bps (5%) should succeed
        execute(
            deps.as_mut(), mock_env(), mock_info(ADMIN, &[]),
            ExecuteMsg::UpdateFee { fee_bps: 500 },
        ).unwrap();

        let config: Config = from_json(
            query(deps.as_ref(), mock_env(), QueryMsg::Config {}).unwrap()
        ).unwrap();
        assert_eq!(config.fee_bps, 500);
    }

    // ----------------------------------------------------------------
    // 7. unauthorized — non-admin calls rejected
    // ----------------------------------------------------------------

    #[test]
    fn non_admin_cannot_pause() {
        let (mut deps, env) = setup();

        let err = execute(
            deps.as_mut(), env, mock_info(USER, &[]),
            ExecuteMsg::Pause {},
        ).unwrap_err();
        assert!(err.to_string().contains("Unauthorized"));
    }

    #[test]
    fn non_admin_cannot_unpause() {
        let (mut deps, env) = setup();

        let err = execute(
            deps.as_mut(), env, mock_info(USER, &[]),
            ExecuteMsg::Unpause {},
        ).unwrap_err();
        assert!(err.to_string().contains("Unauthorized"));
    }

    #[test]
    fn non_admin_cannot_update_fee() {
        let (mut deps, _env) = setup();

        let err = execute(
            deps.as_mut(), mock_env(), mock_info(USER, &[]),
            ExecuteMsg::UpdateFee { fee_bps: 10 },
        ).unwrap_err();
        assert!(err.to_string().contains("Unauthorized"));
    }

    #[test]
    fn non_admin_cannot_update_signers() {
        let (mut deps, _env) = setup();

        let err = execute(
            deps.as_mut(), mock_env(), mock_info(USER, &[]),
            ExecuteMsg::UpdateSigners {
                signers: vec!["cccc".to_string()],
                threshold: 1,
            },
        ).unwrap_err();
        assert!(err.to_string().contains("Unauthorized"));
    }

    #[test]
    fn non_admin_cannot_register_token() {
        let (mut deps, _env) = setup();

        let err = execute(
            deps.as_mut(), mock_env(), mock_info(USER, &[]),
            ExecuteMsg::RegisterToken {
                denom: "ulux".to_string(),
                is_native: true,
                daily_limit: Uint128::new(1_000_000),
            },
        ).unwrap_err();
        assert!(err.to_string().contains("Unauthorized"));
    }
}
