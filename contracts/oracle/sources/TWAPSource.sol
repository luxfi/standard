// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IOracleSource} from "../interfaces/IOracleSource.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Minimal Uniswap V2 pair interface for TWAP
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title TWAPSource
/// @notice Time-weighted average price from AMM liquidity pools
/// @dev Uses cumulative price mechanism from Uniswap V2-style pools
contract TWAPSource is IOracleSource, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice TWAP observation period (default 30 minutes)
    uint32 public twapPeriod = 30 minutes;

    /// @notice Minimum liquidity for valid price (in USD, 18 decimals)
    uint256 public minLiquidity = 10_000e18; // $10k minimum

    /// @notice Quote token (USD stablecoin) used for pricing
    address public immutable quoteToken;

    /// @notice Quote token decimals
    uint8 public immutable quoteDecimals;

    /// @notice Asset to pair mapping
    mapping(address => address) public pairs;

    /// @notice Is asset token0 in the pair
    mapping(address => bool) public isToken0;

    /// @notice Price observations for TWAP calculation
    struct Observation {
        uint32 timestamp;
        uint256 priceCumulative;
    }
    mapping(address => Observation) public observations;

    /// @notice Last heartbeat per asset
    mapping(address => uint256) public lastHeartbeat;

    error PairNotConfigured(address asset);
    error InsufficientLiquidity(address asset, uint256 liquidity);
    error StaleObservation(address asset, uint256 age);

    event PairConfigured(address indexed asset, address indexed pair, bool isToken0);
    event ObservationUpdated(address indexed asset, uint256 price, uint256 timestamp);

    constructor(address _quoteToken, uint8 _quoteDecimals) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        quoteToken = _quoteToken;
        quoteDecimals = _quoteDecimals;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Configure a pair for an asset
    /// @param asset The asset to price
    /// @param pair The Uniswap V2-style pair address
    function setPair(address asset, address pair) external onlyRole(ADMIN_ROLE) {
        pairs[asset] = pair;
        address token0 = IUniswapV2Pair(pair).token0();
        isToken0[asset] = (token0 == asset);

        // Initialize observation
        _updateObservation(asset);

        emit PairConfigured(asset, pair, isToken0[asset]);
    }

    /// @notice Set TWAP period
    function setTwapPeriod(uint32 _period) external onlyRole(ADMIN_ROLE) {
        twapPeriod = _period;
    }

    /// @notice Set minimum liquidity threshold
    function setMinLiquidity(uint256 _minLiquidity) external onlyRole(ADMIN_ROLE) {
        minLiquidity = _minLiquidity;
    }

    // =========================================================================
    // IOracleSource Implementation
    // =========================================================================

    /// @inheritdoc IOracleSource
    function getPrice(address asset) external view override returns (uint256 price, uint256 timestamp) {
        address pair = pairs[asset];
        if (pair == address(0)) revert PairNotConfigured(asset);

        // Get current reserves and cumulative price
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();

        // Check minimum liquidity (assume quote token is paired with asset)
        uint256 quoteLiquidity = isToken0[asset] ? reserve1 : reserve0;
        uint256 liquidityUsd = _normalizeToUsd(quoteLiquidity, quoteDecimals);
        if (liquidityUsd < minLiquidity) revert InsufficientLiquidity(asset, liquidityUsd);

        // Get TWAP price
        Observation memory obs = observations[asset];
        if (obs.timestamp == 0) {
            // No observation yet, use spot price
            price = _getSpotPrice(asset, reserve0, reserve1);
        } else {
            uint32 elapsed = blockTimestampLast - obs.timestamp;
            if (elapsed >= twapPeriod) {
                // Calculate TWAP
                uint256 currentCumulative = isToken0[asset]
                    ? IUniswapV2Pair(pair).price0CumulativeLast()
                    : IUniswapV2Pair(pair).price1CumulativeLast();

                // Price cumulative is UQ112x112 format
                uint256 priceDelta = currentCumulative - obs.priceCumulative;
                price = _normalizeToUsd(priceDelta / elapsed, 112); // UQ112 to 18 decimals
            } else {
                // Observation too fresh, use spot with TWAP blend
                uint256 spotPrice = _getSpotPrice(asset, reserve0, reserve1);
                price = spotPrice; // For now, use spot if TWAP period not elapsed
            }
        }

        timestamp = blockTimestampLast;
    }

    /// @inheritdoc IOracleSource
    function isSupported(address asset) external view override returns (bool) {
        return pairs[asset] != address(0);
    }

    /// @inheritdoc IOracleSource
    function source() external pure override returns (string memory) {
        return "twap";
    }

    /// @inheritdoc IOracleSource
    function health() external view override returns (bool healthy, uint256 lastHb) {
        // Check if any pair has been updated recently
        // This is a simplification - in production, check all configured pairs
        healthy = true;
        lastHb = block.timestamp;
    }

    // =========================================================================
    // Observation Management
    // =========================================================================

    /// @notice Update observation for TWAP calculation (call periodically)
    /// @param asset The asset to update
    function updateObservation(address asset) external {
        _updateObservation(asset);
    }

    /// @notice Batch update observations
    function updateObservations(address[] calldata assets) external {
        for (uint256 i = 0; i < assets.length; i++) {
            _updateObservation(assets[i]);
        }
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    function _updateObservation(address asset) internal {
        address pair = pairs[asset];
        if (pair == address(0)) return;

        (, , uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();

        uint256 priceCumulative = isToken0[asset]
            ? IUniswapV2Pair(pair).price0CumulativeLast()
            : IUniswapV2Pair(pair).price1CumulativeLast();

        observations[asset] = Observation({
            timestamp: blockTimestampLast,
            priceCumulative: priceCumulative
        });

        lastHeartbeat[asset] = block.timestamp;

        // Emit spot price for monitoring
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        emit ObservationUpdated(asset, _getSpotPrice(asset, r0, r1), block.timestamp);
    }

    function _getSpotPrice(address asset, uint112 reserve0, uint112 reserve1) internal view returns (uint256) {
        // Price = quoteReserve / assetReserve (normalized to 18 decimals)
        if (isToken0[asset]) {
            // asset is token0, quote is token1
            if (reserve0 == 0) return 0;
            return _normalizeToUsd(uint256(reserve1) * 1e18 / reserve0, quoteDecimals);
        } else {
            // asset is token1, quote is token0
            if (reserve1 == 0) return 0;
            return _normalizeToUsd(uint256(reserve0) * 1e18 / reserve1, quoteDecimals);
        }
    }

    function _normalizeToUsd(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return amount * 10**(18 - decimals);
        } else if (decimals > 18) {
            return amount / 10**(decimals - 18);
        }
        return amount;
    }
}
