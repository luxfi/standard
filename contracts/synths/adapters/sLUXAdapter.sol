// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITokenAdapter} from "../interfaces/ITokenAdapter.sol";

interface IsLUX {
    function stake(uint256 luxAmount) external returns (uint256);
    function instantUnstake(uint256 sLuxAmount) external returns (uint256);
    function exchangeRate() external view returns (uint256);
    function previewDeposit(uint256 luxAmount) external view returns (uint256);
    function previewRedeem(uint256 sLuxAmount) external view returns (uint256);
    function lux() external view returns (address);
}

/**
 * @title sLUXAdapter
 * @notice Token adapter for sLUX (Staked LUX) yield token
 * @dev Allows AlchemistV2 to use sLUX as collateral for minting xLUX
 */
contract sLUXAdapter is ITokenAdapter {
    using SafeERC20 for IERC20;

    string public constant override version = "1.0.0";

    /// @notice The sLUX yield token
    IsLUX public immutable sLux;

    /// @notice The underlying LUX token (WLUX)
    IERC20 public immutable lux;

    constructor(address _sLux) {
        sLux = IsLUX(_sLux);
        lux = IERC20(sLux.lux());
    }

    /// @inheritdoc ITokenAdapter
    function token() external view override returns (address) {
        return address(sLux);
    }

    /// @inheritdoc ITokenAdapter
    function underlyingToken() external view override returns (address) {
        return address(lux);
    }

    /// @notice Get the price of sLUX in terms of LUX
    /// @return Price scaled by 1e18
    function price() external view override returns (uint256) {
        return sLux.exchangeRate();
    }

    /// @notice Wrap LUX into sLUX
    /// @param amount Amount of LUX to wrap
    /// @param recipient Recipient of sLUX
    /// @return sLuxAmount Amount of sLUX received
    function wrap(uint256 amount, address recipient) external override returns (uint256 sLuxAmount) {
        // Transfer LUX from caller
        lux.safeTransferFrom(msg.sender, address(this), amount);
        
        // Approve sLUX contract
        lux.safeIncreaseAllowance(address(sLux), amount);
        
        // Stake LUX for sLUX
        sLuxAmount = sLux.stake(amount);
        
        // Transfer sLUX to recipient
        if (recipient != address(this)) {
            IERC20(address(sLux)).safeTransfer(recipient, sLuxAmount);
        }
    }

    /// @notice Unwrap sLUX into LUX
    /// @param amount Amount of sLUX to unwrap
    /// @param recipient Recipient of LUX
    /// @return luxAmount Amount of LUX received
    function unwrap(uint256 amount, address recipient) external override returns (uint256 luxAmount) {
        // Transfer sLUX from caller
        IERC20(address(sLux)).safeTransferFrom(msg.sender, address(this), amount);
        
        // Instant unstake (with penalty for immediate liquidity)
        luxAmount = sLux.instantUnstake(amount);
        
        // Transfer LUX to recipient
        if (recipient != address(this)) {
            lux.safeTransfer(recipient, luxAmount);
        }
    }
}
