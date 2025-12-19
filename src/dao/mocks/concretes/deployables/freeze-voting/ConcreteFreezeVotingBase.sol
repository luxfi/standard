// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    FreezeVotingBase
} from "../../../../deployables/freeze-voting/FreezeVotingBase.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract ConcreteFreezeVotingBase is FreezeVotingBase, Ownable2StepUpgradeable {
    function initialize(
        address owner_,
        uint256 freezeVotesThreshold_,
        uint32 freezeProposalPeriod_,
        address lightAccountFactory_
    ) public initializer {
        __FreezeVotingBase_init(
            freezeProposalPeriod_,
            freezeVotesThreshold_,
            lightAccountFactory_
        );
        __Ownable_init(owner_);
    }

    function castFreezeVote() external {
        // If no freeze proposal exists yet, create one
        FreezeVotingBaseStorage storage $base = _getFreezeVotingBaseStorage();
        if ($base.freezeProposalCreated == 0) {
            _initializeFreezeVote();
        }

        // Check if proposal period has expired
        require(
            block.timestamp <=
                $base.freezeProposalCreated + $base.freezeProposalPeriod,
            "Freeze proposal period expired"
        );

        _recordFreezeVote(msg.sender, 1);
    }

    function unfreeze() external onlyOwner {
        FreezeVotingBaseStorage storage $ = _getFreezeVotingBaseStorage();
        $.isFrozen = false;
        $.freezeProposalCreated = 0;
        $.freezeProposalVoteCount = 0;
    }
}
