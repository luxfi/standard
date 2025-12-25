// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MultiFaucet
/// @notice Testnet faucet that distributes multiple tokens
/// @dev Supports rate limiting and configurable drip amounts
contract MultiFaucet is Ownable {
    /// @notice Token configuration
    struct TokenConfig {
        uint256 dripAmount;    // Amount per request
        uint256 cooldown;      // Cooldown between requests
        bool enabled;          // Whether token is active
    }

    /// @notice Token configs by address
    mapping(address => TokenConfig) public tokens;

    /// @notice Last drip time per user per token
    mapping(address => mapping(address => uint256)) public lastDrip;

    /// @notice Registered token list
    address[] public tokenList;

    /// @notice Native token (LUX) drip amount
    uint256 public nativeDripAmount;

    /// @notice Native token cooldown
    uint256 public nativeCooldown;

    event TokenAdded(address indexed token, uint256 dripAmount, uint256 cooldown);
    event TokenRemoved(address indexed token);
    event Drip(address indexed user, address indexed token, uint256 amount);
    event NativeDrip(address indexed user, uint256 amount);

    error CooldownActive(uint256 timeRemaining);
    error TokenNotEnabled();
    error InsufficientBalance();
    error TransferFailed();

    constructor() Ownable(msg.sender) {
        nativeDripAmount = 1 ether;  // 1 LUX
        nativeCooldown = 1 hours;
    }

    /// @notice Request tokens from faucet
    function drip(address token) external {
        TokenConfig memory config = tokens[token];
        if (!config.enabled) revert TokenNotEnabled();

        uint256 lastTime = lastDrip[msg.sender][token];
        if (block.timestamp < lastTime + config.cooldown) {
            revert CooldownActive(lastTime + config.cooldown - block.timestamp);
        }

        if (IERC20(token).balanceOf(address(this)) < config.dripAmount) {
            revert InsufficientBalance();
        }

        lastDrip[msg.sender][token] = block.timestamp;
        IERC20(token).transfer(msg.sender, config.dripAmount);

        emit Drip(msg.sender, token, config.dripAmount);
    }

    /// @notice Request native LUX from faucet
    function dripNative() external {
        uint256 lastTime = lastDrip[msg.sender][address(0)];
        if (block.timestamp < lastTime + nativeCooldown) {
            revert CooldownActive(lastTime + nativeCooldown - block.timestamp);
        }

        if (address(this).balance < nativeDripAmount) {
            revert InsufficientBalance();
        }

        lastDrip[msg.sender][address(0)] = block.timestamp;

        (bool success,) = msg.sender.call{value: nativeDripAmount}("");
        if (!success) revert TransferFailed();

        emit NativeDrip(msg.sender, nativeDripAmount);
    }

    /// @notice Request all enabled tokens at once
    function dripAll() external {
        // Drip native if available
        if (address(this).balance >= nativeDripAmount) {
            uint256 lastNative = lastDrip[msg.sender][address(0)];
            if (block.timestamp >= lastNative + nativeCooldown) {
                lastDrip[msg.sender][address(0)] = block.timestamp;
                (bool success,) = msg.sender.call{value: nativeDripAmount}("");
                if (success) emit NativeDrip(msg.sender, nativeDripAmount);
            }
        }

        // Drip each enabled token
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            TokenConfig memory config = tokens[token];
            if (!config.enabled) continue;

            uint256 lastTime = lastDrip[msg.sender][token];
            if (block.timestamp < lastTime + config.cooldown) continue;
            if (IERC20(token).balanceOf(address(this)) < config.dripAmount) continue;

            lastDrip[msg.sender][token] = block.timestamp;
            IERC20(token).transfer(msg.sender, config.dripAmount);
            emit Drip(msg.sender, token, config.dripAmount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Add a token to the faucet
    function addToken(address token, uint256 dripAmount, uint256 cooldown) external onlyOwner {
        tokens[token] = TokenConfig({
            dripAmount: dripAmount,
            cooldown: cooldown,
            enabled: true
        });
        tokenList.push(token);
        emit TokenAdded(token, dripAmount, cooldown);
    }

    /// @notice Update token configuration
    function updateToken(address token, uint256 dripAmount, uint256 cooldown, bool enabled) external onlyOwner {
        tokens[token] = TokenConfig({
            dripAmount: dripAmount,
            cooldown: cooldown,
            enabled: enabled
        });
    }

    /// @notice Update native token settings
    function updateNative(uint256 dripAmount, uint256 cooldown) external onlyOwner {
        nativeDripAmount = dripAmount;
        nativeCooldown = cooldown;
    }

    /// @notice Withdraw tokens (admin)
    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    /// @notice Withdraw native (admin)
    function withdrawNative(uint256 amount) external onlyOwner {
        (bool success,) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }

    /// @notice Get all registered tokens
    function getTokenList() external view returns (address[] memory) {
        return tokenList;
    }

    /// @notice Get token count
    function tokenCount() external view returns (uint256) {
        return tokenList.length;
    }

    /// @notice Check if user can drip a token
    function canDrip(address user, address token) external view returns (bool, uint256 timeRemaining) {
        if (token == address(0)) {
            uint256 lastTime = lastDrip[user][address(0)];
            if (block.timestamp >= lastTime + nativeCooldown) {
                return (true, 0);
            }
            return (false, lastTime + nativeCooldown - block.timestamp);
        }

        TokenConfig memory config = tokens[token];
        if (!config.enabled) return (false, 0);

        uint256 lastTime = lastDrip[user][token];
        if (block.timestamp >= lastTime + config.cooldown) {
            return (true, 0);
        }
        return (false, lastTime + config.cooldown - block.timestamp);
    }

    receive() external payable {}
}
