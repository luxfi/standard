// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";

/// @title JurisdictionAllowListModule
/// @notice ERC-3643 compliance module that gates transfers by recipient (and
///         optionally sender) jurisdiction. Holder country is read from
///         `IdentityRegistry.investorCountry(wallet)` (ISO 3166-1 numeric,
///         uint16). A transfer passes only when the recipient's country is on
///         this compliance's allow-list. Use for offerings restricted to a
///         specific set of jurisdictions (e.g. US-only Reg D 506(c), QIB-only
///         Rule 144A, Reg A+ Tier 2 US offerings, etc.).
/// @dev    Pair with `JurisdictionDenyListModule` for tokens that need both an
///         allow gate (positive eligibility) AND a deny gate (sanctioned-
///         country block). Allow-list is enforced AFTER deny-list — composition
///         is: deny module rejects sanctioned, allow module rejects non-listed.
///         For tokens with no jurisdiction restriction, leave the allow-list
///         empty AND don't bind this module.
contract JurisdictionAllowListModule is AbstractModule {
    string private constant _NAME = "JurisdictionAllowListModule";

    /// ERC-1404 code returned by {moduleReason} when blocked.
    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_REGION_RESTRICTED = 7;

    /// Per-compliance allow-list as a country-keyed flag map. Iteration uses a
    /// separate dynamic array for getters (gas-cheap to read full list).
    mapping(address compliance => mapping(uint16 country => bool)) public isAllowed;
    mapping(address compliance => uint16[]) internal _allowedList;

    event CountryAllowed(address indexed compliance, uint16 indexed country);
    event CountryRevoked(address indexed compliance, uint16 indexed country);
    event AllowListReplaced(address indexed compliance, uint16[] countries);

    /// @notice Replace the allow-list wholesale. Callable only by the
    ///         compliance owner. Clears existing entries first.
    function setAllowedCountries(address compliance, uint16[] calldata countries) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        // Clear old entries.
        uint16[] storage old = _allowedList[compliance];
        for (uint256 i = 0; i < old.length; i++) {
            isAllowed[compliance][old[i]] = false;
        }
        delete _allowedList[compliance];
        // Install new entries.
        for (uint256 i = 0; i < countries.length; i++) {
            if (!isAllowed[compliance][countries[i]]) {
                isAllowed[compliance][countries[i]] = true;
                _allowedList[compliance].push(countries[i]);
            }
        }
        emit AllowListReplaced(compliance, countries);
    }

    /// @notice Add or remove a single country from the allow-list.
    function setCountryAllowed(address compliance, uint16 country, bool allowed) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        if (allowed && !isAllowed[compliance][country]) {
            isAllowed[compliance][country] = true;
            _allowedList[compliance].push(country);
            emit CountryAllowed(compliance, country);
        } else if (!allowed && isAllowed[compliance][country]) {
            isAllowed[compliance][country] = false;
            uint16[] storage list = _allowedList[compliance];
            for (uint256 i = 0; i < list.length; i++) {
                if (list[i] == country) {
                    list[i] = list[list.length - 1];
                    list.pop();
                    break;
                }
            }
            emit CountryRevoked(compliance, country);
        }
    }

    /// @notice Get the current allow-list (gas-cheap view for off-chain UIs).
    function getAllowedCountries(address compliance) external view returns (uint16[] memory) {
        return _allowedList[compliance];
    }

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return this.moduleReason(_from, _to, _value, _compliance) == CODE_OK;
    }

    /// @notice See {IModule-moduleReason}. Returns code 7 (Region restricted)
    ///         when the recipient's country (or sender's, for non-mint) is not
    ///         on the allow-list. An empty allow-list means "allow nothing" —
    ///         that's a feature for emergency lockdown via setAllowedCountries([]).
    function moduleReason(address _from, address _to, uint256, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        IToken securityToken = IToken(IModularCompliance(_compliance).getTokenBound());
        IIdentityRegistry idReg = securityToken.identityRegistry();

        // Recipient first (mint path: _from == 0 → only validate destination).
        if (_to != address(0)) {
            uint16 toCountry = idReg.investorCountry(_to);
            if (!isAllowed[_compliance][toCountry]) return CODE_REGION_RESTRICTED;
        }
        // Sender (burn path: _to == 0 → only validate source).
        if (_from != address(0)) {
            uint16 fromCountry = idReg.investorCountry(_from);
            if (!isAllowed[_compliance][fromCountry]) return CODE_REGION_RESTRICTED;
        }
        return CODE_OK;
    }

    function moduleTransferAction(address, address, uint256) external override onlyComplianceCall { }
    function moduleMintAction(address, uint256) external override onlyComplianceCall { }
    function moduleBurnAction(address, uint256) external override onlyComplianceCall { }

    function canComplianceBind(address) external pure override returns (bool) {
        return true;
    }

    function isPlugAndPlay() external pure override returns (bool) {
        return true;
    }

    function name() external pure override returns (string memory) {
        return _NAME;
    }

    function _complianceOwner(address compliance) internal view returns (address) {
        (bool ok, bytes memory ret) = compliance.staticcall(abi.encodeWithSignature("owner()"));
        require(ok && ret.length >= 32, "owner() unavailable");
        return abi.decode(ret, (address));
    }
}
