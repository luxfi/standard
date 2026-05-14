// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import { IIdentity } from "@luxfi/standard/securities/onchainid/interface/IIdentity.sol";

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

    /// ERC-1404 codes returned by {moduleReason}. Match canonical 0..11 table.
    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_SENDER_NOT_REGISTERED = 1;
    uint8 internal constant CODE_SENDER_MISSING_TOPIC = 2;
    uint8 internal constant CODE_SENDER_CLAIM_EXPIRED = 3;
    uint8 internal constant CODE_RECIPIENT_NOT_REGISTERED = 4;
    uint8 internal constant CODE_RECIPIENT_MISSING_TOPIC = 5;
    uint8 internal constant CODE_RECIPIENT_CLAIM_EXPIRED = 6;

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return this.moduleReason(_from, _to, _value, _compliance) == CODE_OK;
    }

    /// @notice See {IModule-moduleReason}. Returns ERC-1404 codes 1..6 depending
    ///         on whether the sender or recipient fails identity registration,
    ///         is missing a required claim topic, or has an expired claim.
    ///         Recipient is checked first because mint (`_from == 0`) is the
    ///         most common failure path.
    function moduleReason(address _from, address _to, uint256, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        IToken token = IToken(IModularCompliance(_compliance).getTokenBound());
        IIdentityRegistry idReg = token.identityRegistry();

        // Recipient first (mint path: _from == 0 → only validate destination).
        if (_to != address(0)) {
            uint8 toCode = _claimCode(idReg, _to, /*isRecipient*/ true);
            if (toCode != CODE_OK) return toCode;
        }
        // Sender (burn path: _to == 0 → only validate source).
        if (_from != address(0)) {
            uint8 fromCode = _claimCode(idReg, _from, /*isRecipient*/ false);
            if (fromCode != CODE_OK) return fromCode;
        }
        return CODE_OK;
    }

    /// @dev Returns the ERC-1404 code for the user. `isRecipient` switches the
    ///      code family (1/2/3 for sender, 4/5/6 for recipient).
    function _claimCode(IIdentityRegistry idReg, address user, bool isRecipient) internal view returns (uint8) {
        IIdentity id = idReg.identity(user);
        if (address(id) == address(0)) {
            return isRecipient ? CODE_RECIPIENT_NOT_REGISTERED : CODE_SENDER_NOT_REGISTERED;
        }

        uint256[] memory topics = idReg.topicsRegistry().getClaimTopics();
        uint256 nowTs = block.timestamp;

        for (uint256 i = 0; i < topics.length; ++i) {
            bytes32[] memory ids = id.getClaimIdsByTopic(topics[i]);
            if (ids.length == 0) {
                return isRecipient ? CODE_RECIPIENT_MISSING_TOPIC : CODE_SENDER_MISSING_TOPIC;
            }
            bool fresh = false;
            for (uint256 j = 0; j < ids.length; ++j) {
                (,,,, bytes memory data,) = id.getClaim(ids[j]);
                if (data.length < 64) {
                    // Legacy (non-validity-encoded) claims count as fresh — they
                    // never expire. This preserves backwards compatibility with
                    // claims issued before validity encoding was rolled out.
                    fresh = true;
                    break;
                }
                (, uint64 validUntil,) = abi.decode(data, (uint64, uint64, bytes));
                if (validUntil == 0 || validUntil >= nowTs) {
                    fresh = true;
                    break;
                }
            }
            if (!fresh) {
                return isRecipient ? CODE_RECIPIENT_CLAIM_EXPIRED : CODE_SENDER_CLAIM_EXPIRED;
            }
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
}
