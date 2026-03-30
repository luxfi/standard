// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Options } from "./Options.sol";
import { OptionsRouter } from "./OptionsRouter.sol";
import { IComplianceGate } from "../interfaces/options/IComplianceGate.sol";
import { IOptionsRouter } from "../interfaces/options/IOptionsRouter.sol";

// Import the existing ComplianceRegistry from the securities module
import { ComplianceRegistry } from "../securities/compliance/ComplianceRegistry.sol";

/**
 * @title ComplianceGate
 * @author Lux Industries
 * @notice KYC/AML compliance wrapper that gates all options operations
 * @dev Checks users against the existing ComplianceRegistry from the securities module.
 *      Supports per-series accredited-only restrictions and jurisdiction blocking.
 *      Does NOT inherit from Options — it composes with it, wrapping calls.
 *
 * Usage:
 * 1. Deploy ComplianceGate with Options contract and ComplianceRegistry addresses
 * 2. Users call writeCompliant() and exerciseCompliant() instead of Options directly
 * 3. Admins can set per-series accreditation requirements and jurisdiction blocks
 */
contract ComplianceGate is IComplianceGate, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Accreditation status value that qualifies as "accredited"
    uint8 public constant ACCREDITED_STATUS = 1;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Options contract being gated
    Options public immutable options;

    /// @notice Compliance registry for KYC/AML checks
    ComplianceRegistry private _complianceRegistry;

    /// @notice Per-series accredited-only flag
    mapping(uint256 => bool) public override accreditedOnly;

    /// @notice Blocked jurisdictions
    mapping(bytes2 => bool) public blockedJurisdictions;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _options, address _registry, address _admin) {
        if (_options == address(0)) revert InvalidRegistry();
        if (_registry == address(0)) revert InvalidRegistry();
        if (_admin == address(0)) revert InvalidRegistry();

        options = Options(_options);
        _complianceRegistry = ComplianceRegistry(_registry);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyCompliant(address user) {
        if (!_complianceRegistry.isApproved(user)) revert NotCompliant(user);

        bytes2 juris = _complianceRegistry.jurisdiction(user);
        if (juris != bytes2(0) && blockedJurisdictions[juris]) {
            revert JurisdictionBlocked(user, juris);
        }
        _;
    }

    modifier onlyAccreditedIfRequired(address user, uint256 seriesId) {
        if (accreditedOnly[seriesId]) {
            uint8 status = _complianceRegistry.accreditationStatus(user);
            if (status < ACCREDITED_STATUS) revert NotAccredited(user);
        }
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GATED OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IComplianceGate
    function writeCompliant(uint256 seriesId, uint256 amount, address recipient)
        external
        nonReentrant
        whenNotPaused
        onlyCompliant(msg.sender)
        onlyCompliant(recipient)
        onlyAccreditedIfRequired(msg.sender, seriesId)
        onlyAccreditedIfRequired(recipient, seriesId)
        returns (uint256 collateralRequired)
    {
        Options.OptionSeries memory series = options.getSeries(seriesId);
        if (!series.exists) revert SeriesNotFound(seriesId);

        // Determine collateral token and amount (including fee)
        address collateralToken = series.optionType == Options.OptionType.CALL
            ? series.underlying
            : series.quote;

        uint256 calcCollateral = options.calculateCollateral(seriesId, amount);
        uint256 fee = (calcCollateral * options.writeFeeBps()) / options.BPS();
        uint256 totalNeeded = calcCollateral + fee;

        // Pull collateral from user to this contract
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), totalNeeded);

        // Approve Options contract and write
        IERC20(collateralToken).approve(address(options), totalNeeded);
        collateralRequired = options.write(seriesId, amount, recipient);

        // Return any excess to caller
        uint256 remaining = IERC20(collateralToken).balanceOf(address(this));
        if (remaining > 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, remaining);
        }
    }

    /// @inheritdoc IComplianceGate
    function exerciseCompliant(uint256 seriesId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyCompliant(msg.sender)
        onlyAccreditedIfRequired(msg.sender, seriesId)
        returns (uint256 payout)
    {
        Options.OptionSeries memory series = options.getSeries(seriesId);
        if (!series.exists) revert SeriesNotFound(seriesId);

        // Transfer user's option tokens to this contract (user must setApprovalForAll first)
        options.safeTransferFrom(msg.sender, address(this), seriesId, amount, "");

        // Exercise on behalf of this contract (which now holds the tokens)
        payout = options.exercise(seriesId, amount);

        // Forward payout to user
        address payoutToken = series.settlement == Options.SettlementType.CASH
            ? series.quote
            : (series.optionType == Options.OptionType.CALL ? series.underlying : series.quote);

        if (payout > 0) {
            IERC20(payoutToken).safeTransfer(msg.sender, payout);
        }
    }

    /**
     * @notice Execute a strategy through the router with compliance checks
     * @param router OptionsRouter contract
     * @param strategyType Strategy type
     * @param legs Strategy legs
     * @param netPremiumLimit Maximum net premium
     * @return positionId Strategy position ID
     */
    function executeStrategyCompliant(
        OptionsRouter router,
        IOptionsRouter.StrategyType strategyType,
        IOptionsRouter.Leg[] calldata legs,
        uint256 netPremiumLimit
    )
        external
        nonReentrant
        whenNotPaused
        onlyCompliant(msg.sender)
        returns (uint256 positionId)
    {
        // Check accreditation for all series in the strategy
        for (uint256 i; i < legs.length; ++i) {
            if (accreditedOnly[legs[i].seriesId]) {
                uint8 status = _complianceRegistry.accreditationStatus(msg.sender);
                if (status < ACCREDITED_STATUS) revert NotAccredited(msg.sender);
                break; // Only need to check once per user
            }
        }

        positionId = router.executeStrategy(strategyType, legs, netPremiumLimit);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IComplianceGate
    function isCompliantForSeries(address user, uint256 seriesId) external view returns (bool) {
        // Must be approved (whitelisted, not blacklisted)
        if (!_complianceRegistry.isApproved(user)) return false;

        // Jurisdiction check
        bytes2 juris = _complianceRegistry.jurisdiction(user);
        if (juris != bytes2(0) && blockedJurisdictions[juris]) return false;

        // Accreditation check
        if (accreditedOnly[seriesId]) {
            if (_complianceRegistry.accreditationStatus(user) < ACCREDITED_STATUS) return false;
        }

        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IComplianceGate
    function complianceRegistry() external view override returns (address) {
        return address(_complianceRegistry);
    }

    /// @inheritdoc IComplianceGate
    function setComplianceRegistry(address registry) external onlyRole(ADMIN_ROLE) {
        if (registry == address(0)) revert InvalidRegistry();
        address old = address(_complianceRegistry);
        _complianceRegistry = ComplianceRegistry(registry);
        emit ComplianceRegistryUpdated(old, registry);
    }

    /// @inheritdoc IComplianceGate
    function setAccreditedOnly(uint256 seriesId, bool required) external onlyRole(ADMIN_ROLE) {
        accreditedOnly[seriesId] = required;
        emit AccreditedOnlySet(seriesId, required);
    }

    /// @inheritdoc IComplianceGate
    function setJurisdictionBlock(bytes2 jurisdiction, bool blocked) external onlyRole(ADMIN_ROLE) {
        blockedJurisdictions[jurisdiction] = blocked;
        emit JurisdictionBlockSet(jurisdiction, blocked);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC1155 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
