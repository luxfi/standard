// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
    ██╗     ██╗   ██╗██╗  ██╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
    ██║     ██║   ██║╚██╗██╔╝    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
    ██║     ██║   ██║ ╚███╔╝        ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
    ██║     ██║   ██║ ██╔██╗        ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████╗╚██████╔╝██╔╝ ██╗       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
 */

import {LRC20} from "../tokens/LRC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title LRC20B
 * @author Lux Network
 * @notice LRC20 Bridge Token - Base contract for bridged tokens
 * @dev Extends LRC20 with bridge mint/burn capabilities and role-based access
 */
contract LRC20B is LRC20, Ownable, AccessControl {
    // ═══════════════════════════════════════════════════════════════════════
    // ROLES - C-03 fix: Add separate MINTER_ROLE
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS - C-03 fix: Daily mint limit
    // ═══════════════════════════════════════════════════════════════════════

    uint256 public constant MINT_LIMIT_PERIOD = 1 days;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE - C-03 fix: Daily mint tracking
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Daily mint limit (configurable by admin)
    uint256 public dailyMintLimit;

    /// @notice Amount minted in current period
    uint256 public dailyMinted;

    /// @notice Start of current mint period
    uint256 public mintPeriodStart;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event BridgeMint(address indexed account, uint amount);
    event BridgeBurn(address indexed account, uint amount);
    event AdminGranted(address to);
    event AdminRevoked(address to);
    event MinterGranted(address indexed minter);
    event MinterRevoked(address indexed minter);
    event DailyMintLimitSet(uint256 newLimit);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS - C-03 fix: Add mint limit error
    // ═══════════════════════════════════════════════════════════════════════

    error MintLimitExceeded();
    error InsufficientAllowance();

    constructor(
        string memory name_,
        string memory symbol_
    ) LRC20(name_, symbol_) Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        mintPeriodStart = block.timestamp;
    }

    /**
     * @dev verify that the sender is an admin
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "LRC20B: caller is not admin"
        );
        _;
    }

    /**
     * @dev grant admin role to specific user
     */
    function grantAdmin(address to) public onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminGranted(to);
    }

    /**
     * @dev revoke admin role from specific user
     */
    function revokeAdmin(address to) public onlyAdmin {
        require(hasRole(DEFAULT_ADMIN_ROLE, to), "LRC20B: not an admin");
        revokeRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminRevoked(to);
    }

    /**
     * @dev mint token via bridge
     * @dev C-03 fix: Uses MINTER_ROLE and enforces daily mint limit
     * @return amount If successful, returns true
     */
    function bridgeMint(
        address account,
        uint256 amount
    ) public returns (bool) {
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "LRC20B: caller is not minter"
        );

        // C-03 fix: Reset period if needed
        if (block.timestamp >= mintPeriodStart + MINT_LIMIT_PERIOD) {
            dailyMinted = 0;
            mintPeriodStart = block.timestamp;
        }

        // C-03 fix: Enforce daily mint limit (if set)
        if (dailyMintLimit > 0) {
            if (dailyMinted + amount > dailyMintLimit) {
                revert MintLimitExceeded();
            }
            dailyMinted += amount;
        }

        _mint(account, amount);
        emit BridgeMint(account, amount);
        return true;
    }

    /**
     * @dev burn token via bridge
     * @dev H-02 fix: Only allow burning from address(this) or with allowance
     * @return amount If successful, returns true
     */
    function bridgeBurn(
        address account,
        uint256 amount
    ) public onlyAdmin returns (bool) {
        // H-02 fix: Only allow burning from contract itself or with allowance
        if (account != address(this)) {
            uint256 currentAllowance = allowance(account, msg.sender);
            if (currentAllowance < amount) {
                revert InsufficientAllowance();
            }
            _approve(account, msg.sender, currentAllowance - amount);
        }
        _burn(account, amount);
        emit BridgeBurn(account, amount);
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINTER MANAGEMENT - C-03 fix
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @dev Grant minter role to an address
     */
    function grantMinter(address minter) public onlyAdmin {
        _grantRole(MINTER_ROLE, minter);
        emit MinterGranted(minter);
    }

    /**
     * @dev Revoke minter role from an address
     */
    function revokeMinter(address minter) public onlyAdmin {
        _revokeRole(MINTER_ROLE, minter);
        emit MinterRevoked(minter);
    }

    /**
     * @dev Set daily mint limit
     */
    function setDailyMintLimit(uint256 limit) public onlyAdmin {
        dailyMintLimit = limit;
        emit DailyMintLimitSet(limit);
    }

    /**
     * @dev Override _msgSender for OZ AccessControl/Ownable and LRC20 compatibility
     */
    function _msgSender() internal view override returns (address) {
        return msg.sender;
    }
}
