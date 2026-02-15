// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWarp, WarpLib} from "../../bridge/interfaces/IWarpMessenger.sol";
import {IClaims} from "../claims/interfaces/IClaims.sol";

/**
 * @title IResolver
 * @notice Minimal interface for Resolver
 */
interface IResolver {
    function initialize(
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) external returns (bytes32 questionID);

    function resolve(bytes32 questionID) external;
    function ready(bytes32 questionID) external view returns (bool);
    function getExpectedPayouts(bytes32 questionID) external view returns (uint256[] memory);
}

/**
 * @title IHub
 * @notice Interface for Hub
 */
interface IHub {
    function recordResolution(bytes32 marketId, uint256[] calldata payouts) external;
}

/**
 * @title Relay
 * @author Lux Industries
 * @notice Relay assertions cross-chain for prediction market resolution
 * @dev Enables markets on Zoo/AI chains to be resolved via C-Chain Oracle infrastructure
 *
 * Architecture:
 * - Spoke chains send assertion requests via Warp
 * - This relay receives assertions and forwards to Oracle on C-Chain
 * - After oracle resolution, broadcasts results back to spoke chains
 *
 * Flow:
 * 1. Market created on spoke chain (Zoo/AI)
 * 2. Assertion request sent via Warp to C-Chain
 * 3. Relay receives and creates oracle request
 * 4. After liveness period, resolution is determined
 * 5. Resolution broadcast back to spoke chains via Warp
 */
contract Relay is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Assertion status
    enum AssertionStatus {
        Unknown,
        Pending,
        Disputed,
        Resolved,
        Rejected
    }

    /// @notice Cross-chain assertion data
    struct Assertion {
        bytes32 assertionId;        // Unique assertion ID
        bytes32 marketId;           // Associated market ID
        bytes32 sourceChainId;      // Chain where assertion originated
        address asserter;           // Original asserter address
        bytes32 questionId;         // CTF question ID
        uint256 outcomeSlotCount;   // Number of outcomes
        uint256 proposalBond;       // Bond amount
        uint256 liveness;           // Liveness period in seconds
        uint256 createdAt;          // Creation timestamp
        uint256 resolvedAt;         // Resolution timestamp
        AssertionStatus status;     // Current status
        uint256[] payouts;          // Resolution payouts
        bytes ancillaryData;        // Assertion data
    }

    /// @notice Warp message types
    enum MessageType {
        REQUEST_ASSERTION,
        DISPUTE_ASSERTION,
        RESOLUTION_RESULT
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice This chain's blockchain ID
    bytes32 public immutable thisChainId;

    /// @notice Resolver for CTF
    IResolver public immutable resolver;

    /// @notice Claims contract
    IClaims public immutable claims;

    /// @notice Hub for resolution recording
    IHub public marketHub;

    /// @notice Default reward token (USDC)
    address public defaultRewardToken;

    /// @notice Default reward amount
    uint256 public defaultReward;

    /// @notice Default proposal bond
    uint256 public defaultBond;

    /// @notice Default liveness period (2 hours)
    uint256 public defaultLiveness = 2 hours;

    /// @notice Assertions by ID
    mapping(bytes32 => Assertion) public assertions;

    /// @notice Mapping from oracle questionId to assertionId
    mapping(bytes32 => bytes32) public oracleToAssertion;

    /// @notice Authorized spoke chain hubs
    mapping(bytes32 => address) public authorizedHubs;

    /// @notice Nonce for assertion IDs
    uint256 public assertionNonce;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event AssertionReceived(
        bytes32 indexed assertionId,
        bytes32 indexed marketId,
        bytes32 indexed sourceChainId,
        address asserter,
        bytes32 questionId
    );

    event AssertionForwarded(
        bytes32 indexed assertionId,
        bytes32 indexed oracleQuestionId
    );

    event AssertionResolved(
        bytes32 indexed assertionId,
        bytes32 indexed marketId,
        uint256[] payouts
    );

    event ResolutionBroadcast(
        bytes32 indexed assertionId,
        bytes32 indexed targetChainId,
        bytes32 messageId
    );

    event AuthorizedHubSet(bytes32 indexed chainId, address hub);
    event MarketHubSet(address indexed marketHub);
    event DefaultsUpdated(address rewardToken, uint256 reward, uint256 bond, uint256 liveness);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidMessage();
    error UnauthorizedChain();
    error UnauthorizedSender();
    error AssertionNotFound();
    error AssertionAlreadyExists();
    error AssertionNotReady();
    error AssertionAlreadyResolved();
    error ZeroAddress();
    error InvalidPayouts();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @param _resolver Resolver address
     * @param _claims Claims contract address
     * @param _rewardToken Default reward token
     * @param _reward Default reward amount
     * @param _bond Default proposal bond
     */
    constructor(
        address _resolver,
        address _claims,
        address _rewardToken,
        uint256 _reward,
        uint256 _bond
    ) Ownable(msg.sender) {
        if (_resolver == address(0) || _claims == address(0)) revert ZeroAddress();

        thisChainId = WarpLib.getBlockchainID();
        resolver = IResolver(_resolver);
        claims = IClaims(_claims);
        defaultRewardToken = _rewardToken;
        defaultReward = _reward;
        defaultBond = _bond;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // WARP MESSAGE RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Receive and process a Warp message from spoke chain
     * @param messageIndex Index of the Warp message in the transaction
     */
    function receiveWarpMessage(uint32 messageIndex) external nonReentrant {
        IWarp.WarpMessage memory message = WarpLib.getVerifiedMessageOrRevert(messageIndex);

        // Verify source is authorized hub
        address authorizedHub = authorizedHubs[message.sourceChainID];
        if (authorizedHub == address(0)) revert UnauthorizedChain();
        if (message.originSenderAddress != authorizedHub) revert UnauthorizedSender();

        _processMessage(message.sourceChainID, message.payload);
    }

    /**
     * @notice Process decoded message payload
     */
    function _processMessage(bytes32 sourceChainId, bytes memory payload) internal {
        MessageType msgType = abi.decode(payload, (MessageType));

        if (msgType == MessageType.REQUEST_ASSERTION) {
            _handleAssertionRequest(sourceChainId, payload);
        } else if (msgType == MessageType.DISPUTE_ASSERTION) {
            _handleDisputeRequest(payload);
        } else {
            revert InvalidMessage();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MESSAGE HANDLERS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Handle assertion request from spoke chain
     */
    function _handleAssertionRequest(bytes32 sourceChainId, bytes memory payload) internal {
        (
            ,  // MessageType
            bytes32 marketId,
            address asserter,
            bytes32 questionId,
            uint256 outcomeSlotCount,
            uint256 proposalBond,
            uint256 liveness,
            bytes memory ancillaryData
        ) = abi.decode(payload, (
            MessageType, bytes32, address, bytes32, uint256, uint256, uint256, bytes
        ));

        // Generate unique assertion ID
        bytes32 assertionId = keccak256(abi.encodePacked(
            sourceChainId,
            marketId,
            assertionNonce++
        ));

        if (assertions[assertionId].status != AssertionStatus.Unknown) revert AssertionAlreadyExists();

        // Use defaults if not specified
        if (proposalBond == 0) proposalBond = defaultBond;
        if (liveness == 0) liveness = defaultLiveness;

        // Store assertion
        assertions[assertionId] = Assertion({
            assertionId: assertionId,
            marketId: marketId,
            sourceChainId: sourceChainId,
            asserter: asserter,
            questionId: questionId,
            outcomeSlotCount: outcomeSlotCount,
            proposalBond: proposalBond,
            liveness: liveness,
            createdAt: block.timestamp,
            resolvedAt: 0,
            status: AssertionStatus.Pending,
            payouts: new uint256[](0),
            ancillaryData: ancillaryData
        });

        emit AssertionReceived(assertionId, marketId, sourceChainId, asserter, questionId);

        // Forward to Oracle
        _forwardToOracle(assertionId);
    }

    /**
     * @notice Forward assertion to Resolver
     */
    function _forwardToOracle(bytes32 assertionId) internal {
        Assertion storage assertion = assertions[assertionId];

        // Approve reward token if needed
        if (defaultReward > 0) {
            IERC20(defaultRewardToken).approve(address(resolver), defaultReward);
        }

        // Initialize question on Oracle
        bytes32 oracleQuestionId = resolver.initialize(
            assertion.ancillaryData,
            defaultRewardToken,
            defaultReward,
            assertion.proposalBond,
            assertion.liveness
        );

        // Map oracle question to our assertion
        oracleToAssertion[oracleQuestionId] = assertionId;

        emit AssertionForwarded(assertionId, oracleQuestionId);
    }

    /**
     * @notice Handle dispute request (future implementation)
     */
    function _handleDisputeRequest(bytes memory payload) internal {
        // Future: Handle cross-chain disputes
        (payload);  // Suppress unused warning
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Resolve an assertion after liveness period
     * @param assertionId Assertion ID to resolve
     */
    function resolveAssertion(bytes32 assertionId) external nonReentrant {
        Assertion storage assertion = assertions[assertionId];
        if (assertion.status == AssertionStatus.Unknown) revert AssertionNotFound();
        if (assertion.status == AssertionStatus.Resolved) revert AssertionAlreadyResolved();

        // Find oracle question ID
        bytes32 oracleQuestionId = _findOracleQuestionId(assertionId);

        // Check if ready
        if (!resolver.ready(oracleQuestionId)) revert AssertionNotReady();

        // Resolve on Oracle
        resolver.resolve(oracleQuestionId);

        // Get payouts
        uint256[] memory payouts = resolver.getExpectedPayouts(oracleQuestionId);

        // Update assertion
        assertion.status = AssertionStatus.Resolved;
        assertion.resolvedAt = block.timestamp;
        assertion.payouts = payouts;

        emit AssertionResolved(assertionId, assertion.marketId, payouts);

        // Record on market hub
        if (address(marketHub) != address(0)) {
            marketHub.recordResolution(assertion.marketId, payouts);
        }
    }

    /**
     * @notice Broadcast resolution to spoke chain
     * @param assertionId Assertion ID
     * @return messageId Warp message ID
     */
    function broadcastResolution(bytes32 assertionId) external nonReentrant returns (bytes32 messageId) {
        Assertion storage assertion = assertions[assertionId];
        if (assertion.status != AssertionStatus.Resolved) revert AssertionNotFound();

        // Encode resolution message
        bytes memory payload = abi.encode(
            MessageType.RESOLUTION_RESULT,
            assertion.assertionId,
            assertion.marketId,
            assertion.questionId,
            assertion.payouts
        );

        // Send via Warp
        messageId = WarpLib.sendMessage(payload);

        emit ResolutionBroadcast(assertionId, assertion.sourceChainId, messageId);
    }

    /**
     * @notice Find oracle question ID for an assertion
     * @dev Reverse lookup through mapping
     */
    function _findOracleQuestionId(bytes32 assertionId) internal view returns (bytes32) {
        // In production, we'd store this bidirectionally
        // For now, compute from ancillary data
        Assertion storage assertion = assertions[assertionId];
        return keccak256(assertion.ancillaryData);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOCAL ASSERTION (for C-Chain native assertions)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create assertion locally on C-Chain
     * @param marketId Market ID
     * @param questionId CTF question ID
     * @param outcomeSlotCount Number of outcomes
     * @param proposalBond Bond amount
     * @param liveness Liveness period
     * @param ancillaryData Assertion data
     * @return assertionId New assertion ID
     */
    function createLocalAssertion(
        bytes32 marketId,
        bytes32 questionId,
        uint256 outcomeSlotCount,
        uint256 proposalBond,
        uint256 liveness,
        bytes calldata ancillaryData
    ) external nonReentrant returns (bytes32 assertionId) {
        assertionId = keccak256(abi.encodePacked(
            thisChainId,
            marketId,
            assertionNonce++
        ));

        if (proposalBond == 0) proposalBond = defaultBond;
        if (liveness == 0) liveness = defaultLiveness;

        assertions[assertionId] = Assertion({
            assertionId: assertionId,
            marketId: marketId,
            sourceChainId: thisChainId,
            asserter: msg.sender,
            questionId: questionId,
            outcomeSlotCount: outcomeSlotCount,
            proposalBond: proposalBond,
            liveness: liveness,
            createdAt: block.timestamp,
            resolvedAt: 0,
            status: AssertionStatus.Pending,
            payouts: new uint256[](0),
            ancillaryData: ancillaryData
        });

        emit AssertionReceived(assertionId, marketId, thisChainId, msg.sender, questionId);

        _forwardToOracle(assertionId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set authorized hub for a spoke chain
     * @param chainId Spoke chain ID
     * @param hub Hub contract address
     */
    function setAuthorizedHub(bytes32 chainId, address hub) external onlyOwner {
        authorizedHubs[chainId] = hub;
        emit AuthorizedHubSet(chainId, hub);
    }

    /**
     * @notice Set market hub address
     * @param _marketHub Market hub address
     */
    function setMarketHub(address _marketHub) external onlyOwner {
        if (_marketHub == address(0)) revert ZeroAddress();
        marketHub = IHub(_marketHub);
        emit MarketHubSet(_marketHub);
    }

    /**
     * @notice Update default parameters
     * @param rewardToken Reward token address
     * @param reward Reward amount
     * @param bond Proposal bond
     * @param liveness Liveness period
     */
    function setDefaults(
        address rewardToken,
        uint256 reward,
        uint256 bond,
        uint256 liveness
    ) external onlyOwner {
        defaultRewardToken = rewardToken;
        defaultReward = reward;
        defaultBond = bond;
        defaultLiveness = liveness;
        emit DefaultsUpdated(rewardToken, reward, bond, liveness);
    }

    /**
     * @notice Withdraw stuck tokens (emergency)
     * @param token Token address
     * @param to Recipient
     * @param amount Amount
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get assertion data
     * @param assertionId Assertion ID
     * @return Assertion data
     */
    function getAssertion(bytes32 assertionId) external view returns (Assertion memory) {
        return assertions[assertionId];
    }

    /**
     * @notice Check if assertion is resolved
     * @param assertionId Assertion ID
     * @return True if resolved
     */
    function isResolved(bytes32 assertionId) external view returns (bool) {
        return assertions[assertionId].status == AssertionStatus.Resolved;
    }

    /**
     * @notice Get assertion payouts
     * @param assertionId Assertion ID
     * @return Payout array
     */
    function getPayouts(bytes32 assertionId) external view returns (uint256[] memory) {
        return assertions[assertionId].payouts;
    }

    /**
     * @notice Check if assertion is ready for resolution
     * @param assertionId Assertion ID
     * @return True if ready
     */
    function isReady(bytes32 assertionId) external view returns (bool) {
        Assertion storage assertion = assertions[assertionId];
        if (assertion.status != AssertionStatus.Pending) return false;

        bytes32 oracleQuestionId = _findOracleQuestionId(assertionId);
        return resolver.ready(oracleQuestionId);
    }
}
