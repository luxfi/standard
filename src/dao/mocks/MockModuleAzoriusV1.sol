// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IModuleAzoriusV1,
    Transaction
} from "../interfaces/dao/deployables/IModuleAzoriusV1.sol";
import {Enum} from "./safe-smart-account/common/Enum.sol";

contract MockModuleAzoriusV1 is IModuleAzoriusV1 {
    address public currentStrategy;
    uint32 public currentTimelockPeriod;
    uint32 public currentExecutionPeriod;
    uint32 public currentTotalProposalCount;
    mapping(uint32 => Proposal) public proposalsMap;

    constructor() {}

    function initialize(
        address /* owner_ */,
        address /* avatar_ */,
        address /* target_ */,
        address strategy_,
        uint32 timelockPeriod_,
        uint32 executionPeriod_
    ) external virtual {
        currentStrategy = strategy_;
        currentTimelockPeriod = timelockPeriod_;
        currentExecutionPeriod = executionPeriod_;
    }

    function setUp(bytes memory) external virtual {}

    function totalProposalCount()
        external
        view
        virtual
        override
        returns (uint32)
    {
        return currentTotalProposalCount;
    }

    function timelockPeriod() external view virtual override returns (uint32) {
        return currentTimelockPeriod;
    }

    function executionPeriod() external view virtual override returns (uint32) {
        return currentExecutionPeriod;
    }

    function proposals(
        uint32 proposalId_
    ) external view virtual override returns (Proposal memory) {
        return proposalsMap[proposalId_];
    }

    function strategy() external view virtual override returns (address) {
        return currentStrategy;
    }

    function updateTimelockPeriod(uint32) external virtual override {}

    function updateExecutionPeriod(uint32) external virtual override {}

    function updateStrategy(address strategy_) external virtual override {
        currentStrategy = strategy_;
    }

    function submitProposal(
        Transaction[] calldata,
        string calldata,
        address,
        bytes calldata
    ) external virtual override {}

    function executeProposal(
        uint32,
        Transaction[] calldata
    ) external virtual override {}

    function getProposalTxHash(
        uint32,
        uint32
    ) external view virtual override returns (bytes32) {
        return bytes32(0);
    }

    function getProposalTxHashes(
        uint32
    ) external view virtual override returns (bytes32[] memory) {
        bytes32[] memory empty;
        return empty;
    }

    function getProposal(
        uint32 proposalId_
    )
        external
        view
        virtual
        override
        returns (address, bytes32[] memory, uint32, uint32, uint32)
    {
        Proposal memory p = proposalsMap[proposalId_];
        return (
            p.strategy,
            p.txHashes,
            p.timelockPeriod,
            p.executionPeriod,
            p.executionCounter
        );
    }

    function proposalState(
        uint32
    ) public view virtual override returns (ProposalState) {
        return ProposalState.ACTIVE; // Default mock state
    }

    function generateTxHashData(
        Transaction calldata,
        uint256
    ) public view virtual override returns (bytes memory) {
        return bytes("");
    }

    function getTxHash(
        Transaction calldata
    ) public view virtual override returns (bytes32) {
        return keccak256(bytes("mockHash"));
    }
}
