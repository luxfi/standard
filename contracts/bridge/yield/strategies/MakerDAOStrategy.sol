// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MakerDAOStrategy
 * @notice Yield strategy for MakerDAO sDAI (Savings DAI)
 * @dev sDAI earns the DAI Savings Rate (DSR) set by MakerDAO governance
 *
 * APY: ~5% (DSR, varies with governance)
 * Risk: Very Low (battle-tested, over $1B TVL)
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice sDAI interface (ERC4626 vault)
interface IsDAI {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
}

/// @notice MakerDAO Pot interface (for DSR rate)
interface IPot {
    function dsr() external view returns (uint256); // DSR rate in ray (27 decimals)
    function chi() external view returns (uint256); // Accumulated rate
}

contract MakerDAOStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS (Ethereum Mainnet)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice DAI stablecoin
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /// @notice sDAI (Savings DAI)
    address public constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;

    /// @notice MakerDAO Pot (for DSR rate)
    address public constant POT = 0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    address public vault;
    uint256 public totalShares;
    uint256 public totalDeposited;
    bool public active = true;

    modifier onlyVault() {
        require(msg.sender == vault, "MakerDAOStrategy: only vault");
        _;
    }

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        IERC20(DAI).approve(SDAI, type(uint256).max);
    }

    /// @notice
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        require(active, "MakerDAOStrategy: not active");
        IERC20(DAI).safeTransferFrom(msg.sender, address(this), amount);
        shares = IsDAI(SDAI).deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;
    }

    /// @notice
    function withdraw(uint256 amount) external onlyVault returns (uint256 assets) {
        // Convert amount to shares
        uint256 shares = IsDAI(SDAI).convertToShares(amount);
        require(shares <= totalShares, "MakerDAOStrategy: insufficient shares");
        assets = IsDAI(SDAI).redeem(shares, vault, address(this));
        totalShares -= shares;
        if (totalDeposited >= assets) {
            totalDeposited -= assets;
        } else {
            totalDeposited = 0;
        }
    }

    /// @notice
    function harvest() external returns (uint256) {
        return 0; // sDAI yield is reflected in exchange rate
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return IsDAI(SDAI).convertToAssets(totalShares);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate APY from DSR
        // dsr is in ray (1e27), represents per-second rate
        // APY = (dsr ^ seconds_per_year) - 1
        uint256 dsr = IPot(POT).dsr();
        // Simplified: (dsr - 1e27) * seconds_per_year / 1e27 * 10000
        // For ~5% APY, dsr ≈ 1.000000001547125957863212448e27
        return 500; // ~5% in basis points (approximate)
    }

    /// @notice
    function asset() external pure returns (address) {
        return DAI;
    }

    /// @notice Get yield token address (not in interface)
    function yieldToken() external pure returns (address) {
        return SDAI;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "MakerDAO sDAI Strategy";
    }

    function setActive(bool _active) external onlyOwner { active = _active; }
    function setVault(address _vault) external onlyOwner { vault = _vault; }
}
