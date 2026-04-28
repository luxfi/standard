// SPDX-License-Identifier: MIT
// OP_NET outbound: prove EVM (Lux/Zoo/any L1) can mint into OP_NET via burn-and-relay.
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OmnichainRouter } from "../../contracts/bridge/OmnichainRouter.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// Mirrors OmnichainRouterSecurity's MockBridgeToken (router gating).
contract MockBridgeToken is ERC20 {
    address public router;

    constructor(string memory name, string memory symbol, address _router) ERC20(name, symbol) {
        router = _router;
    }

    function setRouter(address _router) external {
        router = _router;
    }

    function bridgeMint(address to, uint256 amount) external {
        require(msg.sender == router, "Only router");
        _mint(to, amount);
    }

    function bridgeBurn(address from, uint256 amount) external {
        require(msg.sender == router, "Only router");
        _burn(from, amount);
    }
}

/// @title OPNETOutbound
/// @notice Verifies EVM → OP_NET teleport semantics on the source side.
///
/// Flow: a Lux or Zoo L1 user holds bridged BTC (e.g. LBTC). They burn it via
/// `OmnichainRouter.burnForWithdrawal(token, amount, OPNET_CHAIN_ID, taprootPubkey)`.
/// The router emits `Burned(...)` carrying the destination chain (4294967299
/// = OP_NET) and the recipient's Bitcoin Taproot x-only pubkey as bytes32.
///
/// The MPC oracle (FROST/Taproot threshold) observes this event off-chain,
/// constructs an OP_NET-conformant Bitcoin transaction (an OP-20 mint
/// inscription to `taprootPubkey`), signs it via FROST, and broadcasts. The
/// OP_NET indexer accepts the mint.
///
/// This test asserts the EVM-side primitive: burn emits the right event with
/// the right destination chain ID and the right recipient bytes.
contract OPNETOutbound is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    OmnichainRouter public router;
    MockBridgeToken public lbtc;

    uint256 internal mpcGroupKey = 0xBEEF;
    address internal mpcGroup;

    address internal governor = address(0xAAAA);
    address internal vault = address(0xBBBB);
    address internal treasury = address(0xCCCC);
    address internal user = address(0xDDDD);

    uint64 internal constant CHAIN_ID = 96369; // Lux C-Chain
    uint64 internal constant OPNET_CHAIN_ID = 4_294_967_299; // 0x100000003
    uint256 internal constant FEE_BPS = 50; // 0.5%

    /// Re-declare the event so we can `vm.expectEmit` against it.
    event Burned(
        uint64 indexed destChain,
        uint64 indexed nonce,
        address indexed token,
        address sender,
        bytes32 recipient,
        uint256 amount
    );

    function setUp() public {
        mpcGroup = vm.addr(mpcGroupKey);

        // Three individual signers required by the constructor; we don't use
        // single-signer paths in this test, so any addrs are fine.
        router = new OmnichainRouter(
            CHAIN_ID, governor, vault, treasury, FEE_BPS, 9000, vm.addr(0xA1), vm.addr(0xA2), vm.addr(0xA3), mpcGroup
        );

        lbtc = new MockBridgeToken("Liquid BTC", "LBTC", address(router));
        _registerToken(address(lbtc), 1_000_000 ether);
        _mintDeposit(uint64(OPNET_CHAIN_ID), 1, 1 ether);
    }

    // ── The actual OP_NET capability test ──────────────────────────────────

    /// @notice Burning bridged BTC for OP_NET emits the event the MPC oracle needs.
    ///         destChain = OPNET_CHAIN_ID (4294967299) and recipient is the
    ///         user's Bitcoin Taproot x-only pubkey.
    function test_OPNET_burnEmitsCorrectEvent() public {
        // Arbitrary 32-byte Taproot x-only pubkey.
        bytes32 taprootPubkey = 0x1d1c5f3a4d4a4c2a8c5b6e7f8090a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8;

        uint256 amount = 1 ether;
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 mintAmount = amount - fee;

        vm.startPrank(user);
        lbtc.approve(address(router), mintAmount);

        vm.expectEmit(true, true, true, true);
        emit Burned(OPNET_CHAIN_ID, 1, address(lbtc), user, taprootPubkey, mintAmount);

        router.burnForWithdrawal(address(lbtc), mintAmount, OPNET_CHAIN_ID, taprootPubkey);
        vm.stopPrank();

        assertEq(lbtc.balanceOf(user), 0, "user fully burned");
    }

    /// @notice Same primitive works for any L1 destination, parameterized by chainId.
    ///         Confirms OmnichainRouter is destChain-agnostic — Zoo, Lux, OP_NET, etc.
    function test_OPNET_anyDestinationChain(uint64 destChain) public {
        vm.assume(destChain != 0);
        bytes32 recipient = bytes32(uint256(uint160(user)));
        uint256 amount = 1 ether;
        uint256 mintAmount = amount - (amount * FEE_BPS) / 10000;

        vm.startPrank(user);
        lbtc.approve(address(router), mintAmount);

        vm.expectEmit(true, true, true, true);
        emit Burned(destChain, 1, address(lbtc), user, recipient, mintAmount);

        router.burnForWithdrawal(address(lbtc), mintAmount, destChain, recipient);
        vm.stopPrank();
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    function _signMpc(bytes32 digest) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(mpcGroupKey, digest.toEthSignedMessageHash());
        return abi.encodePacked(r, s, v);
    }

    function _registerToken(address t, uint256 limit) internal {
        bytes32 digest = keccak256(abi.encode("REGISTER", CHAIN_ID, t, limit));
        router.registerToken(t, limit, _signMpc(digest));
    }

    function _mintDeposit(uint64 sourceChain, uint64 nonce, uint256 amount) internal {
        bytes32 digest = keccak256(abi.encode("DEPOSIT", CHAIN_ID, sourceChain, nonce, address(lbtc), user, amount));
        router.mintDeposit(sourceChain, nonce, address(lbtc), user, amount, _signMpc(digest));
    }
}
