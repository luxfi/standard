// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBridge
 * @author Lux Industries
 * @notice Interface for the Bridge cross-chain Claims position bridge
 */
interface IBridge {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum BridgeStatus {
        Unknown,
        Locked,
        Bridged,
        Redeemed,
        Cancelled
    }

    struct LockedPosition {
        bytes32 lockId;
        bytes32 sourceChainId;
        bytes32 destChainId;
        address owner;
        address ctf;
        bytes32 conditionId;
        uint256[] positionIds;
        uint256[] amounts;
        uint256 lockedAt;
        uint256 bridgedAt;
        BridgeStatus status;
    }

    struct WrappedMeta {
        bytes32 sourceChainId;
        address sourceCTF;
        bytes32 conditionId;
        uint256 sourcePositionId;
        bool resolved;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PositionsLocked(
        bytes32 indexed lockId,
        address indexed owner,
        bytes32 indexed destChainId,
        uint256[] positionIds,
        uint256[] amounts
    );

    event PositionsBridged(
        bytes32 indexed lockId,
        bytes32 indexed sourceChainId,
        address indexed recipient,
        uint256[] wrappedIds,
        uint256[] amounts
    );

    event PositionsUnlocked(
        bytes32 indexed lockId,
        address indexed owner,
        uint256[] positionIds,
        uint256[] amounts
    );

    event WrappedBurned(
        bytes32 indexed lockId,
        address indexed owner,
        uint256[] wrappedIds,
        uint256[] amounts
    );

    // ═══════════════════════════════════════════════════════════════════════
    // FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Lock CTF positions for bridging to another chain
     */
    function lockAndBridge(
        bytes32 destChainId,
        bytes32 conditionId,
        uint256[] calldata positionIds,
        uint256[] calldata amounts,
        address recipient
    ) external returns (bytes32 lockId, bytes32 messageId);

    /**
     * @notice Receive and process Warp message from source chain
     */
    function receiveWarpMessage(uint32 messageIndex) external;

    /**
     * @notice Burn wrapped positions and request unlock on source chain
     */
    function burnAndUnlock(
        bytes32 lockId,
        uint256[] calldata wrappedIds,
        uint256[] calldata amounts
    ) external returns (bytes32 messageId);

    /**
     * @notice Redeem resolved positions directly on source chain
     */
    function redeemResolved(
        bytes32 lockId,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        uint256[] calldata indexSets
    ) external;

    /**
     * @notice Cancel a bridge operation and unlock positions
     */
    function cancelBridge(bytes32 lockId) external;

    /**
     * @notice Get locked position data
     */
    function getLockedPosition(bytes32 lockId) external view returns (LockedPosition memory);

    /**
     * @notice Get user's lock IDs
     */
    function getUserLocks(address user) external view returns (bytes32[] memory);

    /**
     * @notice Get wrapped position metadata
     */
    function getWrappedMeta(uint256 wrappedId) external view returns (WrappedMeta memory);

    /**
     * @notice Calculate wrapped position ID
     */
    function getWrappedPositionId(
        bytes32 sourceChainId,
        address sourceCTF,
        uint256 sourcePositionId
    ) external pure returns (uint256);
}
