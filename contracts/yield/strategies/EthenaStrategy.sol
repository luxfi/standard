// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title EthenaStrategy
 * @notice Yield strategy for Ethena USDe/sUSDe
 * @dev Ethena earns yield from delta-neutral ETH positions + funding rates
 * 
 * APY: 15-30%+ (varies with funding rates)
 * Risk: Medium-High (smart contract + counterparty + funding rate risk)
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Ethena sUSDe interface (staked USDe)
interface IsUSDe {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
}

contract EthenaStrategy is Ownable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS (Ethereum Mainnet)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice USDe stablecoin
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    
    /// @notice sUSDe (staked USDe)
    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total sUSDe shares held
    uint256 public totalShares;

    /// @notice Total deposited (for yield tracking)
    uint256 public totalDeposited;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Accepts USDC and converts to USDe
    address public immutable inputAsset;

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "EthenaStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _vault, address _inputAsset) Ownable(msg.sender) {
        vault = _vault;
        inputAsset = _inputAsset;
        
        // Approve sUSDe to spend USDe
        IERC20(USDE).approve(SUSDE, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external onlyVault returns (uint256 shares) {
        require(active, "EthenaStrategy: not active");
        
        // Receive USDe (or USDC which needs to be swapped first)
        IERC20(USDE).safeTransferFrom(msg.sender, address(this), amount);

        // Stake USDe for sUSDe
        shares = IsUSDe(SUSDE).deposit(amount, address(this));
        totalShares += shares;
        totalDeposited += amount;
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        require(shares <= totalShares, "EthenaStrategy: insufficient shares");

        // Redeem sUSDe for USDe
        amount = IsUSDe(SUSDE).redeem(shares, vault, address(this));
        totalShares -= shares;
        if (amount <= totalDeposited) {
            totalDeposited -= amount;
        } else {
            totalDeposited = 0;
        }
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // sUSDe is share-based, yield is reflected in exchange rate
        // No explicit harvest needed
        harvested = 0;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return IsUSDe(SUSDE).convertToAssets(totalShares);
    }

    /// @notice
    function currentAPY() external pure returns (uint256) {
        // Ethena yields 15-30%+ from funding rates
        return 2000; // 20% in basis points (conservative estimate)
    }

    /// @notice
    function underlying() external view returns (address) {
        return inputAsset;
    }

    /// @notice
    function yieldToken() external pure returns (address) {
        return SUSDE;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Ethena sUSDe Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
}
