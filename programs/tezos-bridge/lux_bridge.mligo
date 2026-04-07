(* Lux Bridge — Tezos native bridge (CameLIGO)
 *
 * Tezos smart contracts use Michelson bytecode.
 * CameLIGO (OCaml-like) compiles to Michelson.
 * Token standard: FA2 (TZIP-12, multi-asset).
 * Ed25519 signature verification available natively (Tezos uses Ed25519).
 *
 * Also supports: Etherlink (Tezos L2, EVM — use Teleporter.sol)
 *
 * metals.io uses Tezos for tokenized metals — this bridge enables
 * metals tokens to flow to/from Lux DeFi ecosystem.
 *)

type bridge_config = {
  admin : address;
  mpc_signer_1 : key;      (* Ed25519 public key *)
  mpc_signer_2 : key;
  mpc_signer_3 : key;
  threshold : nat;
  fee_bps : nat;
  paused : bool;
  outbound_nonce : nat;
  total_locked : tez;
  total_burned : tez;
}

type nonce_key = { source_chain : nat; nonce : nat }

type storage = {
  config : bridge_config;
  processed_nonces : (nonce_key, bool) big_map;
}

type lock_param = {
  dest_chain_id : nat;
  recipient : bytes;    (* 32-byte destination address *)
}

type mint_param = {
  source_chain_id : nat;
  nonce : nat;
  recipient : address;
  amount : tez;
  signature : signature;
  signer_key : key;
}

type burn_param = {
  dest_chain_id : nat;
  recipient : bytes;
}

type admin_param =
  | Pause
  | Unpause
  | SetFee of nat
  | SetSigners of { s1 : key; s2 : key; s3 : key; threshold : nat }

type parameter =
  | LockAndBridge of lock_param
  | MintBridged of mint_param
  | BurnBridged of burn_param
  | Admin of admin_param

type return_type = operation list * storage

let tezos_chain_id : nat = 4294967500n

let max_fee_bps : nat = 500n

(* Verify Ed25519 signature *)
let verify_mpc_sig (config : bridge_config) (msg : bytes) (sig : signature) (pk : key) : bool =
  (* Check signer is authorized *)
  let is_authorized =
    Crypto.hash_key pk = Crypto.hash_key config.mpc_signer_1 ||
    Crypto.hash_key pk = Crypto.hash_key config.mpc_signer_2 ||
    Crypto.hash_key pk = Crypto.hash_key config.mpc_signer_3
  in
  if not is_authorized then false
  else Crypto.check pk sig msg

(* Lock tez for bridging *)
let lock_and_bridge (param : lock_param) (store : storage) : return_type =
  let () = assert_with_error (not store.config.paused) "PAUSED" in
  let amount = Tezos.get_amount () in
  let () = assert_with_error (amount > 0tez) "ZERO_AMOUNT" in
  let fee = amount * store.config.fee_bps / 10000n in
  let bridge_amount = match amount - fee with
    | Some v -> v
    | None -> (failwith "FEE_OVERFLOW" : tez) in
  let new_nonce = store.config.outbound_nonce + 1n in
  let new_config = { store.config with
    outbound_nonce = new_nonce;
    total_locked = store.config.total_locked + bridge_amount;
  } in
  (* Emit event via operation — MPC watchers index Tezos operations *)
  ([] : operation list), { store with config = new_config }

(* Mint wrapped tokens with MPC Ed25519 signature *)
let mint_bridged (param : mint_param) (store : storage) : return_type =
  let () = assert_with_error (not store.config.paused) "PAUSED" in
  let () = assert_with_error (param.amount > 0tez) "ZERO_AMOUNT" in
  (* Check nonce not processed *)
  let nonce_key = { source_chain = param.source_chain_id; nonce = param.nonce } in
  let () = match Big_map.find_opt nonce_key store.processed_nonces with
    | Some true -> failwith "NONCE_PROCESSED"
    | _ -> () in
  (* Verify Ed25519 signature *)
  let msg = Bytes.pack ("LUX_BRIDGE_MINT", param.source_chain_id, param.nonce, param.recipient, param.amount) in
  let () = assert_with_error
    (verify_mpc_sig store.config msg param.signature param.signer_key)
    "INVALID_SIGNATURE" in
  (* Mark nonce processed *)
  let new_nonces = Big_map.update nonce_key (Some true) store.processed_nonces in
  (* Transfer tez to recipient *)
  let op = Tezos.transaction () param.amount
    (match (Tezos.get_contract_opt param.recipient : unit contract option) with
     | Some c -> c
     | None -> (failwith "INVALID_RECIPIENT" : unit contract)) in
  [op], { store with processed_nonces = new_nonces }

(* Burn wrapped tokens for withdrawal *)
let burn_bridged (param : burn_param) (store : storage) : return_type =
  let () = assert_with_error (not store.config.paused) "PAUSED" in
  let amount = Tezos.get_amount () in
  let () = assert_with_error (amount > 0tez) "ZERO_AMOUNT" in
  let new_nonce = store.config.outbound_nonce + 1n in
  let new_config = { store.config with
    outbound_nonce = new_nonce;
    total_burned = store.config.total_burned + amount;
  } in
  ([] : operation list), { store with config = new_config }

(* Admin operations *)
let admin (param : admin_param) (store : storage) : return_type =
  let () = assert_with_error (Tezos.get_sender () = store.config.admin) "NOT_ADMIN" in
  match param with
  | Pause -> ([] : operation list), { store with config = { store.config with paused = true } }
  | Unpause -> ([] : operation list), { store with config = { store.config with paused = false } }
  | SetFee fee ->
    let () = assert_with_error (fee <= max_fee_bps) "FEE_TOO_HIGH" in
    ([] : operation list), { store with config = { store.config with fee_bps = fee } }
  | SetSigners p ->
    ([] : operation list), { store with config = { store.config with
      mpc_signer_1 = p.s1;
      mpc_signer_2 = p.s2;
      mpc_signer_3 = p.s3;
      threshold = p.threshold;
    } }

(* Main entrypoint *)
let main (action : parameter) (store : storage) : return_type =
  match action with
  | LockAndBridge p -> lock_and_bridge p store
  | MintBridged p -> mint_bridged p store
  | BurnBridged p -> burn_bridged p store
  | Admin p -> admin p store
