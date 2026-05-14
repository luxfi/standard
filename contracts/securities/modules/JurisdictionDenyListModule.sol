// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";

/// @title JurisdictionDenyListModule
/// @notice ERC-3643 compliance module that BLOCKS transfers where either party
///         is in a deny-listed jurisdiction. Mirror of `JurisdictionAllowListModule`
///         — used for Reg S (block US, country 840), OFAC sanctioned-country
///         lists, or any deny-by-default policy.
/// @dev    Composes with the allow-list module: deny is the absolute floor
///         (a country in deny CANNOT hold regardless of allow status), then
///         allow narrows further. Empty deny-list = no block (no-op module).
contract JurisdictionDenyListModule is AbstractModule {
    string private constant _NAME = "JurisdictionDenyListModule";

    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_REGION_RESTRICTED = 7;

    mapping(address compliance => mapping(uint16 country => bool)) public isDenied;
    mapping(address compliance => uint16[]) internal _deniedList;

    event CountryDenied(address indexed compliance, uint16 indexed country);
    event CountryUndenied(address indexed compliance, uint16 indexed country);
    event DenyListReplaced(address indexed compliance, uint16[] countries);

    function setDeniedCountries(address compliance, uint16[] calldata countries) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        uint16[] storage old = _deniedList[compliance];
        for (uint256 i = 0; i < old.length; i++) {
            isDenied[compliance][old[i]] = false;
        }
        delete _deniedList[compliance];
        for (uint256 i = 0; i < countries.length; i++) {
            if (!isDenied[compliance][countries[i]]) {
                isDenied[compliance][countries[i]] = true;
                _deniedList[compliance].push(countries[i]);
            }
        }
        emit DenyListReplaced(compliance, countries);
    }

    function setCountryDenied(address compliance, uint16 country, bool denied) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        if (denied && !isDenied[compliance][country]) {
            isDenied[compliance][country] = true;
            _deniedList[compliance].push(country);
            emit CountryDenied(compliance, country);
        } else if (!denied && isDenied[compliance][country]) {
            isDenied[compliance][country] = false;
            uint16[] storage list = _deniedList[compliance];
            for (uint256 i = 0; i < list.length; i++) {
                if (list[i] == country) {
                    list[i] = list[list.length - 1];
                    list.pop();
                    break;
                }
            }
            emit CountryUndenied(compliance, country);
        }
    }

    function getDeniedCountries(address compliance) external view returns (uint16[] memory) {
        return _deniedList[compliance];
    }

    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return this.moduleReason(_from, _to, _value, _compliance) == CODE_OK;
    }

    /// @notice Returns code 7 (Region restricted) when either party is in a
    ///         deny-listed jurisdiction.
    function moduleReason(address _from, address _to, uint256, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        IToken securityToken = IToken(IModularCompliance(_compliance).getTokenBound());
        IIdentityRegistry idReg = securityToken.identityRegistry();

        if (_to != address(0)) {
            uint16 toCountry = idReg.investorCountry(_to);
            if (isDenied[_compliance][toCountry]) return CODE_REGION_RESTRICTED;
        }
        if (_from != address(0)) {
            uint16 fromCountry = idReg.investorCountry(_from);
            if (isDenied[_compliance][fromCountry]) return CODE_REGION_RESTRICTED;
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
