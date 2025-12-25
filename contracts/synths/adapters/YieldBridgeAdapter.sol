// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title YieldBridgeAdapter
 * @notice Alchemix adapter for yield-bearing bridge tokens (yLETH, yLBTC, yLUSD, etc.)
 * @dev Allows using bridged assets as self-repaying collateral in Alchemix
 * 
 * Flow:
 * 1. User deposits yLETH into Alchemix
 * 2. Alchemix recognizes yLETH as yield-bearing collateral
 * 3. User borrows xETH (synthetic ETH)
 * 4. Yield from source chain (Lido/Rocket Pool on Ethereum) repays xETH debt
 * 5. Loan becomes self-repaying!
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenAdapter} from "../interfaces/ITokenAdapter.sol";

/// @notice Interface for yield-bearing bridge tokens
interface IYieldBearingBridgeToken {
    function pricePerShare() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function balanceOfUnderlying(address account) external view returns (uint256);
    function isYieldBearing() external view returns (bool);
    function getAverageAPY() external view returns (uint256);
    function underlyingSymbol() external view returns (string memory);
    function sourceChainId() external view returns (uint32);
}

/**
 * @title YieldBridgeAdapter
 * @notice Alchemix TokenAdapter for yield-bearing bridge tokens
 */
contract YieldBridgeAdapter is ITokenAdapter {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice The yield-bearing bridge token (yLETH, yLBTC, etc.)
    address public immutable override token;

    /// @notice The underlying token this represents (LETH, LBTC, etc.)
    /// @dev For yLETH, this would be LETH (or address(0) for native representation)
    address public immutable override underlyingToken;

    /// @notice Version of this adapter
    string public constant version = "1.0.0";

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(
        address _yieldToken,
        address _underlyingToken
    ) {
        require(
            IYieldBearingBridgeToken(_yieldToken).isYieldBearing(),
            "YieldBridgeAdapter: not yield-bearing token"
        );
        token = _yieldToken;
        underlyingToken = _underlyingToken;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOKEN ADAPTER INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the current price of the yield token in underlying terms
     * @return Price per share in 18 decimals
     */
    function price() external view override returns (uint256) {
        return IYieldBearingBridgeToken(token).pricePerShare();
    }

    /**
     * @notice Wrap underlying tokens into yield-bearing tokens
     * @param amount Amount of underlying to wrap
     * @param recipient Address to receive yield tokens
     * @return amountYieldTokens Amount of yield tokens received
     */
    function wrap(
        uint256 amount,
        address recipient
    ) external override returns (uint256 amountYieldTokens) {
        // Transfer underlying from caller
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);

        // Convert to shares
        amountYieldTokens = IYieldBearingBridgeToken(token).convertToShares(amount);

        // Transfer yield tokens to recipient
        IERC20(token).safeTransfer(recipient, amountYieldTokens);
    }

    /**
     * @notice Unwrap yield-bearing tokens to underlying
     * @param amount Amount of yield tokens to unwrap
     * @param recipient Address to receive underlying
     * @return amountUnderlyingTokens Amount of underlying received
     */
    function unwrap(
        uint256 amount,
        address recipient
    ) external override returns (uint256 amountUnderlyingTokens) {
        // Transfer yield tokens from caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Convert to assets
        amountUnderlyingTokens = IYieldBearingBridgeToken(token).convertToAssets(amount);

        // Transfer underlying to recipient
        IERC20(underlyingToken).safeTransfer(recipient, amountUnderlyingTokens);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADDITIONAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get the current APY of the yield token
     * @return APY in basis points
     */
    function currentAPY() external view returns (uint256) {
        return IYieldBearingBridgeToken(token).getAverageAPY();
    }

    /**
     * @notice Get underlying value of yield tokens
     * @param shares Amount of yield tokens
     * @return Underlying value
     */
    function getUnderlyingValue(uint256 shares) external view returns (uint256) {
        return IYieldBearingBridgeToken(token).convertToAssets(shares);
    }

    /**
     * @notice Get source chain info
     * @return chainId Source chain ID
     */
    function sourceChainId() external view returns (uint32) {
        return IYieldBearingBridgeToken(token).sourceChainId();
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONCRETE IMPLEMENTATIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * @title yLETHAdapter
 * @notice Adapter for yLETH (Yield-Bearing Lux ETH) in Alchemix
 */
contract yLETHAdapter is YieldBridgeAdapter {
    constructor(
        address _yLETH,
        address _LETH
    ) YieldBridgeAdapter(_yLETH, _LETH) {}
}

/**
 * @title yLBTCAdapter
 * @notice Adapter for yLBTC (Yield-Bearing Lux BTC) in Alchemix
 */
contract yLBTCAdapter is YieldBridgeAdapter {
    constructor(
        address _yLBTC,
        address _LBTC
    ) YieldBridgeAdapter(_yLBTC, _LBTC) {}
}

/**
 * @title yLUSDAdapter
 * @notice Adapter for yLUSD (Yield-Bearing Lux USD) in Alchemix
 */
contract yLUSDAdapter is YieldBridgeAdapter {
    constructor(
        address _yLUSD,
        address _LUSD
    ) YieldBridgeAdapter(_yLUSD, _LUSD) {}
}
