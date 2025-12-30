// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title CircuitBreaker
/// @notice Protection against extreme price volatility and oracle manipulation
/// @dev Integrated into Oracle.sol for automatic protection
contract CircuitBreaker is AccessControl {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Maximum allowed price change per update (basis points)
    /// @dev 1000 = 10%, 2000 = 20%
    uint256 public maxPriceChangeBps = 1000; // 10% default

    /// @notice Maximum allowed price change per hour (basis points)
    uint256 public maxHourlyChangeBps = 2500; // 25% default

    /// @notice Minimum time between price updates
    uint256 public minUpdateInterval = 1 minutes;

    /// @notice Cooldown after circuit breaker trips
    uint256 public cooldownPeriod = 5 minutes;

    /// @notice Global pause flag
    bool public paused;

    /// @notice Per-asset circuit breaker state
    struct AssetState {
        uint256 lastPrice;           // Last accepted price
        uint256 lastUpdateTime;      // Last update timestamp
        uint256 hourlyStartPrice;    // Price at start of current hour
        uint256 hourlyStartTime;     // Start of current hour tracking
        bool tripped;                // Circuit breaker tripped
        uint256 tripTime;            // When breaker tripped
    }
    mapping(address => AssetState) public assetState;

    /// @notice Per-asset custom limits (0 means use global)
    struct AssetLimits {
        uint256 maxPriceChangeBps;
        uint256 maxHourlyChangeBps;
        bool configured;
    }
    mapping(address => AssetLimits) public assetLimits;

    // =========================================================================
    // Errors
    // =========================================================================

    error BreakerTripped(address asset, uint256 priceChange);
    error HourlyLimitExceeded(address asset, uint256 hourlyChange);
    error UpdateTooFrequent(address asset, uint256 elapsed);
    error CooldownActive(address asset, uint256 remaining);
    error Paused();

    // =========================================================================
    // Events
    // =========================================================================

    event BreakerTrippedEvent(address indexed asset, uint256 oldPrice, uint256 newPrice, uint256 changeBps);
    event CircuitBreakerReset(address indexed asset);
    event PriceAccepted(address indexed asset, uint256 price, uint256 changeBps);
    event GlobalPause(bool paused);
    event LimitsUpdated(uint256 maxPriceChangeBps, uint256 maxHourlyChangeBps);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
    }

    // =========================================================================
    // Circuit Breaker Logic
    // =========================================================================

    /// @notice Check if a price update is valid and update state
    /// @param asset The asset address
    /// @param newPrice The proposed new price
    /// @return valid True if price is accepted
    function checkAndUpdate(address asset, uint256 newPrice) external returns (bool valid) {
        if (paused) revert Paused();

        AssetState storage state = assetState[asset];

        // Check cooldown if tripped
        if (state.tripped) {
            if (block.timestamp < state.tripTime + cooldownPeriod) {
                revert CooldownActive(asset, state.tripTime + cooldownPeriod - block.timestamp);
            }
            // Auto-reset after cooldown
            state.tripped = false;
            emit CircuitBreakerReset(asset);
        }

        // First price - always accept
        if (state.lastPrice == 0) {
            _updateState(state, newPrice);
            emit PriceAccepted(asset, newPrice, 0);
            return true;
        }

        // Check update interval
        uint256 elapsed = block.timestamp - state.lastUpdateTime;
        if (elapsed < minUpdateInterval) {
            revert UpdateTooFrequent(asset, elapsed);
        }

        // Get limits (use asset-specific or global)
        (uint256 maxChange, uint256 maxHourly) = _getLimits(asset);

        // Check instant price change
        uint256 changeBps = _calculateChangeBps(state.lastPrice, newPrice);
        if (changeBps > maxChange) {
            state.tripped = true;
            state.tripTime = block.timestamp;
            emit BreakerTrippedEvent(asset, state.lastPrice, newPrice, changeBps);
            revert BreakerTripped(asset, changeBps);
        }

        // Check hourly change
        if (block.timestamp >= state.hourlyStartTime + 1 hours) {
            // New hour - reset tracking
            state.hourlyStartPrice = newPrice;
            state.hourlyStartTime = block.timestamp;
        } else {
            uint256 hourlyChangeBps = _calculateChangeBps(state.hourlyStartPrice, newPrice);
            if (hourlyChangeBps > maxHourly) {
                state.tripped = true;
                state.tripTime = block.timestamp;
                emit BreakerTrippedEvent(asset, state.hourlyStartPrice, newPrice, hourlyChangeBps);
                revert HourlyLimitExceeded(asset, hourlyChangeBps);
            }
        }

        // Accept price
        _updateState(state, newPrice);
        emit PriceAccepted(asset, newPrice, changeBps);
        return true;
    }

    /// @notice View-only check without state update
    /// @param asset The asset address
    /// @param newPrice The proposed new price
    /// @return valid True if price would be accepted
    /// @return changeBps The price change in basis points
    function check(address asset, uint256 newPrice) external view returns (bool valid, uint256 changeBps) {
        if (paused) return (false, 0);

        AssetState memory state = assetState[asset];

        if (state.tripped && block.timestamp < state.tripTime + cooldownPeriod) {
            return (false, 0);
        }

        if (state.lastPrice == 0) {
            return (true, 0);
        }

        changeBps = _calculateChangeBps(state.lastPrice, newPrice);
        (uint256 maxChange, ) = _getLimits(asset);

        valid = changeBps <= maxChange;
    }

    /// @notice Check if circuit breaker is tripped for an asset
    function isTripped(address asset) external view returns (bool) {
        AssetState memory state = assetState[asset];
        return state.tripped && block.timestamp < state.tripTime + cooldownPeriod;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Set global limits
    function setLimits(uint256 _maxPriceChangeBps, uint256 _maxHourlyChangeBps) external onlyRole(GUARDIAN_ROLE) {
        require(_maxPriceChangeBps > 0 && _maxPriceChangeBps <= 5000, "Invalid max change"); // Max 50%
        require(_maxHourlyChangeBps >= _maxPriceChangeBps, "Hourly must be >= instant");

        maxPriceChangeBps = _maxPriceChangeBps;
        maxHourlyChangeBps = _maxHourlyChangeBps;
        emit LimitsUpdated(_maxPriceChangeBps, _maxHourlyChangeBps);
    }

    /// @notice Set per-asset limits
    function setAssetLimits(address asset, uint256 _maxPriceChangeBps, uint256 _maxHourlyChangeBps)
        external onlyRole(GUARDIAN_ROLE)
    {
        assetLimits[asset] = AssetLimits({
            maxPriceChangeBps: _maxPriceChangeBps,
            maxHourlyChangeBps: _maxHourlyChangeBps,
            configured: true
        });
    }

    /// @notice Clear asset-specific limits (use global)
    function clearAssetLimits(address asset) external onlyRole(GUARDIAN_ROLE) {
        delete assetLimits[asset];
    }

    /// @notice Manually reset circuit breaker for an asset
    function resetBreaker(address asset) external onlyRole(GUARDIAN_ROLE) {
        assetState[asset].tripped = false;
        emit CircuitBreakerReset(asset);
    }

    /// @notice Global pause
    function setPaused(bool _paused) external onlyRole(GUARDIAN_ROLE) {
        paused = _paused;
        emit GlobalPause(_paused);
    }

    /// @notice Set timing parameters
    function setTiming(uint256 _minUpdateInterval, uint256 _cooldownPeriod) external onlyRole(GUARDIAN_ROLE) {
        minUpdateInterval = _minUpdateInterval;
        cooldownPeriod = _cooldownPeriod;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    function _updateState(AssetState storage state, uint256 newPrice) internal {
        state.lastPrice = newPrice;
        state.lastUpdateTime = block.timestamp;

        if (state.hourlyStartTime == 0) {
            state.hourlyStartPrice = newPrice;
            state.hourlyStartTime = block.timestamp;
        }
    }

    function _getLimits(address asset) internal view returns (uint256 maxChange, uint256 maxHourly) {
        AssetLimits memory limits = assetLimits[asset];
        if (limits.configured) {
            return (limits.maxPriceChangeBps, limits.maxHourlyChangeBps);
        }
        return (maxPriceChangeBps, maxHourlyChangeBps);
    }

    function _calculateChangeBps(uint256 oldPrice, uint256 newPrice) internal pure returns (uint256) {
        if (oldPrice == 0) return 0;

        uint256 diff = newPrice > oldPrice ? newPrice - oldPrice : oldPrice - newPrice;
        return (diff * 10000) / oldPrice;
    }
}
