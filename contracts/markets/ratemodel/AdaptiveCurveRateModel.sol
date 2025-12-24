// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IRateModel} from "../interfaces/IRateModel.sol";
import {MarketParams, Market} from "../interfaces/IMarkets.sol";
import {MathLib} from "../libraries/MathLib.sol";

/// @title AdaptiveCurveRateModel
/// @notice Adaptive interest rate model with curved utilization response
/// @dev Based on Morpho's adaptive curve IRM
contract AdaptiveCurveRateModel is IRateModel {
    using MathLib for uint256;

    /* CONSTANTS */

    /// @notice Seconds per year
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Target utilization (90%)
    uint256 public constant TARGET_UTILIZATION = 0.9e18;

    /// @notice Speed of rate adjustment
    uint256 public constant ADJUSTMENT_SPEED = 50e18 / SECONDS_PER_YEAR; // 50x per year

    /// @notice Initial rate at target utilization (4% APR)
    uint256 public constant INITIAL_RATE_AT_TARGET = 0.04e18 / SECONDS_PER_YEAR;

    /// @notice Minimum rate (0.1% APR)
    uint256 public constant MIN_RATE = 0.001e18 / SECONDS_PER_YEAR;

    /// @notice Maximum rate (200% APR)
    uint256 public constant MAX_RATE = 2e18 / SECONDS_PER_YEAR;

    /// @notice Curve steepness
    uint256 public constant CURVE_STEEPNESS = 4e18;

    /* STORAGE */

    /// @notice Rate at target utilization per market
    mapping(bytes32 => uint256) public rateAtTarget;

    /// @notice Last update timestamp per market
    mapping(bytes32 => uint256) public lastUpdate;

    /* EVENTS */

    event RateUpdated(bytes32 indexed id, uint256 rateAtTarget, uint256 utilization);

    /* FUNCTIONS */

    /// @inheritdoc IRateModel
    function borrowRate(MarketParams memory marketParams, Market memory market) external override returns (uint256) {
        bytes32 id = keccak256(abi.encode(marketParams));

        uint256 utilization = _utilization(market);
        uint256 currentRateAtTarget = rateAtTarget[id];

        // Initialize if first call
        if (currentRateAtTarget == 0) {
            currentRateAtTarget = INITIAL_RATE_AT_TARGET;
            rateAtTarget[id] = currentRateAtTarget;
            lastUpdate[id] = block.timestamp;
            emit RateUpdated(id, currentRateAtTarget, utilization);
            return _curve(utilization, currentRateAtTarget);
        }

        // Adapt rate based on utilization deviation from target
        uint256 elapsed = block.timestamp - lastUpdate[id];
        if (elapsed > 0) {
            int256 deviation = int256(utilization) - int256(TARGET_UTILIZATION);
            int256 adjustment = (deviation * int256(ADJUSTMENT_SPEED) * int256(elapsed)) / 1e18;

            int256 newRate = int256(currentRateAtTarget) + adjustment;
            newRate = _bound(newRate, int256(MIN_RATE), int256(MAX_RATE));

            currentRateAtTarget = uint256(newRate);
            rateAtTarget[id] = currentRateAtTarget;
            lastUpdate[id] = block.timestamp;

            emit RateUpdated(id, currentRateAtTarget, utilization);
        }

        return _curve(utilization, currentRateAtTarget);
    }

    /// @inheritdoc IRateModel
    function borrowRateView(bytes32 id, uint256 utilization) external view override returns (uint256) {
        uint256 currentRateAtTarget = rateAtTarget[id];
        if (currentRateAtTarget == 0) {
            currentRateAtTarget = INITIAL_RATE_AT_TARGET;
        }
        return _curve(utilization, currentRateAtTarget);
    }

    /* INTERNAL */

    function _utilization(Market memory market) internal pure returns (uint256) {
        if (market.totalSupplyAssets == 0) return 0;
        return uint256(market.totalBorrowAssets).mulDivDown(1e18, uint256(market.totalSupplyAssets));
    }

    function _curve(uint256 utilization, uint256 rateAtTargetUtil) internal pure returns (uint256) {
        if (utilization <= TARGET_UTILIZATION) {
            // Below target: linear increase to rateAtTarget
            return rateAtTargetUtil.mulDivDown(utilization, TARGET_UTILIZATION);
        } else {
            // Above target: exponential increase
            uint256 excessUtilization = utilization - TARGET_UTILIZATION;
            uint256 remainingCapacity = 1e18 - TARGET_UTILIZATION;
            uint256 utilizationRatio = excessUtilization.mulDivUp(1e18, remainingCapacity);

            // rate = rateAtTarget * (1 + steepness * utilizationRatio^2)
            uint256 multiplier = 1e18 + CURVE_STEEPNESS.mulDivDown(utilizationRatio.mulDivDown(utilizationRatio, 1e18), 1e18);
            return rateAtTargetUtil.mulDivDown(multiplier, 1e18);
        }
    }

    function _bound(int256 value, int256 minVal, int256 maxVal) internal pure returns (int256) {
        if (value < minVal) return minVal;
        if (value > maxVal) return maxVal;
        return value;
    }
}
