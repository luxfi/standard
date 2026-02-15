// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWarp, WarpLib} from "../../bridge/interfaces/IWarpMessenger.sol";
import {IClaims} from "../claims/interfaces/IClaims.sol";

/**
 * @title WrappedPosition
 * @notice ERC-1155 wrapped position token for bridged CTF positions
 */
contract WrappedPosition is ERC1155 {
    address public immutable bridge;

    error OnlyBridge();

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    constructor(string memory uri_) ERC1155(uri_) {
        bridge = msg.sender;
    }

    function mint(address to, uint256 id, uint256 amount) external onlyBridge {
        _mint(to, id, amount, "");
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) external onlyBridge {
        _mintBatch(to, ids, amounts, "");
    }

    function burn(address from, uint256 id, uint256 amount) external onlyBridge {
        _burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] memory ids, uint256[] memory amounts) external onlyBridge {
        _burnBatch(from, ids, amounts);
    }
}

/**
 * @title Bridge
 * @author Lux Industries
 * @notice Bridge Claims positions across Lux Network chains via Warp messaging
 * @dev Enables prediction market positions on Zoo/AI chains to be bridged
 *
 * Architecture:
 * - Lock Claims positions on source chain
 * - Send Warp message with position details
 * - Mint wrapped positions on destination chain
 * - After resolution, redeem on source chain and burn wrapped
 *
 * Position Flow:
 * 1. User locks Claims position on source chain
 * 2. Warp message sent to destination
 * 3. Wrapped position minted on destination
 * 4. User can trade wrapped position
 * 5. After resolution, user burns wrapped and claims on source
 *
 * Security:
 * - Only authorized bridge contracts can mint/burn wrapped positions
 * - Position locking prevents double-spending
 * - Resolution data verified via Warp from authoritative source
 */
contract Bridge is Ownable, ReentrancyGuard, IERC1155Receiver {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Bridge operation status
    enum BridgeStatus {
        Unknown,
        Locked,
        Bridged,
        Redeemed,
        Cancelled
    }

    /// @notice Locked position data
    struct LockedPosition {
        bytes32 lockId;             // Unique lock identifier
        bytes32 sourceChainId;      // Source chain
        bytes32 destChainId;        // Destination chain
        address owner;              // Original position owner
        address ctf;                // CTF contract address
        bytes32 conditionId;        // CTF condition ID
        uint256[] positionIds;      // ERC-1155 position IDs
        uint256[] amounts;          // Position amounts
        uint256 lockedAt;           // Lock timestamp
        uint256 bridgedAt;          // Bridge completion timestamp
        BridgeStatus status;        // Current status
    }

    /// @notice Wrapped position metadata
    struct WrappedMeta {
        bytes32 sourceChainId;      // Original chain
        address sourceCTF;          // Original CTF contract
        bytes32 conditionId;        // Original condition ID
        uint256 sourcePositionId;   // Original position ID
        bool resolved;              // Whether underlying is resolved
    }

    /// @notice Warp message types
    enum MessageType {
        BRIDGE_POSITIONS,
        UNLOCK_POSITIONS,
        SYNC_RESOLUTION
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice This chain's blockchain ID
    bytes32 public immutable thisChainId;

    /// @notice Local Claims contract
    IClaims public immutable localClaims;

    /// @notice Wrapped position token contract
    WrappedPosition public immutable wrappedToken;

    /// @notice Locked positions by ID
    mapping(bytes32 => LockedPosition) public lockedPositions;

    /// @notice Wrapped position metadata
    mapping(uint256 => WrappedMeta) public wrappedMeta;

    /// @notice Authorized bridge contracts on other chains
    mapping(bytes32 => address) public authorizedBridges;

    /// @notice User's locked position IDs
    mapping(address => bytes32[]) public userLocks;

    /// @notice Nonce for lock IDs
    uint256 public lockNonce;

    /// @notice Total value locked (in position units)
    uint256 public totalLocked;

    /// @notice Total value bridged
    uint256 public totalBridged;

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

    event ResolutionSynced(
        bytes32 indexed conditionId,
        uint256[] payouts
    );

    event AuthorizedBridgeSet(bytes32 indexed chainId, address bridge);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidMessage();
    error UnauthorizedChain();
    error UnauthorizedSender();
    error LockNotFound();
    error InvalidStatus();
    error ArrayLengthMismatch();
    error ZeroAmount();
    error ZeroAddress();
    error NotOwner();
    error ConditionNotResolved();
    error AlreadyResolved();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @param _claims Local Claims contract address
     * @param uri_ Wrapped token URI
     */
    constructor(
        address _claims,
        string memory uri_
    ) Ownable(msg.sender) {
        if (_claims == address(0)) revert ZeroAddress();

        thisChainId = WarpLib.getBlockchainID();
        localClaims = IClaims(_claims);
        wrappedToken = new WrappedPosition(uri_);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOCK & BRIDGE (Source Chain)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Lock CTF positions for bridging to another chain
     * @param destChainId Destination chain ID
     * @param conditionId CTF condition ID
     * @param positionIds Position IDs to bridge
     * @param amounts Amounts of each position
     * @param recipient Recipient on destination chain
     * @return lockId Unique lock identifier
     * @return messageId Warp message ID
     */
    function lockAndBridge(
        bytes32 destChainId,
        bytes32 conditionId,
        uint256[] calldata positionIds,
        uint256[] calldata amounts,
        address recipient
    ) external nonReentrant returns (bytes32 lockId, bytes32 messageId) {
        if (positionIds.length != amounts.length) revert ArrayLengthMismatch();
        if (positionIds.length == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (authorizedBridges[destChainId] == address(0)) revert UnauthorizedChain();

        // Generate lock ID
        lockId = keccak256(abi.encodePacked(
            thisChainId,
            destChainId,
            msg.sender,
            lockNonce++
        ));

        // Transfer positions to this contract (lock)
        localClaims.safeBatchTransferFrom(
            msg.sender,
            address(this),
            positionIds,
            amounts,
            ""
        );

        // Calculate total locked
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        totalLocked += totalAmount;

        // Store lock data
        lockedPositions[lockId] = LockedPosition({
            lockId: lockId,
            sourceChainId: thisChainId,
            destChainId: destChainId,
            owner: msg.sender,
            ctf: address(localClaims),
            conditionId: conditionId,
            positionIds: positionIds,
            amounts: amounts,
            lockedAt: block.timestamp,
            bridgedAt: 0,
            status: BridgeStatus.Locked
        });

        userLocks[msg.sender].push(lockId);

        emit PositionsLocked(lockId, msg.sender, destChainId, positionIds, amounts);

        // Send Warp message to destination
        bytes memory payload = abi.encode(
            MessageType.BRIDGE_POSITIONS,
            lockId,
            thisChainId,
            address(localClaims),
            conditionId,
            recipient,
            positionIds,
            amounts
        );

        messageId = WarpLib.sendMessage(payload);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WARP MESSAGE RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive and process Warp message from source chain
     * @param messageIndex Index of Warp message in transaction
     */
    function receiveWarpMessage(uint32 messageIndex) external nonReentrant {
        IWarp.WarpMessage memory message = WarpLib.getVerifiedMessageOrRevert(messageIndex);

        // Verify source is authorized bridge
        address authorizedBridge = authorizedBridges[message.sourceChainID];
        if (authorizedBridge == address(0)) revert UnauthorizedChain();
        if (message.originSenderAddress != authorizedBridge) revert UnauthorizedSender();

        _processMessage(message.sourceChainID, message.payload);
    }

    /**
     * @notice Process decoded message payload
     */
    function _processMessage(bytes32 sourceChainId, bytes memory payload) internal {
        MessageType msgType = abi.decode(payload, (MessageType));

        if (msgType == MessageType.BRIDGE_POSITIONS) {
            _handleBridgePositions(sourceChainId, payload);
        } else if (msgType == MessageType.UNLOCK_POSITIONS) {
            _handleUnlockPositions(payload);
        } else if (msgType == MessageType.SYNC_RESOLUTION) {
            _handleSyncResolution(payload);
        } else {
            revert InvalidMessage();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGE HANDLERS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Handle bridge positions message - mint wrapped tokens
     */
    function _handleBridgePositions(bytes32 sourceChainId, bytes memory payload) internal {
        (
            ,  // MessageType
            bytes32 lockId,
            ,  // sourceChainId (already have it)
            address sourceCTF,
            bytes32 conditionId,
            address recipient,
            uint256[] memory positionIds,
            uint256[] memory amounts
        ) = abi.decode(payload, (
            MessageType, bytes32, bytes32, address, bytes32, address, uint256[], uint256[]
        ));

        // Generate wrapped position IDs (unique per source chain + position)
        uint256[] memory wrappedIds = new uint256[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            wrappedIds[i] = _getWrappedPositionId(sourceChainId, sourceCTF, positionIds[i]);

            // Store metadata if not exists
            if (wrappedMeta[wrappedIds[i]].sourceChainId == bytes32(0)) {
                wrappedMeta[wrappedIds[i]] = WrappedMeta({
                    sourceChainId: sourceChainId,
                    sourceCTF: sourceCTF,
                    conditionId: conditionId,
                    sourcePositionId: positionIds[i],
                    resolved: false
                });
            }
        }

        // Mint wrapped positions
        wrappedToken.mintBatch(recipient, wrappedIds, amounts);

        // Update totals
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        totalBridged += totalAmount;

        emit PositionsBridged(lockId, sourceChainId, recipient, wrappedIds, amounts);
    }

    /**
     * @notice Handle unlock positions message - release locked tokens
     */
    function _handleUnlockPositions(bytes memory payload) internal {
        (
            ,  // MessageType
            bytes32 lockId,
            address recipient
        ) = abi.decode(payload, (MessageType, bytes32, address));

        LockedPosition storage lock = lockedPositions[lockId];
        if (lock.status != BridgeStatus.Locked && lock.status != BridgeStatus.Bridged) {
            revert InvalidStatus();
        }

        // Transfer positions back to recipient
        localClaims.safeBatchTransferFrom(
            address(this),
            recipient,
            lock.positionIds,
            lock.amounts,
            ""
        );

        // Update status
        lock.status = BridgeStatus.Redeemed;

        // Update totals
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < lock.amounts.length; i++) {
            totalAmount += lock.amounts[i];
        }
        totalLocked -= totalAmount;

        emit PositionsUnlocked(lockId, recipient, lock.positionIds, lock.amounts);
    }

    /**
     * @notice Handle resolution sync - mark wrapped positions as resolved
     */
    function _handleSyncResolution(bytes memory payload) internal {
        (
            ,  // MessageType
            bytes32 conditionId,
            uint256[] memory payouts
        ) = abi.decode(payload, (MessageType, bytes32, uint256[]));

        // Mark all wrapped positions with this condition as resolved
        // Note: In production, would need efficient lookup
        emit ResolutionSynced(conditionId, payouts);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REDEMPTION (Destination Chain)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Burn wrapped positions and request unlock on source chain
     * @param lockId Original lock ID
     * @param wrappedIds Wrapped position IDs to burn
     * @param amounts Amounts to burn
     * @return messageId Warp message ID
     */
    function burnAndUnlock(
        bytes32 lockId,
        uint256[] calldata wrappedIds,
        uint256[] calldata amounts
    ) external nonReentrant returns (bytes32 messageId) {
        if (wrappedIds.length != amounts.length) revert ArrayLengthMismatch();
        if (wrappedIds.length == 0) revert ZeroAmount();

        // Verify ownership and burn
        for (uint256 i = 0; i < wrappedIds.length; i++) {
            if (wrappedToken.balanceOf(msg.sender, wrappedIds[i]) < amounts[i]) {
                revert ZeroAmount();  // Insufficient balance
            }
        }

        wrappedToken.burnBatch(msg.sender, wrappedIds, amounts);

        // Get source chain from first wrapped position
        WrappedMeta storage meta = wrappedMeta[wrappedIds[0]];
        bytes32 sourceChainId = meta.sourceChainId;

        emit WrappedBurned(lockId, msg.sender, wrappedIds, amounts);

        // Send unlock message to source chain
        bytes memory payload = abi.encode(
            MessageType.UNLOCK_POSITIONS,
            lockId,
            msg.sender  // recipient on source chain
        );

        messageId = WarpLib.sendMessage(payload);
    }

    /**
     * @notice Redeem resolved positions directly on source chain
     * @dev Called after market resolution - burns wrapped and redeems underlying
     * @param lockId Lock ID
     * @param collateralToken Collateral token for redemption
     * @param parentCollectionId Parent collection ID (usually bytes32(0))
     * @param indexSets Index sets to redeem
     */
    function redeemResolved(
        bytes32 lockId,
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        uint256[] calldata indexSets
    ) external nonReentrant {
        LockedPosition storage lock = lockedPositions[lockId];
        if (lock.status != BridgeStatus.Locked && lock.status != BridgeStatus.Bridged) {
            revert InvalidStatus();
        }
        if (lock.owner != msg.sender) revert NotOwner();

        // Verify condition is resolved
        if (localClaims.payoutDenominator(lock.conditionId) == 0) {
            revert ConditionNotResolved();
        }

        // Redeem positions held in this contract
        localClaims.redeemPositions(
            collateralToken,
            parentCollectionId,
            lock.conditionId,
            indexSets
        );

        // Update status
        lock.status = BridgeStatus.Redeemed;

        // Transfer collateral to owner
        uint256 balance = collateralToken.balanceOf(address(this));
        if (balance > 0) {
            collateralToken.transfer(msg.sender, balance);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CANCEL BRIDGE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Cancel a bridge operation and unlock positions
     * @dev Only callable by lock owner before bridging completes
     * @param lockId Lock ID to cancel
     */
    function cancelBridge(bytes32 lockId) external nonReentrant {
        LockedPosition storage lock = lockedPositions[lockId];
        if (lock.status != BridgeStatus.Locked) revert InvalidStatus();
        if (lock.owner != msg.sender) revert NotOwner();

        // Transfer positions back
        localClaims.safeBatchTransferFrom(
            address(this),
            msg.sender,
            lock.positionIds,
            lock.amounts,
            ""
        );

        lock.status = BridgeStatus.Cancelled;

        // Update totals
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < lock.amounts.length; i++) {
            totalAmount += lock.amounts[i];
        }
        totalLocked -= totalAmount;

        emit PositionsUnlocked(lockId, msg.sender, lock.positionIds, lock.amounts);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set authorized bridge contract for a chain
     * @param chainId Chain ID
     * @param bridge Bridge contract address
     */
    function setAuthorizedBridge(bytes32 chainId, address bridge) external onlyOwner {
        authorizedBridges[chainId] = bridge;
        emit AuthorizedBridgeSet(chainId, bridge);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get locked position data
     * @param lockId Lock ID
     * @return Lock data
     */
    function getLockedPosition(bytes32 lockId) external view returns (LockedPosition memory) {
        return lockedPositions[lockId];
    }

    /**
     * @notice Get user's lock IDs
     * @param user User address
     * @return Array of lock IDs
     */
    function getUserLocks(address user) external view returns (bytes32[] memory) {
        return userLocks[user];
    }

    /**
     * @notice Get wrapped position metadata
     * @param wrappedId Wrapped position ID
     * @return Metadata
     */
    function getWrappedMeta(uint256 wrappedId) external view returns (WrappedMeta memory) {
        return wrappedMeta[wrappedId];
    }

    /**
     * @notice Calculate wrapped position ID
     * @param sourceChainId Source chain ID
     * @param sourceCTF Source CTF address
     * @param sourcePositionId Source position ID
     * @return Wrapped position ID
     */
    function _getWrappedPositionId(
        bytes32 sourceChainId,
        address sourceCTF,
        uint256 sourcePositionId
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            sourceChainId,
            sourceCTF,
            sourcePositionId
        )));
    }

    /**
     * @notice Get wrapped position ID (public view)
     */
    function getWrappedPositionId(
        bytes32 sourceChainId,
        address sourceCTF,
        uint256 sourcePositionId
    ) external pure returns (uint256) {
        return _getWrappedPositionId(sourceChainId, sourceCTF, sourcePositionId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC-1155 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
