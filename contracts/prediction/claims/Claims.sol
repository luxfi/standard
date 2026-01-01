// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Helpers} from "./Helpers.sol";
import {IClaims} from "./interfaces/IClaims.sol";

/// @title Claims
/// @author Gnosis (original Solidity 0.5.x), Lux Industries (0.8.31 port)
/// @notice ERC-1155 conditional tokens for prediction markets and outcome-based positions
/// @dev Core claims contract - enables splitting, merging, and redemption of conditional positions
///
/// Key concepts:
/// - Condition: A question with multiple outcomes, identified by (oracle, questionId, outcomeSlotCount)
/// - Collection: A set of outcomes, used to create hierarchical conditions
/// - Position: An ERC-1155 token representing a stake in a collection backed by collateral
/// - Split: Convert collateral or parent position into conditional outcome positions
/// - Merge: Reverse of split - combine conditional positions back into collateral or parent
/// - Redeem: After resolution, claim collateral proportional to payout for winning outcomes
contract Claims is ERC1155, IClaims {
    using SafeERC20 for IERC20;

    // ============ Storage ============

    /// @notice Payout numerators for each outcome of a condition
    /// @dev Length == outcomeSlotCount when prepared, empty when not prepared
    mapping(bytes32 conditionId => uint256[] numerators) private _payoutNumerators;

    /// @notice Payout denominator (sum of all numerators) for a resolved condition
    /// @dev Non-zero indicates condition has been resolved
    mapping(bytes32 conditionId => uint256 denominator) private _payoutDenominator;

    // ============ Constructor ============

    /// @notice Creates the Claims contract
    /// @dev URI can be empty as positions derive their metadata from condition/collection
    constructor() ERC1155("") {}

    // ============ External Functions ============

    /// @inheritdoc IClaims
    function prepareCondition(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external override {
        // Validate outcome count (2-256 outcomes supported)
        if (outcomeSlotCount > 256) revert TooManyOutcomeSlots();
        if (outcomeSlotCount <= 1) revert TooFewOutcomeSlots();

        bytes32 conditionId = Helpers.getConditionId(oracle, questionId, outcomeSlotCount);

        // Prevent re-preparation
        if (_payoutNumerators[conditionId].length != 0) revert ConditionAlreadyPrepared();

        // Initialize payout vector with zeros
        _payoutNumerators[conditionId] = new uint256[](outcomeSlotCount);

        emit ConditionPreparation(conditionId, oracle, questionId, outcomeSlotCount);
    }

    /// @inheritdoc IClaims
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external override {
        uint256 outcomeSlotCount = payouts.length;
        if (outcomeSlotCount <= 1) revert TooFewOutcomeSlots();

        // Oracle is msg.sender - enforced by inclusion in condition ID
        bytes32 conditionId = Helpers.getConditionId(msg.sender, questionId, outcomeSlotCount);

        // Verify condition exists
        if (_payoutNumerators[conditionId].length != outcomeSlotCount) revert ConditionNotPrepared();

        // Verify not already resolved
        if (_payoutDenominator[conditionId] != 0) revert ConditionAlreadyResolved();

        uint256 denominator = 0;
        uint256[] storage numerators = _payoutNumerators[conditionId];

        for (uint256 i = 0; i < outcomeSlotCount;) {
            uint256 num = payouts[i];

            // Native overflow check replaces SafeMath
            denominator += num;

            // Ensure numerator not already set (should be 0 from prepareCondition)
            if (numerators[i] != 0) revert PayoutNumeratorAlreadySet();
            numerators[i] = num;

            unchecked { ++i; }
        }

        // At least one outcome must have non-zero payout
        if (denominator == 0) revert PayoutAllZeroes();

        _payoutDenominator[conditionId] = denominator;

        emit ConditionResolution(conditionId, msg.sender, questionId, outcomeSlotCount, payouts);
    }

    /// @inheritdoc IClaims
    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external override {
        if (partition.length <= 1) revert InvalidPartition();

        uint256 outcomeSlotCount = _payoutNumerators[conditionId].length;
        if (outcomeSlotCount == 0) revert ConditionNotPrepared();

        // fullIndexSet is a bitmask with all outcome bits set
        // e.g., for 4 outcomes: 0b1111 = 15
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        uint256[] memory positionIds = new uint256[](partition.length);
        uint256[] memory amounts = new uint256[](partition.length);

        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            // Validate index set bounds
            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();

            // Ensure partition is disjoint (no overlapping outcomes)
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();
            freeIndexSet ^= indexSet;

            // Calculate position ID for this outcome collection
            positionIds[i] = Helpers.getPositionId(
                collateralToken,
                Helpers.getCollectionId(parentCollectionId, conditionId, indexSet)
            );
            amounts[i] = amount;

            unchecked { ++i; }
        }

        if (freeIndexSet == 0) {
            // Full partition - splitting from collateral or parent collection
            if (parentCollectionId == bytes32(0)) {
                // Splitting from collateral - transfer tokens in
                collateralToken.safeTransferFrom(msg.sender, address(this), amount);
            } else {
                // Splitting from parent position - burn parent tokens
                _burn(
                    msg.sender,
                    Helpers.getPositionId(collateralToken, parentCollectionId),
                    amount
                );
            }
        } else {
            // Partial partition - splitting from existing conditional position
            // e.g., splitting $:(A|C) into $:(A) and $:(C)
            _burn(
                msg.sender,
                Helpers.getPositionId(
                    collateralToken,
                    Helpers.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)
                ),
                amount
            );
        }

        // Mint new conditional position tokens
        _mintBatch(msg.sender, positionIds, amounts, "");

        emit PositionSplit(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /// @inheritdoc IClaims
    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external override {
        if (partition.length <= 1) revert InvalidPartition();

        uint256 outcomeSlotCount = _payoutNumerators[conditionId].length;
        if (outcomeSlotCount == 0) revert ConditionNotPrepared();

        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;
        uint256 freeIndexSet = fullIndexSet;

        uint256[] memory positionIds = new uint256[](partition.length);
        uint256[] memory amounts = new uint256[](partition.length);

        for (uint256 i = 0; i < partition.length;) {
            uint256 indexSet = partition[i];

            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();
            if ((indexSet & freeIndexSet) != indexSet) revert PartitionNotDisjoint();
            freeIndexSet ^= indexSet;

            positionIds[i] = Helpers.getPositionId(
                collateralToken,
                Helpers.getCollectionId(parentCollectionId, conditionId, indexSet)
            );
            amounts[i] = amount;

            unchecked { ++i; }
        }

        // Burn the conditional position tokens being merged
        _burnBatch(msg.sender, positionIds, amounts);

        if (freeIndexSet == 0) {
            // Full partition - merging back to collateral or parent collection
            if (parentCollectionId == bytes32(0)) {
                // Merging to collateral - transfer tokens out
                collateralToken.safeTransfer(msg.sender, amount);
            } else {
                // Merging to parent position - mint parent tokens
                _mint(
                    msg.sender,
                    Helpers.getPositionId(collateralToken, parentCollectionId),
                    amount,
                    ""
                );
            }
        } else {
            // Partial partition - merging back to conditional position
            _mint(
                msg.sender,
                Helpers.getPositionId(
                    collateralToken,
                    Helpers.getCollectionId(parentCollectionId, conditionId, fullIndexSet ^ freeIndexSet)
                ),
                amount,
                ""
            );
        }

        emit PositionsMerge(msg.sender, collateralToken, parentCollectionId, conditionId, partition, amount);
    }

    /// @inheritdoc IClaims
    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external override {
        uint256 denominator = _payoutDenominator[conditionId];
        if (denominator == 0) revert ConditionNotResolved();

        uint256 outcomeSlotCount = _payoutNumerators[conditionId].length;
        if (outcomeSlotCount == 0) revert ConditionNotPrepared();

        uint256 totalPayout = 0;
        uint256 fullIndexSet = (1 << outcomeSlotCount) - 1;

        for (uint256 i = 0; i < indexSets.length;) {
            uint256 indexSet = indexSets[i];
            if (indexSet == 0 || indexSet >= fullIndexSet) revert InvalidIndexSet();

            uint256 positionId = Helpers.getPositionId(
                collateralToken,
                Helpers.getCollectionId(parentCollectionId, conditionId, indexSet)
            );

            // Calculate payout numerator for this index set
            uint256 payoutNumerator = 0;
            for (uint256 j = 0; j < outcomeSlotCount;) {
                if (indexSet & (1 << j) != 0) {
                    payoutNumerator += _payoutNumerators[conditionId][j];
                }
                unchecked { ++j; }
            }

            // Get user's stake in this position
            uint256 payoutStake = balanceOf(msg.sender, positionId);
            if (payoutStake > 0) {
                // Calculate proportional payout
                totalPayout += (payoutStake * payoutNumerator) / denominator;
                _burn(msg.sender, positionId, payoutStake);
            }

            unchecked { ++i; }
        }

        // Transfer payout
        if (totalPayout > 0) {
            if (parentCollectionId == bytes32(0)) {
                // Payout in collateral
                collateralToken.safeTransfer(msg.sender, totalPayout);
            } else {
                // Payout in parent position tokens
                _mint(
                    msg.sender,
                    Helpers.getPositionId(collateralToken, parentCollectionId),
                    totalPayout,
                    ""
                );
            }
        }

        emit PayoutRedemption(msg.sender, collateralToken, parentCollectionId, conditionId, indexSets, totalPayout);
    }

    // ============ View Functions ============

    /// @inheritdoc IClaims
    function getOutcomeSlotCount(bytes32 conditionId) external view override returns (uint256) {
        return _payoutNumerators[conditionId].length;
    }

    /// @inheritdoc IClaims
    function payoutNumerators(bytes32 conditionId, uint256 index) external view override returns (uint256) {
        return _payoutNumerators[conditionId][index];
    }

    /// @inheritdoc IClaims
    function payoutDenominator(bytes32 conditionId) external view override returns (uint256) {
        return _payoutDenominator[conditionId];
    }

    /// @notice Gets the full payout numerators array for a condition
    /// @param conditionId The condition ID
    /// @return The full array of payout numerators
    function getPayoutNumerators(bytes32 conditionId) external view returns (uint256[] memory) {
        return _payoutNumerators[conditionId];
    }

    // ============ Pure/View Helper Functions ============

    /// @inheritdoc IClaims
    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) external pure override returns (bytes32) {
        return Helpers.getConditionId(oracle, questionId, outcomeSlotCount);
    }

    /// @inheritdoc IClaims
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external view override returns (bytes32) {
        return Helpers.getCollectionId(parentCollectionId, conditionId, indexSet);
    }

    /// @inheritdoc IClaims
    function getPositionId(
        IERC20 collateralToken,
        bytes32 collectionId
    ) external pure override returns (uint256) {
        return Helpers.getPositionId(collateralToken, collectionId);
    }

    // ============ ERC-1155 Overrides ============

    /// @notice Returns URI for token metadata
    /// @dev Returns empty string as CTF positions derive metadata from condition/collection
    function uri(uint256) public pure override returns (string memory) {
        return "";
    }
}
