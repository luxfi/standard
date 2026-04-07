(* Tests for Lux Bridge — Tezos (CameLIGO)
 *
 * Uses the CameLIGO Test module for contract origination and entrypoint calls.
 * Run with: ligo run test test_lux_bridge.mligo
 *)

#include "lux_bridge.mligo"

(* ================================================================
 * Helpers
 * ================================================================ *)

let dummy_key_1 : key = ("edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav" : key)
let dummy_key_2 : key = ("edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav" : key)
let dummy_key_3 : key = ("edpkuBknW28nW72KG6RoHtYW7p12T6GKc7nAbwYX5m8Wd9sDVC9yav" : key)

let make_config (admin : address) (fee : nat) : bridge_config = {
  admin = admin;
  mpc_signer_1 = dummy_key_1;
  mpc_signer_2 = dummy_key_2;
  mpc_signer_3 = dummy_key_3;
  threshold = 2n;
  fee_bps = fee;
  paused = false;
  outbound_nonce = 0n;
  total_locked = 0tez;
  total_burned = 0tez;
}

let make_storage (admin : address) (fee : nat) : storage = {
  config = make_config admin fee;
  processed_nonces = (Big_map.empty : (nonce_key, bool) big_map);
}

let originate_bridge (fee : nat) =
  let admin = Test.nth_bootstrap_account 0 in
  let store = make_storage admin fee in
  let addr, _, _ = Test.originate_uncurried main store 10000tez in
  (addr, admin)

let dummy_recipient : bytes = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef

(* ================================================================
 * Constructor / Initial State
 * ================================================================ *)

let test_initial_state_not_paused =
  let (addr, _admin) = originate_bridge 30n in
  let store = Test.get_storage addr in
  assert (not store.config.paused)

let test_initial_total_locked_zero =
  let (addr, _admin) = originate_bridge 30n in
  let store = Test.get_storage addr in
  assert (store.config.total_locked = 0tez)

let test_initial_total_burned_zero =
  let (addr, _admin) = originate_bridge 30n in
  let store = Test.get_storage addr in
  assert (store.config.total_burned = 0tez)

let test_initial_nonce_zero =
  let (addr, _admin) = originate_bridge 30n in
  let store = Test.get_storage addr in
  assert (store.config.outbound_nonce = 0n)

(* ================================================================
 * Admin — Pause / Unpause
 * ================================================================ *)

let test_admin_can_pause =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin Pause) 0tez in
  let store = Test.get_storage addr in
  assert store.config.paused

let test_admin_can_unpause =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin Pause) 0tez in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin Unpause) 0tez in
  let store = Test.get_storage addr in
  assert (not store.config.paused)

let test_non_admin_cannot_pause =
  let (addr, _admin) = originate_bridge 30n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let result = Test.transfer_to_contract (Test.to_contract addr) (Admin Pause) 0tez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

let test_non_admin_cannot_unpause =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin Pause) 0tez in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let result = Test.transfer_to_contract (Test.to_contract addr) (Admin Unpause) 0tez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

(* ================================================================
 * Admin — Set Fee
 * ================================================================ *)

let test_admin_can_set_fee =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin (SetFee 100n)) 0tez in
  let store = Test.get_storage addr in
  assert (store.config.fee_bps = 100n)

let test_set_fee_rejects_above_max =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let result = Test.transfer_to_contract (Test.to_contract addr) (Admin (SetFee 501n)) 0tez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

let test_set_fee_accepts_max =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin (SetFee 500n)) 0tez in
  let store = Test.get_storage addr in
  assert (store.config.fee_bps = 500n)

let test_non_admin_cannot_set_fee =
  let (addr, _admin) = originate_bridge 30n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let result = Test.transfer_to_contract (Test.to_contract addr) (Admin (SetFee 100n)) 0tez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

(* ================================================================
 * Lock and Bridge
 * ================================================================ *)

let test_lock_and_bridge_increments_nonce =
  let (addr, _admin) = originate_bridge 0n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : lock_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (LockAndBridge param) 1000mutez in
  let store = Test.get_storage addr in
  assert (store.config.outbound_nonce = 1n)

let test_lock_and_bridge_updates_total_locked =
  let (addr, _admin) = originate_bridge 0n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : lock_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (LockAndBridge param) 5000mutez in
  let store = Test.get_storage addr in
  assert (store.config.total_locked = 5000mutez)

let test_lock_and_bridge_deducts_fee =
  let (addr, _admin) = originate_bridge 100n in  (* 1% fee *)
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : lock_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (LockAndBridge param) 10000mutez in
  let store = Test.get_storage addr in
  (* fee = 10000 * 100 / 10000 = 100, bridge_amount = 9900 *)
  assert (store.config.total_locked = 9900mutez)

let test_lock_and_bridge_rejects_zero_amount =
  let (addr, _admin) = originate_bridge 30n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : lock_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let result = Test.transfer_to_contract (Test.to_contract addr) (LockAndBridge param) 0tez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

let test_lock_and_bridge_rejects_when_paused =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin Pause) 0tez in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : lock_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let result = Test.transfer_to_contract (Test.to_contract addr) (LockAndBridge param) 1000mutez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

(* ================================================================
 * Burn Bridged
 * ================================================================ *)

let test_burn_bridged_increments_nonce =
  let (addr, _admin) = originate_bridge 30n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : burn_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (BurnBridged param) 500mutez in
  let store = Test.get_storage addr in
  assert (store.config.outbound_nonce = 1n)

let test_burn_bridged_updates_total_burned =
  let (addr, _admin) = originate_bridge 30n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : burn_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (BurnBridged param) 500mutez in
  let store = Test.get_storage addr in
  assert (store.config.total_burned = 500mutez)

let test_burn_bridged_rejects_zero_amount =
  let (addr, _admin) = originate_bridge 30n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : burn_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let result = Test.transfer_to_contract (Test.to_contract addr) (BurnBridged param) 0tez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

let test_burn_bridged_rejects_when_paused =
  let (addr, admin) = originate_bridge 30n in
  let () = Test.set_source admin in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (Admin Pause) 0tez in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let param : burn_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let result = Test.transfer_to_contract (Test.to_contract addr) (BurnBridged param) 500mutez in
  match result with
  | Success _ -> Test.failwith "Should have failed"
  | Fail _ -> ()

(* ================================================================
 * Nonce sharing between lock and burn
 * ================================================================ *)

let test_lock_and_burn_share_nonce_counter =
  let (addr, _admin) = originate_bridge 0n in
  let user = Test.nth_bootstrap_account 1 in
  let () = Test.set_source user in
  let lock_param : lock_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let burn_param : burn_param = { dest_chain_id = 96369n; recipient = dummy_recipient } in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (LockAndBridge lock_param) 1000mutez in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (BurnBridged burn_param) 500mutez in
  let _ = Test.transfer_to_contract_exn (Test.to_contract addr) (LockAndBridge lock_param) 2000mutez in
  let store = Test.get_storage addr in
  assert (store.config.outbound_nonce = 3n)
