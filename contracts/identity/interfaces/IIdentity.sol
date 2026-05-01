// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { IERC734 } from "./IERC734.sol";
import { IERC735 } from "./IERC735.sol";

/// @title IIdentity — combined ERC-734 + ERC-735 (ONCHAINID).
interface IIdentity is IERC734, IERC735 {
    function isClaimValid(
        IIdentity _identity,
        uint256 claimTopic,
        bytes calldata sig,
        bytes calldata data
    ) external view returns (bool);
}
