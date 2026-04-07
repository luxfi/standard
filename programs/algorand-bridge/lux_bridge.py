"""
Lux Bridge — Algorand native bridge (PyTeal/ARC-4)

Algorand smart contracts use PyTeal compiled to TEAL.
Token standard: ASA (Algorand Standard Asset).
Ed25519 signature verification available natively.
"""

from pyteal import *
from beaker import Application, GlobalStateValue, LocalStateValue
from beaker.lib.storage import BoxMapping

# Algorand chain ID in Lux namespace
ALGORAND_CHAIN_ID = Int(4294967450)
MAX_FEE_BPS = Int(500)


class LuxBridge(Application):
    """Lux Bridge for Algorand — lock/mint/burn/release with MPC Ed25519 signatures."""

    # Global state
    admin = GlobalStateValue(stack_type=TealType.bytes, default=Bytes(""))
    mpc_signer_1 = GlobalStateValue(stack_type=TealType.bytes, default=Bytes(""))
    mpc_signer_2 = GlobalStateValue(stack_type=TealType.bytes, default=Bytes(""))
    mpc_signer_3 = GlobalStateValue(stack_type=TealType.bytes, default=Bytes(""))
    threshold = GlobalStateValue(stack_type=TealType.uint64, default=Int(2))
    fee_bps = GlobalStateValue(stack_type=TealType.uint64, default=Int(30))
    paused = GlobalStateValue(stack_type=TealType.uint64, default=Int(0))
    outbound_nonce = GlobalStateValue(stack_type=TealType.uint64, default=Int(0))
    total_locked = GlobalStateValue(stack_type=TealType.uint64, default=Int(0))
    total_burned = GlobalStateValue(stack_type=TealType.uint64, default=Int(0))

    # Box storage for nonce tracking
    processed_nonces = BoxMapping(TealType.bytes, TealType.uint64)

    @external
    def initialize(
        self,
        signer_1: abi.DynamicBytes,
        signer_2: abi.DynamicBytes,
        signer_3: abi.DynamicBytes,
        fee: abi.Uint16,
    ):
        return Seq(
            Assert(fee.get() <= MAX_FEE_BPS),
            self.admin.set(Txn.sender()),
            self.mpc_signer_1.set(signer_1.get()),
            self.mpc_signer_2.set(signer_2.get()),
            self.mpc_signer_3.set(signer_3.get()),
            self.fee_bps.set(fee.get()),
        )

    @external
    def lock_and_bridge(
        self,
        amount: abi.Uint64,
        dest_chain_id: abi.Uint64,
        recipient: abi.DynamicBytes,
        *,
        output: abi.Uint64,
    ):
        """Lock ALGO/ASA for bridging. Emits LockEvent via inner tx log."""
        fee = ScratchVar(TealType.uint64)
        bridge_amount = ScratchVar(TealType.uint64)
        nonce = ScratchVar(TealType.uint64)
        return Seq(
            Assert(self.paused.get() == Int(0)),
            Assert(amount.get() > Int(0)),
            # Calculate fee
            fee.store(amount.get() * self.fee_bps.get() / Int(10000)),
            bridge_amount.store(amount.get() - fee.load()),
            # Update state
            self.total_locked.set(self.total_locked.get() + bridge_amount.load()),
            self.outbound_nonce.set(self.outbound_nonce.get() + Int(1)),
            nonce.store(self.outbound_nonce.get()),
            # Log event for MPC watchers
            Log(Concat(
                Bytes("LOCK:"),
                Itob(ALGORAND_CHAIN_ID),
                Itob(dest_chain_id.get()),
                Itob(nonce.load()),
                Txn.sender(),
                recipient.get(),
                Itob(bridge_amount.load()),
            )),
            output.set(nonce.load()),
        )

    @external
    def mint_bridged(
        self,
        source_chain_id: abi.Uint64,
        nonce: abi.Uint64,
        recipient: abi.Address,
        amount: abi.Uint64,
        signature: abi.DynamicBytes,
        signer_pubkey: abi.DynamicBytes,
    ):
        """Mint wrapped tokens with MPC Ed25519 signature."""
        nonce_key = ScratchVar(TealType.bytes)
        return Seq(
            Assert(self.paused.get() == Int(0)),
            Assert(amount.get() > Int(0)),
            # Verify signer authorized
            Assert(
                Or(
                    signer_pubkey.get() == self.mpc_signer_1.get(),
                    signer_pubkey.get() == self.mpc_signer_2.get(),
                    signer_pubkey.get() == self.mpc_signer_3.get(),
                )
            ),
            # Check nonce not processed
            nonce_key.store(Concat(Itob(source_chain_id.get()), Itob(nonce.get()))),
            Assert(Not(self.processed_nonces[nonce_key.load()].exists())),
            # Verify Ed25519 signature (native Algorand opcode)
            Assert(
                Ed25519Verify_Bare(
                    Concat(
                        Bytes("LUX_BRIDGE_MINT"),
                        Itob(source_chain_id.get()),
                        Itob(nonce.get()),
                        recipient.get(),
                        Itob(amount.get()),
                    ),
                    signature.get(),
                    signer_pubkey.get(),
                )
            ),
            # Mark nonce processed
            self.processed_nonces[nonce_key.load()].set(Int(1)),
            # Transfer ALGO to recipient via inner transaction
            InnerTxnBuilder.Execute({
                TxnField.type_enum: TxnType.Payment,
                TxnField.receiver: recipient.get(),
                TxnField.amount: amount.get(),
                TxnField.fee: Int(0),
            }),
            Log(Concat(Bytes("MINT:"), Itob(source_chain_id.get()), Itob(nonce.get()))),
        )

    @external
    def burn_bridged(
        self,
        amount: abi.Uint64,
        dest_chain_id: abi.Uint64,
        recipient: abi.DynamicBytes,
        *,
        output: abi.Uint64,
    ):
        """Burn wrapped tokens for withdrawal."""
        nonce = ScratchVar(TealType.uint64)
        return Seq(
            Assert(self.paused.get() == Int(0)),
            Assert(amount.get() > Int(0)),
            self.total_burned.set(self.total_burned.get() + amount.get()),
            self.outbound_nonce.set(self.outbound_nonce.get() + Int(1)),
            nonce.store(self.outbound_nonce.get()),
            Log(Concat(
                Bytes("BURN:"),
                Itob(ALGORAND_CHAIN_ID),
                Itob(dest_chain_id.get()),
                Itob(nonce.load()),
                Txn.sender(),
                recipient.get(),
                Itob(amount.get()),
            )),
            output.set(nonce.load()),
        )

    # Admin
    @external
    def pause(self):
        return Seq(Assert(Txn.sender() == self.admin.get()), self.paused.set(Int(1)))

    @external
    def unpause(self):
        return Seq(Assert(Txn.sender() == self.admin.get()), self.paused.set(Int(0)))

    @external
    def set_fee(self, fee_bps: abi.Uint16):
        return Seq(
            Assert(Txn.sender() == self.admin.get()),
            Assert(fee_bps.get() <= MAX_FEE_BPS),
            self.fee_bps.set(fee_bps.get()),
        )

    # Views
    @external(read_only=True)
    def get_total_locked(self, *, output: abi.Uint64):
        return output.set(self.total_locked.get())

    @external(read_only=True)
    def get_total_burned(self, *, output: abi.Uint64):
        return output.set(self.total_burned.get())

    @external(read_only=True)
    def get_paused(self, *, output: abi.Uint64):
        return output.set(self.paused.get())


if __name__ == "__main__":
    LuxBridge().build().export("./artifacts")
