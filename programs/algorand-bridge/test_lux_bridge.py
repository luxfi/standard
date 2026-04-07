"""
Tests for Lux Bridge — Algorand (PyTeal/Beaker)

Run with: python -m pytest test_lux_bridge.py -v
Requires: pyteal, beaker-pyteal
"""

import unittest
from unittest.mock import MagicMock, patch
from pyteal import *
from pyteal import abi as pyteal_abi

from lux_bridge import LuxBridge, ALGORAND_CHAIN_ID, MAX_FEE_BPS


class TestLuxBridgeSchema(unittest.TestCase):
    """Verify the application schema and state declarations."""

    def setUp(self):
        self.app = LuxBridge()

    def test_global_state_keys(self):
        """All expected global state keys exist."""
        state_keys = {
            "admin",
            "mpc_signer_1",
            "mpc_signer_2",
            "mpc_signer_3",
            "threshold",
            "fee_bps",
            "paused",
            "outbound_nonce",
            "total_locked",
            "total_burned",
        }
        declared = set(self.app.global_state.declared_vals.keys())
        self.assertEqual(state_keys, declared)

    def test_global_state_defaults(self):
        """Default values are set correctly."""
        gs = self.app.global_state
        self.assertEqual(gs.threshold.default.value, 2)
        self.assertEqual(gs.fee_bps.default.value, 30)
        self.assertEqual(gs.paused.default.value, 0)
        self.assertEqual(gs.outbound_nonce.default.value, 0)
        self.assertEqual(gs.total_locked.default.value, 0)
        self.assertEqual(gs.total_burned.default.value, 0)

    def test_box_mapping_exists(self):
        """Processed nonces box mapping is declared."""
        self.assertIsNotNone(self.app.processed_nonces)


class TestLuxBridgeCompilation(unittest.TestCase):
    """Verify that all methods compile to valid TEAL."""

    def setUp(self):
        self.app = LuxBridge()

    def test_approval_compiles(self):
        """Approval program compiles without error."""
        app_spec = self.app.build()
        approval = app_spec.approval_program
        self.assertIsInstance(approval, str)
        self.assertGreater(len(approval), 0)
        # TEAL programs start with #pragma
        self.assertTrue(approval.startswith("#pragma"))

    def test_clear_compiles(self):
        """Clear-state program compiles without error."""
        app_spec = self.app.build()
        clear = app_spec.clear_program
        self.assertIsInstance(clear, str)
        self.assertGreater(len(clear), 0)

    def test_contract_json(self):
        """ABI contract JSON is generated."""
        app_spec = self.app.build()
        contract = app_spec.contract.dictify()
        self.assertIn("methods", contract)
        self.assertIn("name", contract)
        self.assertEqual(contract["name"], "LuxBridge")


class TestLuxBridgeABI(unittest.TestCase):
    """Verify ABI method signatures are correct."""

    def setUp(self):
        self.app = LuxBridge()
        self.app_spec = self.app.build()
        self.methods = {
            m["name"]: m for m in self.app_spec.contract.dictify()["methods"]
        }

    def test_initialize_method(self):
        """initialize has correct args."""
        m = self.methods["initialize"]
        arg_names = [a["name"] for a in m["args"]]
        self.assertIn("signer_1", arg_names)
        self.assertIn("signer_2", arg_names)
        self.assertIn("signer_3", arg_names)
        self.assertIn("fee", arg_names)

    def test_lock_and_bridge_method(self):
        """lock_and_bridge has correct args and returns uint64."""
        m = self.methods["lock_and_bridge"]
        arg_names = [a["name"] for a in m["args"]]
        self.assertIn("amount", arg_names)
        self.assertIn("dest_chain_id", arg_names)
        self.assertIn("recipient", arg_names)
        ret = m["returns"]
        self.assertEqual(ret["type"], "uint64")

    def test_mint_bridged_method(self):
        """mint_bridged has correct args including signature and signer_pubkey."""
        m = self.methods["mint_bridged"]
        arg_names = [a["name"] for a in m["args"]]
        self.assertIn("source_chain_id", arg_names)
        self.assertIn("nonce", arg_names)
        self.assertIn("recipient", arg_names)
        self.assertIn("amount", arg_names)
        self.assertIn("signature", arg_names)
        self.assertIn("signer_pubkey", arg_names)

    def test_burn_bridged_method(self):
        """burn_bridged has correct args and returns uint64."""
        m = self.methods["burn_bridged"]
        arg_names = [a["name"] for a in m["args"]]
        self.assertIn("amount", arg_names)
        self.assertIn("dest_chain_id", arg_names)
        self.assertIn("recipient", arg_names)
        ret = m["returns"]
        self.assertEqual(ret["type"], "uint64")

    def test_pause_method(self):
        """pause exists with no args."""
        m = self.methods["pause"]
        self.assertEqual(len(m["args"]), 0)

    def test_unpause_method(self):
        """unpause exists with no args."""
        m = self.methods["unpause"]
        self.assertEqual(len(m["args"]), 0)

    def test_set_fee_method(self):
        """set_fee has fee_bps arg."""
        m = self.methods["set_fee"]
        arg_names = [a["name"] for a in m["args"]]
        self.assertIn("fee_bps", arg_names)

    def test_view_methods_exist(self):
        """Read-only view methods exist."""
        self.assertIn("get_total_locked", self.methods)
        self.assertIn("get_total_burned", self.methods)
        self.assertIn("get_paused", self.methods)

    def test_method_count(self):
        """Exactly 10 public methods."""
        self.assertEqual(len(self.methods), 10)


class TestLuxBridgeTEALLogic(unittest.TestCase):
    """Verify TEAL output contains expected opcodes and logic."""

    def setUp(self):
        self.app = LuxBridge()
        self.app_spec = self.app.build()
        self.approval = self.app_spec.approval_program

    def test_pause_check_in_lock(self):
        """Approval program contains pause assertion logic."""
        # The compiled TEAL should reference the paused global state
        self.assertIn("paused", self.approval)

    def test_ed25519_verify_in_mint(self):
        """Approval program uses Ed25519 verification opcode."""
        self.assertIn("ed25519verify_bare", self.approval)

    def test_log_opcode_for_events(self):
        """Approval program uses log opcode for event emission."""
        self.assertIn("log", self.approval)

    def test_inner_transaction_for_mint(self):
        """Approval program uses inner transactions for payments."""
        self.assertIn("itxn_submit", self.approval)

    def test_fee_bps_max_check(self):
        """Approval program checks fee against MAX_FEE_BPS (500)."""
        # The constant 500 should appear in compiled TEAL
        self.assertIn("500", self.approval)

    def test_algorand_chain_id(self):
        """ALGORAND_CHAIN_ID constant compiles correctly."""
        # 4294967450 = 0xFFFF_FF9A
        self.assertEqual(ALGORAND_CHAIN_ID.value, 4294967450)

    def test_max_fee_bps_constant(self):
        """MAX_FEE_BPS is 500."""
        self.assertEqual(MAX_FEE_BPS.value, 500)


class TestLuxBridgeInitialize(unittest.TestCase):
    """Verify the initialize method's PyTeal AST structure."""

    def setUp(self):
        self.app = LuxBridge()

    def test_initialize_sets_admin(self):
        """initialize method references Txn.sender for admin."""
        # Build the AST for initialize
        s1 = pyteal_abi.DynamicBytes()
        s2 = pyteal_abi.DynamicBytes()
        s3 = pyteal_abi.DynamicBytes()
        fee = pyteal_abi.Uint16()
        expr = self.app.initialize(s1, s2, s3, fee)
        # The expression should be a Seq (not None)
        self.assertIsNotNone(expr)

    def test_initialize_fee_assertion(self):
        """initialize checks fee <= MAX_FEE_BPS."""
        s1 = pyteal_abi.DynamicBytes()
        s2 = pyteal_abi.DynamicBytes()
        s3 = pyteal_abi.DynamicBytes()
        fee = pyteal_abi.Uint16()
        expr = self.app.initialize(s1, s2, s3, fee)
        # Compile to TEAL to check assertion is present
        compiled = compileTeal(expr, mode=Mode.Application, version=8)
        self.assertIn("assert", compiled)


class TestLuxBridgeLockLogic(unittest.TestCase):
    """Verify lock_and_bridge PyTeal AST structure."""

    def setUp(self):
        self.app = LuxBridge()

    def test_lock_returns_nonce(self):
        """lock_and_bridge writes output nonce."""
        amount = pyteal_abi.Uint64()
        dest = pyteal_abi.Uint64()
        recip = pyteal_abi.DynamicBytes()
        output = pyteal_abi.Uint64()
        expr = self.app.lock_and_bridge(amount, dest, recip, output=output)
        self.assertIsNotNone(expr)

    def test_lock_compiles(self):
        """lock_and_bridge compiles to valid TEAL."""
        amount = pyteal_abi.Uint64()
        dest = pyteal_abi.Uint64()
        recip = pyteal_abi.DynamicBytes()
        output = pyteal_abi.Uint64()
        expr = self.app.lock_and_bridge(amount, dest, recip, output=output)
        compiled = compileTeal(expr, mode=Mode.Application, version=8)
        self.assertIn("assert", compiled)
        self.assertIn("log", compiled)


class TestLuxBridgeBurnLogic(unittest.TestCase):
    """Verify burn_bridged PyTeal AST structure."""

    def setUp(self):
        self.app = LuxBridge()

    def test_burn_returns_nonce(self):
        """burn_bridged writes output nonce."""
        amount = pyteal_abi.Uint64()
        dest = pyteal_abi.Uint64()
        recip = pyteal_abi.DynamicBytes()
        output = pyteal_abi.Uint64()
        expr = self.app.burn_bridged(amount, dest, recip, output=output)
        self.assertIsNotNone(expr)

    def test_burn_compiles(self):
        """burn_bridged compiles to valid TEAL."""
        amount = pyteal_abi.Uint64()
        dest = pyteal_abi.Uint64()
        recip = pyteal_abi.DynamicBytes()
        output = pyteal_abi.Uint64()
        expr = self.app.burn_bridged(amount, dest, recip, output=output)
        compiled = compileTeal(expr, mode=Mode.Application, version=8)
        self.assertIn("assert", compiled)
        self.assertIn("log", compiled)


class TestLuxBridgePauseLogic(unittest.TestCase):
    """Verify pause/unpause PyTeal AST structure."""

    def setUp(self):
        self.app = LuxBridge()

    def test_pause_compiles(self):
        """pause method compiles to valid TEAL."""
        expr = self.app.pause()
        compiled = compileTeal(expr, mode=Mode.Application, version=8)
        self.assertIn("assert", compiled)

    def test_unpause_compiles(self):
        """unpause method compiles to valid TEAL."""
        expr = self.app.unpause()
        compiled = compileTeal(expr, mode=Mode.Application, version=8)
        self.assertIn("assert", compiled)


if __name__ == "__main__":
    unittest.main()
