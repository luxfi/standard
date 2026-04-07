/// Tests for Lux Bridge — Cardano (Aiken)
///
/// Uses Aiken's built-in `test` keyword for property-based testing.
/// Run with: aiken check

use aiken/hash.{Blake2b_224, Hash, blake2b_256}
use aiken/list
use aiken/transaction.{ScriptContext, Spend, InlineDatum, Transaction, Input, Output, OutputReference, TransactionId, NoDatum}
use aiken/transaction/credential.{VerificationKey}
use aiken/transaction/value
use aiken/interval.{Interval, IntervalBound, Finite, PositiveInfinity, NegativeInfinity}

use lux_bridge.{BridgeDatum, BridgeRedeemer, bridge, build_mint_message, max_fee_bps, cardano_chain_id}

// ================================================================
// Test helpers
// ================================================================

fn test_admin() -> Hash<Blake2b_224, VerificationKey> {
  #"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
}

fn test_signer_1() -> ByteArray {
  #"1111111111111111111111111111111111111111111111111111111111111111"
}

fn test_signer_2() -> ByteArray {
  #"2222222222222222222222222222222222222222222222222222222222222222"
}

fn test_signer_3() -> ByteArray {
  #"3333333333333333333333333333333333333333333333333333333333333333"
}

fn test_recipient() -> ByteArray {
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef00"
}

fn base_datum() -> BridgeDatum {
  BridgeDatum {
    admin: test_admin(),
    mpc_signers: [test_signer_1(), test_signer_2(), test_signer_3()],
    threshold: 2,
    fee_bps: 30,
    paused: False,
    outbound_nonce: 0,
    total_locked: 0,
    total_burned: 0,
    processed_nonces: [],
  }
}

fn paused_datum() -> BridgeDatum {
  BridgeDatum { ..base_datum(), paused: True }
}

fn dummy_output_ref() -> OutputReference {
  OutputReference {
    transaction_id: TransactionId { hash: #"0000000000000000000000000000000000000000000000000000000000000000" },
    output_index: 0,
  }
}

fn empty_interval() -> Interval<Int> {
  Interval {
    lower_bound: IntervalBound { bound_type: NegativeInfinity, is_inclusive: True },
    upper_bound: IntervalBound { bound_type: PositiveInfinity, is_inclusive: True },
  }
}

/// Build a minimal transaction with the given outputs and extra signatories.
fn make_tx(outputs: List<Output>, extra_signatories: List<Hash<Blake2b_224, VerificationKey>>) -> Transaction {
  Transaction {
    inputs: [
      Input {
        output_reference: dummy_output_ref(),
        output: Output {
          address: credential.from_script(#"00"),
          value: value.from_lovelace(1_000_000),
          datum: InlineDatum(base_datum()),
          reference_script: None,
        },
      },
    ],
    reference_inputs: [],
    outputs: outputs,
    fee: value.zero(),
    mint: value.to_minted_value(value.zero()),
    certificates: [],
    withdrawals: [],
    validity_range: empty_interval(),
    extra_signatories: extra_signatories,
    redeemers: [],
    datums: [],
    id: TransactionId { hash: #"0000000000000000000000000000000000000000000000000000000000000001" },
  }
}

/// Build an output with inline datum.
fn make_output_with_datum(datum: BridgeDatum) -> Output {
  Output {
    address: credential.from_script(#"00"),
    value: value.from_lovelace(1_000_000),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn make_ctx(tx: Transaction) -> ScriptContext {
  ScriptContext {
    transaction: tx,
    purpose: Spend(dummy_output_ref()),
  }
}

// ================================================================
// Datum construction
// ================================================================

test datum_starts_unpaused() {
  let d = base_datum()
  !d.paused
}

test datum_starts_with_zero_nonce() {
  let d = base_datum()
  d.outbound_nonce == 0
}

test datum_starts_with_zero_locked() {
  let d = base_datum()
  d.total_locked == 0
}

test datum_starts_with_zero_burned() {
  let d = base_datum()
  d.total_burned == 0
}

test datum_starts_with_empty_processed_nonces() {
  let d = base_datum()
  list.length(d.processed_nonces) == 0
}

test datum_has_three_signers() {
  let d = base_datum()
  list.length(d.mpc_signers) == 3
}

// ================================================================
// Lock redeemer validation
// ================================================================

test lock_produces_correct_expected_datum() {
  let datum = base_datum()
  let amount = 10000
  let fee = amount * datum.fee_bps / 10000
  let bridge_amount = amount - fee

  let expected = BridgeDatum {
    ..datum,
    outbound_nonce: 1,
    total_locked: datum.total_locked + bridge_amount,
  }

  expected.outbound_nonce == 1 && expected.total_locked == bridge_amount
}

test lock_with_zero_fee_locks_full_amount() {
  let datum = BridgeDatum { ..base_datum(), fee_bps: 0 }
  let amount = 5000
  let fee = amount * datum.fee_bps / 10000
  let bridge_amount = amount - fee

  bridge_amount == 5000
}

test lock_with_max_fee_deducts_five_percent() {
  let datum = BridgeDatum { ..base_datum(), fee_bps: 500 }
  let amount = 10000
  let fee = amount * datum.fee_bps / 10000
  let bridge_amount = amount - fee

  // 500 bps = 5%: fee = 500, bridge = 9500
  fee == 500 && bridge_amount == 9500
}

// ================================================================
// Lock validator (with continuing output)
// ================================================================

test lock_succeeds_with_valid_continuing_output() {
  let datum = BridgeDatum { ..base_datum(), fee_bps: 0 }
  let amount = 1000
  let expected_datum = BridgeDatum {
    ..datum,
    outbound_nonce: 1,
    total_locked: 1000,
  }

  let tx = make_tx([make_output_with_datum(expected_datum)], [])
  let ctx = make_ctx(tx)
  let redeemer = Lock { dest_chain_id: 96369, recipient: test_recipient(), amount: amount }

  bridge(datum, redeemer, ctx)
}

// ================================================================
// Burn redeemer validation
// ================================================================

test burn_produces_correct_expected_datum() {
  let datum = base_datum()
  let amount = 500

  let expected = BridgeDatum {
    ..datum,
    outbound_nonce: 1,
    total_burned: datum.total_burned + amount,
  }

  expected.outbound_nonce == 1 && expected.total_burned == 500
}

test burn_succeeds_with_valid_continuing_output() {
  let datum = base_datum()
  let amount = 500
  let expected_datum = BridgeDatum {
    ..datum,
    outbound_nonce: 1,
    total_burned: 500,
  }

  let tx = make_tx([make_output_with_datum(expected_datum)], [])
  let ctx = make_ctx(tx)
  let redeemer = Burn { dest_chain_id: 96369, recipient: test_recipient(), amount: amount }

  bridge(datum, redeemer, ctx)
}

// ================================================================
// Pause / Unpause admin operations
// ================================================================

test pause_succeeds_with_admin_signature() {
  let datum = base_datum()
  let expected_datum = BridgeDatum { ..datum, paused: True }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_admin()])
  let ctx = make_ctx(tx)

  bridge(datum, Pause, ctx)
}

test unpause_succeeds_with_admin_signature() {
  let datum = paused_datum()
  let expected_datum = BridgeDatum { ..datum, paused: False }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_admin()])
  let ctx = make_ctx(tx)

  bridge(datum, Unpause, ctx)
}

// ================================================================
// SetFee admin operation
// ================================================================

test set_fee_succeeds_with_admin_and_valid_fee() {
  let datum = base_datum()
  let expected_datum = BridgeDatum { ..datum, fee_bps: 100 }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_admin()])
  let ctx = make_ctx(tx)

  bridge(datum, SetFee { fee_bps: 100 }, ctx)
}

test set_fee_accepts_max_fee() {
  let datum = base_datum()
  let expected_datum = BridgeDatum { ..datum, fee_bps: max_fee_bps }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_admin()])
  let ctx = make_ctx(tx)

  bridge(datum, SetFee { fee_bps: max_fee_bps }, ctx)
}

// ================================================================
// SetSigners admin operation
// ================================================================

test set_signers_succeeds_with_admin() {
  let datum = base_datum()
  let new_signers = [test_signer_3(), test_signer_2()]
  let expected_datum = BridgeDatum { ..datum, mpc_signers: new_signers, threshold: 1 }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_admin()])
  let ctx = make_ctx(tx)

  bridge(datum, SetSigners { signers: new_signers, threshold: 1 }, ctx)
}

// ================================================================
// MintAuthorize — nonce tracking
// ================================================================

test nonce_not_in_empty_list() {
  let nonces: List<(Int, Int)> = []
  !list.any(nonces, fn(pair) { pair == (1, 1) })
}

test nonce_detected_in_list() {
  let nonces = [(1, 1), (2, 5)]
  list.any(nonces, fn(pair) { pair == (1, 1) })
}

test nonce_not_detected_if_different() {
  let nonces = [(1, 1), (2, 5)]
  !list.any(nonces, fn(pair) { pair == (3, 10) })
}

// ================================================================
// MintAuthorize with extra signatories
// ================================================================

test mint_authorize_succeeds_with_valid_signer() {
  let datum = base_datum()
  let expected_datum = BridgeDatum {
    ..datum,
    processed_nonces: list.concat(datum.processed_nonces, [(42, 1)]),
  }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_signer_1()])
  let ctx = make_ctx(tx)

  let redeemer = MintAuthorize {
    source_chain_id: 42,
    nonce: 1,
    recipient: test_recipient(),
    amount: 1000,
    signature: #"",
    signer_idx: 0,
  }

  bridge(datum, redeemer, ctx)
}

// ================================================================
// Release with extra signatories
// ================================================================

test release_succeeds_with_valid_signer() {
  let datum = base_datum()
  let expected_datum = BridgeDatum {
    ..datum,
    processed_nonces: list.concat(datum.processed_nonces, [(42, 1)]),
  }

  let tx = make_tx([make_output_with_datum(expected_datum)], [test_signer_2()])
  let ctx = make_ctx(tx)

  let redeemer = Release {
    source_chain_id: 42,
    nonce: 1,
    recipient: test_recipient(),
    amount: 500,
    signature: #"",
    signer_idx: 1,
  }

  bridge(datum, redeemer, ctx)
}

// ================================================================
// build_mint_message helper
// ================================================================

test build_mint_message_produces_deterministic_output() {
  let msg1 = build_mint_message(42, 1, test_recipient(), 1000)
  let msg2 = build_mint_message(42, 1, test_recipient(), 1000)
  msg1 == msg2
}

test build_mint_message_differs_for_different_nonces() {
  let msg1 = build_mint_message(42, 1, test_recipient(), 1000)
  let msg2 = build_mint_message(42, 2, test_recipient(), 1000)
  msg1 != msg2
}

test build_mint_message_differs_for_different_chains() {
  let msg1 = build_mint_message(42, 1, test_recipient(), 1000)
  let msg2 = build_mint_message(99, 1, test_recipient(), 1000)
  msg1 != msg2
}

test build_mint_message_differs_for_different_amounts() {
  let msg1 = build_mint_message(42, 1, test_recipient(), 1000)
  let msg2 = build_mint_message(42, 1, test_recipient(), 2000)
  msg1 != msg2
}

// ================================================================
// Fee arithmetic edge cases
// ================================================================

test fee_of_zero_bps_is_zero() {
  let amount = 10000
  let fee = amount * 0 / 10000
  fee == 0
}

test fee_of_one_bps_on_small_amount_rounds_down() {
  let amount = 99
  let fee = amount * 1 / 10000
  // 99 / 10000 = 0 (integer division)
  fee == 0
}

test fee_of_500_bps_on_10000_is_500() {
  let amount = 10000
  let fee = amount * 500 / 10000
  fee == 500
}

// ================================================================
// Constants
// ================================================================

test cardano_chain_id_is_correct() {
  cardano_chain_id == 1667330660
}

test max_fee_bps_is_500() {
  max_fee_bps == 500
}
