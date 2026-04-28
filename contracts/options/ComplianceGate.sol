// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@luxfi/oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@luxfi/oz/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@luxfi/oz/utils/ReentrancyGuard.sol";
import { AccessControl } from "@luxfi/oz/access/AccessControl.sol";
import { Pausable } from "@luxfi/oz/utils/Pausable.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import { IIdentity } from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";
import { Options } from "./Options.sol";
import { OptionsRouter } from "./OptionsRouter.sol";
import { IComplianceGate } from "../interfaces/options/IComplianceGate.sol";
import { IOptionsRouter } from "../interfaces/options/IOptionsRouter.sol";

contract ComplianceGate is IComplianceGate, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    Options public immutable options;
    IIdentityRegistry private _identityRegistry;
    uint256 public accreditationTopic;

    mapping(uint256 => bool) public override accreditedOnly;
    mapping(uint16 => bool) public blockedCountries;

    constructor(address _options, address _registry, address _admin, uint256 _accreditationTopic) {
        if (_options == address(0)) revert InvalidRegistry();
        if (_registry == address(0)) revert InvalidRegistry();
        if (_admin == address(0)) revert InvalidRegistry();

        options = Options(_options);
        _identityRegistry = IIdentityRegistry(_registry);
        accreditationTopic = _accreditationTopic;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    modifier onlyCompliant(address user) {
        if (!_identityRegistry.isVerified(user)) revert NotCompliant(user);
        uint16 country = _identityRegistry.investorCountry(user);
        if (blockedCountries[country]) revert CountryBlocked(user, country);
        _;
    }

    modifier onlyAccreditedIfRequired(address user, uint256 seriesId) {
        if (accreditedOnly[seriesId] && !_isAccredited(user)) revert NotAccredited(user);
        _;
    }

    function _isAccredited(address user) internal view returns (bool) {
        if (accreditationTopic == 0) return true;
        IIdentity id = _identityRegistry.identity(user);
        if (address(id) == address(0)) return false;
        bytes32[] memory claimIds = id.getClaimIdsByTopic(accreditationTopic);
        return claimIds.length > 0;
    }

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

        address collateralToken = series.optionType == Options.OptionType.CALL ? series.underlying : series.quote;

        uint256 calcCollateral = options.calculateCollateral(seriesId, amount);
        uint256 fee = (calcCollateral * options.writeFeeBps()) / options.BPS();
        uint256 totalNeeded = calcCollateral + fee;

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), totalNeeded);
        IERC20(collateralToken).approve(address(options), totalNeeded);
        collateralRequired = options.write(seriesId, amount, recipient);

        uint256 remaining = IERC20(collateralToken).balanceOf(address(this));
        if (remaining > 0) IERC20(collateralToken).safeTransfer(msg.sender, remaining);
    }

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

        options.safeTransferFrom(msg.sender, address(this), seriesId, amount, "");
        payout = options.exercise(seriesId, amount);

        address payoutToken = series.settlement == Options.SettlementType.CASH
            ? series.quote
            : (series.optionType == Options.OptionType.CALL ? series.underlying : series.quote);

        if (payout > 0) IERC20(payoutToken).safeTransfer(msg.sender, payout);
    }

    function executeStrategyCompliant(
        OptionsRouter router,
        IOptionsRouter.StrategyType strategyType,
        IOptionsRouter.Leg[] calldata legs,
        uint256 netPremiumLimit
    ) external nonReentrant whenNotPaused onlyCompliant(msg.sender) returns (uint256 positionId) {
        for (uint256 i; i < legs.length; ++i) {
            if (accreditedOnly[legs[i].seriesId] && !_isAccredited(msg.sender)) {
                revert NotAccredited(msg.sender);
            }
        }
        positionId = router.executeStrategy(strategyType, legs, netPremiumLimit);
    }

    function isCompliantForSeries(address user, uint256 seriesId) external view returns (bool) {
        if (!_identityRegistry.isVerified(user)) return false;
        if (blockedCountries[_identityRegistry.investorCountry(user)]) return false;
        if (accreditedOnly[seriesId] && !_isAccredited(user)) return false;
        return true;
    }

    function identityRegistry() external view override returns (address) {
        return address(_identityRegistry);
    }

    function setIdentityRegistry(address registry) external onlyRole(ADMIN_ROLE) {
        if (registry == address(0)) revert InvalidRegistry();
        address old = address(_identityRegistry);
        _identityRegistry = IIdentityRegistry(registry);
        emit IdentityRegistryUpdated(old, registry);
    }

    function setAccreditedOnly(uint256 seriesId, bool required) external onlyRole(ADMIN_ROLE) {
        accreditedOnly[seriesId] = required;
        emit AccreditedOnlySet(seriesId, required);
    }

    function setCountryBlock(uint16 country, bool blocked) external onlyRole(ADMIN_ROLE) {
        blockedCountries[country] = blocked;
        emit CountryBlockSet(country, blocked);
    }

    function setAccreditationTopic(uint256 topic) external onlyRole(ADMIN_ROLE) {
        accreditationTopic = topic;
        emit AccreditationTopicSet(topic);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
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
