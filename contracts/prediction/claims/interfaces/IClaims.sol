// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title IClaims
/// @author Gnosis (original), Lux Industries (0.8.31 port)
/// @notice Interface for Claims contract - ERC-1155 conditional tokens
/// @dev Used for prediction markets, outcome tokens, and conditional outcomes
interface IClaims is IERC1155 {
    // ============ Events ============

    /// @dev Emitted upon the successful preparation of a condition.
    /// @param conditionId The condition's ID. Derived via keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount)).
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots for this condition. Must not exceed 256.
    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount
    );

    /// @dev Emitted when a condition is resolved by the oracle.
    /// @param conditionId The condition's ID.
    /// @param oracle The oracle that resolved the condition.
    /// @param questionId The question ID.
    /// @param outcomeSlotCount The number of outcome slots.
    /// @param payoutNumerators The payout numerators for each outcome.
    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    /// @dev Emitted when a position is successfully split.
    /// @param stakeholder The account that split the position.
    /// @param collateralToken The collateral token address.
    /// @param parentCollectionId The parent collection ID (bytes32(0) if root).
    /// @param conditionId The condition ID.
    /// @param partition The partition of index sets.
    /// @param amount The amount split.
    event PositionSplit(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    /// @dev Emitted when positions are successfully merged.
    /// @param stakeholder The account that merged the positions.
    /// @param collateralToken The collateral token address.
    /// @param parentCollectionId The parent collection ID (bytes32(0) if root).
    /// @param conditionId The condition ID.
    /// @param partition The partition of index sets.
    /// @param amount The amount merged.
    event PositionsMerge(
        address indexed stakeholder,
        IERC20 collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 indexed conditionId,
        uint256[] partition,
        uint256 amount
    );

    /// @dev Emitted when a payout is redeemed.
    /// @param redeemer The account redeeming the payout.
    /// @param collateralToken The collateral token address.
    /// @param parentCollectionId The parent collection ID.
    /// @param conditionId The condition ID.
    /// @param indexSets The index sets redeemed.
    /// @param payout The total payout amount.
    event PayoutRedemption(
        address indexed redeemer,
        IERC20 indexed collateralToken,
        bytes32 indexed parentCollectionId,
        bytes32 conditionId,
        uint256[] indexSets,
        uint256 payout
    );

    // ============ Errors ============

    /// @dev Thrown when outcome slot count exceeds 256
    error TooManyOutcomeSlots();

    /// @dev Thrown when outcome slot count is less than 2
    error TooFewOutcomeSlots();

    /// @dev Thrown when condition has already been prepared
    error ConditionAlreadyPrepared();

    /// @dev Thrown when condition has not been prepared
    error ConditionNotPrepared();

    /// @dev Thrown when condition has already been resolved
    error ConditionAlreadyResolved();

    /// @dev Thrown when condition has not been resolved yet
    error ConditionNotResolved();

    /// @dev Thrown when payout is all zeros
    error PayoutAllZeroes();

    /// @dev Thrown when partition is empty or singleton
    error InvalidPartition();

    /// @dev Thrown when index set is invalid
    error InvalidIndexSet();

    /// @dev Thrown when partition is not disjoint
    error PartitionNotDisjoint();

    /// @dev Thrown when collateral transfer fails
    error CollateralTransferFailed();

    /// @dev Thrown when payout numerator already set
    error PayoutNumeratorAlreadySet();

    /// @dev Thrown when parent collection ID is invalid
    error InvalidParentCollectionId();

    // ============ Core Functions ============

    /// @notice Prepares a condition by initializing a payout vector.
    /// @param oracle The account assigned to report the result.
    /// @param questionId An identifier for the question.
    /// @param outcomeSlotCount The number of outcome slots (2-256).
    function prepareCondition(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external;

    /// @notice Called by the oracle to report results of conditions.
    /// @param questionId The question ID the oracle is answering.
    /// @param payouts The oracle's answer (payout numerators).
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external;

    /// @notice Splits a position into multiple conditional positions.
    /// @param collateralToken The collateral token address.
    /// @param parentCollectionId The parent collection ID (bytes32(0) for root).
    /// @param conditionId The condition ID to split on.
    /// @param partition An array of disjoint index sets.
    /// @param amount The amount of collateral or stake to split.
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /// @notice Merges multiple conditional positions back into one.
    /// @param collateralToken The collateral token address.
    /// @param parentCollectionId The parent collection ID (bytes32(0) for root).
    /// @param conditionId The condition ID.
    /// @param partition An array of disjoint index sets.
    /// @param amount The amount to merge.
    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    /// @notice Redeems positions for collateral after condition resolution.
    /// @param collateralToken The collateral token address.
    /// @param parentCollectionId The parent collection ID.
    /// @param conditionId The condition ID.
    /// @param indexSets The index sets to redeem.
    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    // ============ View Functions ============

    /// @notice Gets the outcome slot count for a condition.
    /// @param conditionId The condition ID.
    /// @return The number of outcome slots, or 0 if not prepared.
    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256);

    /// @notice Gets the payout numerator for a specific outcome.
    /// @param conditionId The condition ID.
    /// @param index The outcome index.
    /// @return The payout numerator.
    function payoutNumerators(bytes32 conditionId, uint256 index) external view returns (uint256);

    /// @notice Gets the payout denominator for a condition.
    /// @param conditionId The condition ID.
    /// @return The payout denominator (sum of all numerators).
    function payoutDenominator(bytes32 conditionId) external view returns (uint256);

    // ============ Helper Functions ============

    /// @notice Constructs a condition ID from oracle, questionId, and outcomeSlotCount.
    /// @param oracle The oracle address.
    /// @param questionId The question ID.
    /// @param outcomeSlotCount The number of outcome slots.
    /// @return The condition ID.
    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external pure returns (bytes32);

    /// @notice Constructs an outcome collection ID.
    /// @param parentCollectionId The parent collection ID (bytes32(0) for root).
    /// @param conditionId The condition ID.
    /// @param indexSet The index set.
    /// @return The collection ID.
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external view returns (bytes32);

    /// @notice Constructs a position ID (ERC-1155 token ID).
    /// @param collateralToken The collateral token.
    /// @param collectionId The collection ID.
    /// @return The position ID.
    function getPositionId(
        IERC20 collateralToken,
        bytes32 collectionId
    ) external pure returns (uint256);
}
