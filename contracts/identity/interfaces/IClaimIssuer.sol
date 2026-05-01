// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { IIdentity } from "./IIdentity.sol";

/// @title IClaimIssuer — issuer-side ONCHAINID with revocation surface.
interface IClaimIssuer is IIdentity {
    event ClaimRevoked(bytes indexed signature);

    function revokeClaim(bytes32 _claimId, address _identity) external returns (bool);
    function revokeClaimBySignature(bytes calldata signature) external;
    function isClaimRevoked(bytes calldata _sig) external view returns (bool);

    function isClaimValid(
        IIdentity _identity,
        uint256 claimTopic,
        bytes calldata sig,
        bytes calldata data
    ) external view returns (bool);
}
