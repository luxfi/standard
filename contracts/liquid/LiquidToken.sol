// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {LRC20} from "../tokens/LRC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "./base/Errors.sol";
import {IERC3156FlashBorrower} from "./interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "./interfaces/IERC3156FlashLender.sol";

/// @title LiquidToken
/// @author Lux Industries Inc
/// @notice Base contract for Lux liquid tokens (LUSD, LETH, LBTC)
/// @dev Mintable tokens with flash loan support and role-based access
/// @custom:security-contact security@lux.network
contract LiquidToken is AccessControl, ReentrancyGuard, LRC20, IERC3156FlashLender {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Admin role - can manage other roles and settings
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    /// @notice Sentinel role - can pause minting for specific addresses
    bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL");

    /// @notice Expected return value from flash borrower
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice Basis points denominator (100% = 10000)
    uint256 public constant BPS = 10000;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Addresses whitelisted to mint tokens (vaults, bridges)
    mapping(address => bool) public whitelisted;

    /// @notice Addresses paused from minting
    mapping(address => bool) public paused;

    /// @notice Flash mint fee in basis points
    uint256 public flashMintFee;

    /// @notice Maximum flash loan amount
    uint256 public maxFlashLoanAmount;

    /// @notice Fee recipient address
    address public feeRecipient;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Paused(address indexed minter, bool state);
    event SetFlashMintFee(uint256 fee);
    event SetMaxFlashLoan(uint256 amount);
    event Whitelisted(address indexed minter, bool state);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _flashFee
    ) LRC20(_name, _symbol) {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SENTINEL_ROLE, msg.sender);
        _setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        flashMintFee = _flashFee;
        feeRecipient = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════

    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlySentinel() {
        if (!hasRole(SENTINEL_ROLE, msg.sender)) revert Unauthorized();
        _;
    }

    modifier onlyWhitelisted() {
        if (!whitelisted[msg.sender]) revert Unauthorized();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set flash mint fee
    function setFlashFee(uint256 newFee) external onlyAdmin {
        if (newFee > BPS) revert IllegalArgument();
        flashMintFee = newFee;
        emit SetFlashMintFee(flashMintFee);
    }

    /// @notice Set max flash loan amount
    function setMaxFlashLoan(uint256 amount) external onlyAdmin {
        maxFlashLoanAmount = amount;
        emit SetMaxFlashLoan(amount);
    }

    /// @notice Set fee recipient address
    function setFeeRecipient(address recipient) external onlyAdmin {
        if (recipient == address(0)) revert IllegalArgument();
        feeRecipient = recipient;
    }

    /// @notice Whitelist an address for minting (vaults, bridges)
    function setWhitelist(address minter, bool state) external onlyAdmin {
        whitelisted[minter] = state;
        emit Whitelisted(minter, state);
    }

    /// @notice Pause minting for a specific address
    function setPaused(address minter, bool state) external onlySentinel {
        paused[minter] = state;
        emit Paused(minter, state);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MINT / BURN (Whitelisted only)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Mint tokens to recipient (only whitelisted addresses)
    function mint(address recipient, uint256 amount) external onlyWhitelisted {
        if (paused[msg.sender]) revert IllegalState();
        _mint(recipient, amount);
    }

    /// @notice Burn tokens from msg.sender
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn tokens from account (requires approval)
    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, msg.sender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert IllegalArgument();
            _approve(account, msg.sender, currentAllowance - amount);
        }
        _burn(account, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN (ERC-3156)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token_) external view override returns (uint256) {
        if (token_ != address(this)) return 0;
        return maxFlashLoanAmount;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token_, uint256 amount) public view override returns (uint256) {
        if (token_ != address(this)) revert IllegalArgument();
        return (amount * flashMintFee) / BPS;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token_,
        uint256 amount,
        bytes calldata data
    ) external override nonReentrant returns (bool) {
        if (token_ != address(this)) revert IllegalArgument();
        if (amount > maxFlashLoanAmount) revert IllegalArgument();

        uint256 fee = flashFee(token_, amount);
        
        _mint(address(receiver), amount);

        if (receiver.onFlashLoan(msg.sender, token_, amount, fee, data) != CALLBACK_SUCCESS) {
            revert IllegalState();
        }

        // Burn the loan + fee
        _burn(address(receiver), amount + fee);

        // Mint fee to fee recipient as revenue
        if (fee > 0) {
            _mint(feeRecipient, fee);
        }

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OVERRIDES (resolve AccessControl/LRC20 conflict)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Override _msgSender to resolve conflict between Context (from AccessControl) and LRC20
    function _msgSender() internal view override returns (address) {
        return msg.sender;
    }
}
