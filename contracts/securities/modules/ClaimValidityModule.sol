// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/erc-3643/contracts/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/erc-3643/contracts/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/erc-3643/contracts/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/erc-3643/contracts/registry/interface/IIdentityRegistry.sol";
import { IIdentity } from "@luxfi/onchain-id/contracts/interface/IIdentity.sol";

/// @title ClaimValidityModule
/// @notice T-REX `IModule` that gates transfers on per-topic claim expiry.
///         Stock T-REX only checks that a claim *exists*; this module
///         decodes `Claim.data = abi.encode(uint64 issuedAt, uint64 validUntil, bytes proof)`
///         and rejects expired claims at transfer time.
/// @dev    Required-topic set is read from the token's `IdentityRegistry`
///         `topicsRegistry().getClaimTopics()`. For each required topic the
///         module looks up `getClaimIdsByTopic(topic)` on the recipient's
///         ONCHAINID and validates `validUntil`. `validUntil == 0` means
///         "never expires" (only valid for topic 6 AFFILIATE).
contract ClaimValidityModule is AbstractModule {
    string private constant _NAME = "ClaimValidityModule";

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256, address _compliance)
        external
        view
        override
        returns (bool)
    {
        IToken token = IToken(IModularCompliance(_compliance).getTokenBound());
        IIdentityRegistry idReg = token.identityRegistry();

        // Mint path (_from == 0) — only validate destination.
        if (_to != address(0)) {
            if (!_validateClaims(idReg, _to)) return false;
        }
        // Burn path (_to == 0) — only validate source.
        if (_from != address(0)) {
            if (!_validateClaims(idReg, _from)) return false;
        }
        return true;
    }

    function _validateClaims(IIdentityRegistry idReg, address user) internal view returns (bool) {
        IIdentity id = idReg.identity(user);
        if (address(id) == address(0)) return false;

        uint256[] memory topics = idReg.topicsRegistry().getClaimTopics();
        uint256 nowTs = block.timestamp;

        for (uint256 i = 0; i < topics.length; ++i) {
            bytes32[] memory ids = id.getClaimIdsByTopic(topics[i]);
            bool found = false;
            for (uint256 j = 0; j < ids.length; ++j) {
                (,,,, bytes memory data,) = id.getClaim(ids[j]);
                if (data.length < 64) continue; // not validity-encoded — skip
                (, uint64 validUntil,) = abi.decode(data, (uint64, uint64, bytes));
                if (validUntil == 0 || validUntil >= nowTs) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
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
}
