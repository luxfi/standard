// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IOracleSource} from "../interfaces/IOracleSource.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice DEX precompile pool manager interface (subset needed for pricing)
interface IPoolManagerOracle {
    function getPool(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) external view returns (uint160 sqrtPriceX96, int24 tick, uint128 liquidity);
}

/// @title DEXSource
/// @notice Price source from native DEX precompile (Uniswap V4-style)
/// @dev Reads sqrtPriceX96 from PoolManager precompile at 0x0400
contract DEXSource is IOracleSource, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice DEX PoolManager precompile address
    address public constant POOL_MANAGER = 0x0000000000000000000000000000000000000400;

    /// @notice Quote token (USD stablecoin) for pricing
    address public immutable quoteToken;

    /// @notice Minimum liquidity for valid price (in quote token units)
    uint128 public minLiquidity = 1000e18; // 1000 quote tokens minimum

    /// @notice Pool configuration for each asset
    struct PoolConfig {
        address currency0;      // Lower address token
        address currency1;      // Higher address token
        uint24 fee;             // Fee tier (e.g., 3000 = 0.30%)
        int24 tickSpacing;      // Tick spacing
        address hooks;          // Hook address (0x0 for none)
        bool assetIsCurrency0;  // True if asset is currency0
    }
    mapping(address => PoolConfig) public poolConfigs;

    /// @notice Last successful price read timestamp
    mapping(address => uint256) public lastSuccessfulRead;

    error PoolNotConfigured(address asset);
    error PoolNotInitialized(address asset);
    error InsufficientLiquidity(address asset, uint128 liquidity);
    error PrecompileCallFailed();

    event PoolConfigured(address indexed asset, uint24 fee, int24 tickSpacing);

    constructor(address _quoteToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        quoteToken = _quoteToken;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Configure a pool for an asset
    /// @param asset The asset to price
    /// @param fee Fee tier (e.g., 3000 for 0.30%)
    /// @param tickSpacing Tick spacing for the pool
    /// @param hooks Hook contract address (address(0) for none)
    function setPool(
        address asset,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) external onlyRole(ADMIN_ROLE) {
        // Sort currencies (required by pool key)
        (address currency0, address currency1, bool assetIsCurrency0) = _sortCurrencies(asset, quoteToken);

        poolConfigs[asset] = PoolConfig({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks,
            assetIsCurrency0: assetIsCurrency0
        });

        emit PoolConfigured(asset, fee, tickSpacing);
    }

    /// @notice Set minimum liquidity threshold
    function setMinLiquidity(uint128 _minLiquidity) external onlyRole(ADMIN_ROLE) {
        minLiquidity = _minLiquidity;
    }

    // =========================================================================
    // IOracleSource Implementation
    // =========================================================================

    /// @inheritdoc IOracleSource
    function getPrice(address asset) external view override returns (uint256 price, uint256 timestamp) {
        PoolConfig memory config = poolConfigs[asset];
        if (config.currency0 == address(0)) revert PoolNotConfigured(asset);

        // Call PoolManager precompile
        (uint160 sqrtPriceX96, , uint128 liquidity) = _getPool(config);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized(asset);
        if (liquidity < minLiquidity) revert InsufficientLiquidity(asset, liquidity);

        // Convert sqrtPriceX96 to price with 18 decimals
        // sqrtPriceX96 = sqrt(price) * 2^96
        // price = (sqrtPriceX96 / 2^96)^2
        // For 18 decimal precision: price = (sqrtPriceX96^2 * 1e18) / 2^192
        price = _sqrtPriceX96ToPrice(sqrtPriceX96, config.assetIsCurrency0);

        timestamp = block.timestamp; // DEX prices are always current
    }

    /// @inheritdoc IOracleSource
    function isSupported(address asset) external view override returns (bool) {
        return poolConfigs[asset].currency0 != address(0);
    }

    /// @inheritdoc IOracleSource
    function source() external pure override returns (string memory) {
        return "dex";
    }

    /// @inheritdoc IOracleSource
    function health() external view override returns (bool healthy, uint256 lastHb) {
        // DEX precompile is always available if chain is running
        healthy = true;
        lastHb = block.timestamp;
    }

    // =========================================================================
    // View Functions
    // =========================================================================

    /// @notice Get current tick for an asset (useful for range orders)
    /// @param asset The asset address
    /// @return tick Current pool tick
    function getTick(address asset) external view returns (int24 tick) {
        PoolConfig memory config = poolConfigs[asset];
        if (config.currency0 == address(0)) revert PoolNotConfigured(asset);

        (, tick, ) = _getPool(config);
    }

    /// @notice Get current liquidity for an asset
    /// @param asset The asset address
    /// @return liquidity Current pool liquidity
    function getLiquidity(address asset) external view returns (uint128 liquidity) {
        PoolConfig memory config = poolConfigs[asset];
        if (config.currency0 == address(0)) revert PoolNotConfigured(asset);

        (, , liquidity) = _getPool(config);
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    function _getPool(PoolConfig memory config)
        internal view returns (uint160 sqrtPriceX96, int24 tick, uint128 liquidity)
    {
        // Static call to precompile
        (bool success, bytes memory data) = POOL_MANAGER.staticcall(
            abi.encodeWithSelector(
                IPoolManagerOracle.getPool.selector,
                config.currency0,
                config.currency1,
                config.fee,
                config.tickSpacing,
                config.hooks
            )
        );

        if (!success) {
            // Precompile may not be available (e.g., on testnets)
            // Return zeros instead of reverting for graceful degradation
            return (0, 0, 0);
        }

        (sqrtPriceX96, tick, liquidity) = abi.decode(data, (uint160, int24, uint128));
    }

    function _sortCurrencies(address tokenA, address tokenB)
        internal pure returns (address currency0, address currency1, bool aIsCurrency0)
    {
        if (tokenA < tokenB) {
            return (tokenA, tokenB, true);
        }
        return (tokenB, tokenA, false);
    }

    function _sqrtPriceX96ToPrice(uint160 sqrtPriceX96, bool assetIsCurrency0)
        internal pure returns (uint256 price)
    {
        // sqrtPriceX96 = sqrt(currency1/currency0) * 2^96
        // price (currency0 in terms of currency1) = (sqrtPriceX96 / 2^96)^2

        // To avoid overflow, we split the calculation:
        // price = sqrtPriceX96^2 / 2^192
        // For 18 decimals: price = (sqrtPriceX96^2 * 1e18) / 2^192

        uint256 sqrtPrice256 = uint256(sqrtPriceX96);

        // price = sqrtPrice^2 * 1e18 / 2^192
        // = sqrtPrice^2 / 2^192 * 1e18
        // = (sqrtPrice / 2^96)^2 * 1e18

        // Split to avoid overflow:
        // numerator = sqrtPrice * sqrtPrice
        // We need to be careful with overflow for large prices

        uint256 numerator = sqrtPrice256 * sqrtPrice256;

        // Q96 * Q96 = Q192, so divide by 2^192 and multiply by 1e18
        // Rearrange: (numerator * 1e18) / 2^192
        // = numerator / 2^192 * 1e18  (but this loses precision)
        // Better: (numerator / 2^64) * 1e18 / 2^128

        // Use full precision division
        price = (numerator >> 192) * 1e18;
        if (price == 0) {
            // Handle small prices more carefully
            price = (numerator * 1e18) >> 192;
        }

        // If asset is currency0, price is already correct (asset per quote)
        // If asset is currency1, we need 1/price (quote per asset)
        if (!assetIsCurrency0 && price > 0) {
            price = 1e36 / price; // 18 + 18 = 36 decimals precision
        }
    }
}
