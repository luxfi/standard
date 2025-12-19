// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {
    IProposerAdapterBaseV1
} from "../interfaces/dao/deployables/IProposerAdapterBaseV1.sol";

contract MockProposerAdapter is IProposerAdapterBaseV1 {
    mapping(address => bool) private _isProposer;

    function isProposer(
        address _proposer,
        bytes calldata
    ) external view override returns (bool) {
        return _isProposer[_proposer];
    }

    // Mock-specific functions for test setup
    function setProposerStatus(address _proposer, bool status) external {
        _isProposer[_proposer] = status;
    }
}
