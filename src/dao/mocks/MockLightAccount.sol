// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {ILightAccount} from "../interfaces/light-account/ILightAccount.sol";
import {IStrategyV1} from "../interfaces/dao/deployables/IStrategyV1.sol";
import {IVotingTypes} from "../interfaces/dao/deployables/IVotingTypes.sol";

contract MockLightAccount is ILightAccount {
    address private _owner;

    constructor(address initialOwner) {
        _owner = initialOwner;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function setOwner(address newOwner) external {
        _owner = newOwner;
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external override {}

    // New function to interact with StrategyV1
    function callStrategyVote(
        IStrategyV1 strategy,
        uint32 proposalId,
        uint8 voteType,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData,
        uint128 lightAccountIndex
    ) external {
        // msg.sender here is the EOA calling MockLightAccount (e.g., relayer)
        // When strategy.vote is called, msg.sender from StrategyV1's perspective will be address(this)
        strategy.castVote(
            proposalId,
            voteType,
            votingConfigsData,
            lightAccountIndex
        );
    }

    // Function specifically for freeze voting tests via smart account
    function executeFreezeVote(
        address targetFreezeVoting,
        bytes calldata callDataForFreezeVote
    ) external {
        (bool success, ) = targetFreezeVoting.call(callDataForFreezeVote);
        if (!success) {
            // Bubble up the revert reason from the low-level call
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
    }
}
