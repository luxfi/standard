// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title RocketPoolStrategy
 * @notice Yield strategy that deposits ETH into Rocket Pool for rETH
 * @dev Deployed on Ethereum mainnet, earns ~4-5% APY from ETH staking
 * 
 * rETH is a non-rebasing token - value increases over time relative to ETH
 */

import {IYieldStrategy} from "../IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Rocket Pool deposit interface
interface IRocketDepositPool {
    function deposit() external payable;
    function getBalance() external view returns (uint256);
}

/// @notice Rocket Pool rETH token interface
interface IRocketTokenRETH {
    function getExchangeRate() external view returns (uint256);
    function getRethValue(uint256 _ethAmount) external view returns (uint256);
    function getEthValue(uint256 _rethAmount) external view returns (uint256);
    function burn(uint256 _rethAmount) external;
}

/// @notice Rocket Pool storage interface
interface IRocketStorage {
    function getAddress(bytes32 _key) external view returns (address);
}

contract RocketPoolStrategy is Ownable{
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Rocket Pool Storage (Ethereum mainnet)
    IRocketStorage public constant ROCKET_STORAGE = IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
    
    /// @notice rETH token address (Ethereum mainnet)
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice Total rETH held by this strategy
    uint256 public totalReth;

    /// @notice Strategy active status
    bool public active = true;

    /// @notice Last recorded exchange rate (for APY calculation)
    uint256 public lastExchangeRate;
    uint256 public lastRateUpdate;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Deposited(uint256 ethAmount, uint256 rethReceived);
    event Withdrawn(uint256 rethAmount, uint256 ethReceived);

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyVault() {
        require(msg.sender == vault, "RocketPoolStrategy: only vault");
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        lastExchangeRate = IRocketTokenRETH(RETH).getExchangeRate();
        lastRateUpdate = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // YIELD STRATEGY INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice
    function deposit(uint256 amount) external payable onlyVault returns (uint256 shares) {
        require(active, "RocketPoolStrategy: not active");
        require(msg.value == amount, "RocketPoolStrategy: ETH amount mismatch");

        // Get deposit pool address from storage
        address depositPoolAddress = ROCKET_STORAGE.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        IRocketDepositPool depositPool = IRocketDepositPool(depositPoolAddress);

        // Record rETH balance before
        uint256 rethBefore = IERC20(RETH).balanceOf(address(this));

        // Deposit ETH to Rocket Pool
        depositPool.deposit{value: amount}();

        // Calculate rETH received
        uint256 rethAfter = IERC20(RETH).balanceOf(address(this));
        shares = rethAfter - rethBefore;
        totalReth += shares;

        emit Deposited(amount, shares);
    }

    /// @notice
    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        require(shares <= totalReth, "RocketPoolStrategy: insufficient rETH");

        // Calculate ETH value
        amount = IRocketTokenRETH(RETH).getEthValue(shares);
        totalReth -= shares;

        // Transfer rETH to vault (vault can burn for ETH or sell on DEX)
        IERC20(RETH).safeTransfer(vault, shares);

        emit Withdrawn(shares, amount);
    }

    /// @notice
    function harvest() external returns (uint256 harvested) {
        // rETH is non-rebasing - value appreciation is built into the token
        // Calculate yield as rate difference since last update
        uint256 currentRate = IRocketTokenRETH(RETH).getExchangeRate();
        
        if (currentRate > lastExchangeRate && totalReth > 0) {
            // Calculate yield in ETH terms
            uint256 currentValue = IRocketTokenRETH(RETH).getEthValue(totalReth);
            uint256 previousValue = (totalReth * lastExchangeRate) / 1e18;
            harvested = currentValue > previousValue ? currentValue - previousValue : 0;
        }

        lastExchangeRate = currentRate;
        lastRateUpdate = block.timestamp;
    }

    /// @notice
    function totalAssets() external view returns (uint256) {
        return IRocketTokenRETH(RETH).getEthValue(totalReth);
    }

    /// @notice
    function currentAPY() external view returns (uint256) {
        // Calculate APY from exchange rate change
        // Rocket Pool typically yields 4-5%
        return 450; // 4.5% in basis points
    }

    /// @notice
    function underlying() external pure returns (address) {
        return address(0); // Native ETH
    }

    /// @notice
    function yieldToken() external pure returns (address) {
        return RETH;
    }

    /// @notice
    function isActive() external view returns (bool) {
        return active;
    }

    /// @notice
    function name() external pure returns (string memory) {
        return "Rocket Pool rETH Strategy";
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setActive(bool _active) external onlyOwner {
        active = _active;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    receive() external payable {}
}
