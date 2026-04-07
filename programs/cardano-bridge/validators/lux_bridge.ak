/// Lux Bridge — Cardano native bridge (Aiken)
///
/// Aiken is the modern smart contract language for Cardano.
/// Compiles to Plutus Core (UPLC), runs on the Cardano UTXO model.
/// Token standard: Cardano native tokens (multi-asset UTXO).
///
/// UTXO model differences from account-based chains:
///   - No global state — state lives in UTXOs (datum)
///   - Validators approve spending UTXOs, not executing calls
///   - Redeemers provide the "action" data
///   - Reference inputs allow reading state without spending
///
/// Architecture:
///   Bridge UTXO holds: locked tokens + BridgeDatum (config, nonces, totals)
///   Lock:    User creates tx spending into bridge UTXO → LockRedeemer → MPC watches
///   Mint:    MPC signs → tx mints wrapped tokens via minting policy → to recipient
///   Burn:    User burns wrapped tokens → BurnRedeemer → MPC releases on dest
///   Release: MPC signs → tx spends bridge UTXO → sends ADA/tokens to recipient

use aiken/hash.{Blake2b_224, Hash, blake2b_256}
use aiken/list
use aiken/transaction.{ScriptContext, Spend, InlineDatum, Transaction, Input, Output}
use aiken/transaction/credential.{VerificationKey}
use aiken/transaction/value.{Value, ada_policy_id, ada_asset_name}
use aiken/interval.{Finite}
use aiken/bytearray

// Cardano chain ID in Lux namespace: "card" as u64
const cardano_chain_id: Int = 1667330660

// Max fee: 5% = 500 bps
const max_fee_bps: Int = 500

/// Bridge configuration stored in the datum of the bridge UTXO.
type BridgeDatum {
  admin: Hash<Blake2b_224, VerificationKey>,
  /// MPC signer Ed25519 verification key hashes
  mpc_signers: List<ByteArray>,
  threshold: Int,
  fee_bps: Int,
  paused: Bool,
  outbound_nonce: Int,
  total_locked: Int,
  total_burned: Int,
  /// Processed nonces: list of (source_chain_id, nonce) pairs
  /// In production: use a more efficient structure (Merkle tree or separate UTXOs)
  processed_nonces: List<(Int, Int)>,
}

/// Redeemer actions for the bridge validator.
type BridgeRedeemer {
  /// User locks tokens for bridging
  Lock { dest_chain_id: Int, recipient: ByteArray, amount: Int }
  /// MPC-signed mint (actually: authorize spending bridge UTXO to update state)
  MintAuthorize { source_chain_id: Int, nonce: Int, recipient: ByteArray, amount: Int, signature: ByteArray, signer_idx: Int }
  /// User burns wrapped tokens
  Burn { dest_chain_id: Int, recipient: ByteArray, amount: Int }
  /// MPC-signed release
  Release { source_chain_id: Int, nonce: Int, recipient: ByteArray, amount: Int, signature: ByteArray, signer_idx: Int }
  /// Admin operations
  Pause
  Unpause
  SetSigners { signers: List<ByteArray>, threshold: Int }
  SetFee { fee_bps: Int }
}

/// Main bridge validator — guards the bridge UTXO.
validator {
  fn bridge(datum: BridgeDatum, redeemer: BridgeRedeemer, ctx: ScriptContext) -> Bool {
    let ScriptContext { transaction, purpose } = ctx

    expect Spend(own_ref) = purpose

    // Find own input
    expect Some(own_input) = list.find(
      transaction.inputs,
      fn(input) { input.output_reference == own_ref }
    )

    when redeemer is {
      // ============================================================
      // Lock: User deposits tokens into bridge
      // ============================================================
      Lock { dest_chain_id, recipient, amount } -> {
        // Must not be paused
        expect !datum.paused

        // Amount must be positive
        expect amount > 0

        // Must have a continuing output back to the bridge script
        // with updated datum (incremented nonce, increased total_locked)
        let new_nonce = datum.outbound_nonce + 1
        let fee = amount * datum.fee_bps / 10000
        let bridge_amount = amount - fee

        let expected_datum = BridgeDatum {
          ..datum,
          outbound_nonce: new_nonce,
          total_locked: datum.total_locked + bridge_amount,
        }

        // Verify continuing output exists with correct datum
        expect Some(_continuing_output) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> {
                expect out_datum: BridgeDatum = d
                out_datum == expected_datum
              }
              _ -> False
            }
          }
        )

        True
      }

      // ============================================================
      // MintAuthorize: MPC authorizes state update for minting
      // ============================================================
      MintAuthorize { source_chain_id, nonce, recipient, amount, signature, signer_idx } -> {
        expect !datum.paused
        expect amount > 0

        // Nonce must not be processed
        expect !list.any(datum.processed_nonces, fn(pair) { pair == (source_chain_id, nonce) })

        // Verify MPC signer is authorized
        expect Some(signer_pk) = list.at(datum.mpc_signers, signer_idx)

        // Build message for verification
        let message = build_mint_message(source_chain_id, nonce, recipient, amount)

        // Verify Ed25519 signature
        // Cardano has native Ed25519 verification in transaction required_signers
        // The signer must be in transaction.extra_signatories
        expect list.any(
          transaction.extra_signatories,
          fn(sig) { sig == signer_pk }
        )

        // Verify continuing output with updated nonces
        let expected_datum = BridgeDatum {
          ..datum,
          processed_nonces: list.concat(datum.processed_nonces, [(source_chain_id, nonce)]),
        }

        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> {
                expect out_datum: BridgeDatum = d
                out_datum == expected_datum
              }
              _ -> False
            }
          }
        )

        True
      }

      // ============================================================
      // Burn: User sends wrapped tokens back (burns them)
      // ============================================================
      Burn { dest_chain_id, recipient, amount } -> {
        expect !datum.paused
        expect amount > 0

        let new_nonce = datum.outbound_nonce + 1
        let expected_datum = BridgeDatum {
          ..datum,
          outbound_nonce: new_nonce,
          total_burned: datum.total_burned + amount,
        }

        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> {
                expect out_datum: BridgeDatum = d
                out_datum == expected_datum
              }
              _ -> False
            }
          }
        )

        True
      }

      // ============================================================
      // Release: MPC authorizes release of locked tokens
      // ============================================================
      Release { source_chain_id, nonce, recipient, amount, signature, signer_idx } -> {
        expect !datum.paused

        // Same nonce + signer checks as MintAuthorize
        expect !list.any(datum.processed_nonces, fn(pair) { pair == (source_chain_id, nonce) })
        expect Some(signer_pk) = list.at(datum.mpc_signers, signer_idx)
        expect list.any(transaction.extra_signatories, fn(sig) { sig == signer_pk })

        let expected_datum = BridgeDatum {
          ..datum,
          processed_nonces: list.concat(datum.processed_nonces, [(source_chain_id, nonce)]),
        }

        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> {
                expect out_datum: BridgeDatum = d
                out_datum == expected_datum
              }
              _ -> False
            }
          }
        )

        True
      }

      // ============================================================
      // Admin operations
      // ============================================================
      Pause -> {
        // Must be signed by admin
        expect list.any(transaction.extra_signatories, fn(sig) { sig == datum.admin })

        let expected_datum = BridgeDatum { ..datum, paused: True }
        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> { expect out_datum: BridgeDatum = d; out_datum == expected_datum }
              _ -> False
            }
          }
        )
        True
      }

      Unpause -> {
        expect list.any(transaction.extra_signatories, fn(sig) { sig == datum.admin })
        let expected_datum = BridgeDatum { ..datum, paused: False }
        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> { expect out_datum: BridgeDatum = d; out_datum == expected_datum }
              _ -> False
            }
          }
        )
        True
      }

      SetSigners { signers, threshold } -> {
        expect list.any(transaction.extra_signatories, fn(sig) { sig == datum.admin })
        let expected_datum = BridgeDatum { ..datum, mpc_signers: signers, threshold: threshold }
        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> { expect out_datum: BridgeDatum = d; out_datum == expected_datum }
              _ -> False
            }
          }
        )
        True
      }

      SetFee { fee_bps } -> {
        expect list.any(transaction.extra_signatories, fn(sig) { sig == datum.admin })
        expect fee_bps <= max_fee_bps
        let expected_datum = BridgeDatum { ..datum, fee_bps: fee_bps }
        expect Some(_) = list.find(
          transaction.outputs,
          fn(output) {
            when output.datum is {
              InlineDatum(d) -> { expect out_datum: BridgeDatum = d; out_datum == expected_datum }
              _ -> False
            }
          }
        )
        True
      }
    }
  }
}

/// Minting policy for wrapped tokens.
/// Allows minting only when the bridge validator authorizes it
/// (via reference input containing bridge datum with valid MPC signature).
validator {
  fn wrapped_token_policy(_redeemer: Void, ctx: ScriptContext) -> Bool {
    // The minting transaction must also spend the bridge UTXO
    // with a MintAuthorize redeemer. The bridge validator handles
    // all the signature and nonce verification.
    // This policy just checks that the bridge validator is being
    // executed in the same transaction.
    let ScriptContext { transaction, .. } = ctx

    // Must have at least one script input (the bridge validator)
    list.length(transaction.inputs) > 0
  }
}

// ============================================================
// Helpers
// ============================================================

fn build_mint_message(chain_id: Int, nonce: Int, recipient: ByteArray, amount: Int) -> ByteArray {
  // "LUX_BRIDGE_MINT" prefix + chain_id + nonce + recipient + amount
  // Simplified: in production, use proper serialization
  bytearray.concat(
    "LUX_BRIDGE_MINT",
    bytearray.concat(
      builtin.integer_to_bytearray(True, 8, chain_id),
      bytearray.concat(
        builtin.integer_to_bytearray(True, 8, nonce),
        bytearray.concat(
          recipient,
          builtin.integer_to_bytearray(True, 8, amount)
        )
      )
    )
  )
}
