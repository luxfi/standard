// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IStrategyV1} from "../interfaces/dao/deployables/IStrategyV1.sol";
import {IVotingTypes} from "../interfaces/dao/deployables/IVotingTypes.sol";
import {
    IVotingWeightV1
} from "../interfaces/dao/deployables/IVotingWeightV1.sol";
import {
    IVoteTrackerV1
} from "../interfaces/dao/deployables/IVoteTrackerV1.sol";
import {
    LightAccountValidator
} from "../deployables/account-abstraction/LightAccountValidator.sol";

contract MockVotingStrategy is IStrategyV1, LightAccountValidator {
    struct TimestampPoints {
        uint48 startTimestamp;
        uint48 endTimestamp;
    }

    address public mockStrategyAdmin;
    mapping(uint32 => ProposalVotingDetails) public proposalVotingDetailsMap;
    mapping(uint32 => uint48) public votingStartTimestampsMap;
    mapping(uint32 => uint48) public votingEndTimestampsMap;
    mapping(uint32 => uint32) public votingStartBlocksMap;
    uint256 internal _mockVotingConfigsCount;
    mapping(address => bool) internal _isProposerAdapterMap;
    IVotingTypes.VotingConfig[] internal _mockVotingConfigs;

    mapping(address => bool) internal _authorizedFreezeVotersMapping;
    address[] internal _authorizedFreezeVotersArray;

    mapping(uint32 => bool) internal _mockIsPassedMap;

    bool private _validStrategyVoteToReturn;
    bool private _shouldCheckExpectedParams;
    uint32 private _expected_proposalId;
    uint8 private _expected_voteType;
    bytes32 private _expected_votingConfigsDataHash;

    uint32 internal _mockVotingPeriod;
    uint256 internal _mockQuorumThreshold;
    uint256 internal _mockBasisNumerator;
    address[] internal _mockProposerAdapters;

    constructor(address _mockStrategyAdmin) {
        mockStrategyAdmin = _mockStrategyAdmin;
    }

    function initialize(
        uint32 votingPeriod_,
        uint256 quorumThreshold_,
        uint256 basisNumerator_,
        address[] calldata proposerAdapters_,
        address lightAccountFactory_
    ) external override {
        _mockVotingPeriod = votingPeriod_;
        _mockQuorumThreshold = quorumThreshold_;
        _mockBasisNumerator = basisNumerator_;
        _mockProposerAdapters = proposerAdapters_;

        for (uint i = 0; i < proposerAdapters_.length; i++) {
            _isProposerAdapterMap[proposerAdapters_[i]] = true;
        }
        __LightAccountValidator_init(lightAccountFactory_);
    }

    function initialize2(
        address strategyAdmin_,
        IVotingTypes.VotingConfig[] calldata votingConfigs_
    ) external override {
        mockStrategyAdmin = strategyAdmin_;
        // Store voting configs
        delete _mockVotingConfigs;
        for (uint i = 0; i < votingConfigs_.length; i++) {
            _mockVotingConfigs.push(votingConfigs_[i]);
        }
        _mockVotingConfigsCount = votingConfigs_.length;
    }

    function strategyAdmin() external view override returns (address) {
        return mockStrategyAdmin;
    }

    function votingPeriod() external view override returns (uint32) {
        return _mockVotingPeriod;
    }

    function quorumThreshold() external view override returns (uint256) {
        return _mockQuorumThreshold;
    }

    function basisNumerator() external view override returns (uint256) {
        return _mockBasisNumerator;
    }

    function proposalVotingDetails(
        uint32 proposalId
    ) external view override returns (ProposalVotingDetails memory) {
        return proposalVotingDetailsMap[proposalId];
    }

    function votingConfigs()
        external
        view
        override
        returns (IVotingTypes.VotingConfig[] memory)
    {
        return _mockVotingConfigs;
    }

    function votingConfig(
        uint256 configIndex_
    ) external view override returns (IVotingTypes.VotingConfig memory) {
        require(
            configIndex_ < _mockVotingConfigs.length,
            "Invalid config index"
        );
        return _mockVotingConfigs[configIndex_];
    }

    function proposerAdapters()
        external
        view
        override
        returns (address[] memory)
    {
        return _mockProposerAdapters;
    }

    function isProposerAdapter(
        address pa
    ) external view override returns (bool) {
        return _isProposerAdapterMap[pa];
    }

    function setVotingTimestamps(
        uint32 proposalId,
        uint48 startTime,
        uint48 endTime
    ) external {
        votingStartTimestampsMap[proposalId] = startTime;
        votingEndTimestampsMap[proposalId] = endTime;
        proposalVotingDetailsMap[proposalId].votingStartTimestamp = startTime;
        proposalVotingDetailsMap[proposalId].votingEndTimestamp = endTime;
    }

    function setVotingStartBlock(
        uint32 proposalId,
        uint32 startBlock
    ) external {
        votingStartBlocksMap[proposalId] = startBlock;
        proposalVotingDetailsMap[proposalId].votingStartBlock = startBlock;
    }

    function getVotingTimestamps(
        uint32 proposalId
    ) external view override returns (uint48 startTime, uint48 endTime) {
        return (
            votingStartTimestampsMap[proposalId],
            votingEndTimestampsMap[proposalId]
        );
    }

    function getVotingStartBlock(
        uint32 proposalId
    ) external view override returns (uint32 votingStartBlock) {
        return votingStartBlocksMap[proposalId];
    }

    function initializeProposal(uint32 proposalId) external virtual override {
        ProposalVotingDetails storage proposal = proposalVotingDetailsMap[
            proposalId
        ];

        proposal.votingStartTimestamp = uint48(block.timestamp);
        proposal.votingEndTimestamp = uint48(
            block.timestamp + _mockVotingPeriod
        );
        proposal.votingStartBlock = uint32(block.number);

        votingStartTimestampsMap[proposalId] = proposal.votingStartTimestamp;
        votingEndTimestampsMap[proposalId] = proposal.votingEndTimestamp;

        emit ProposalInitialized(
            proposalId,
            proposal.votingStartTimestamp,
            proposal.votingEndTimestamp,
            proposal.votingStartBlock
        );
    }

    function castVote(
        uint32 _proposalId,
        uint8 _voteType,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData,
        uint256 lightAccountIndex_
    ) external virtual override {
        address resolvedLightAccountOwner = potentialLightAccountResolvedOwner(
            msg.sender,
            lightAccountIndex_
        );
        ProposalVotingDetails storage proposal = proposalVotingDetailsMap[
            _proposalId
        ];
        uint256 totalWeight = 0;
        // Mock implementation - just add a fixed weight per config
        for (uint i = 0; i < votingConfigsData.length; i++) {
            totalWeight += 100; // Fixed weight for testing
        }
        if (_voteType == uint8(VoteType.YES)) proposal.yesVotes += totalWeight;
        else if (_voteType == uint8(VoteType.NO))
            proposal.noVotes += totalWeight;
        else if (_voteType == uint8(VoteType.ABSTAIN))
            proposal.abstainVotes += totalWeight;
        emit Voted(
            resolvedLightAccountOwner,
            _proposalId,
            VoteType(_voteType),
            totalWeight
        );
    }

    function isPassed(
        uint32 _proposalId
    ) external view override returns (bool) {
        return _mockIsPassedMap[_proposalId];
    }

    function setIsPassed(uint32 proposalId, bool passed) external {
        _mockIsPassedMap[proposalId] = passed;
    }

    function setValidStrategyVoteResult(bool result) external {
        _validStrategyVoteToReturn = result;
        _shouldCheckExpectedParams = false;
    }

    function setExpectedValidStrategyVoteParams(
        uint32 expectedProposalId,
        uint8 expectedVoteType,
        IVotingTypes.VotingConfigVoteData[] calldata expectedVotingConfigsData
    ) external {
        _expected_proposalId = expectedProposalId;
        _expected_voteType = expectedVoteType;
        _expected_votingConfigsDataHash = keccak256(
            abi.encode(expectedVotingConfigsData)
        );
        _shouldCheckExpectedParams = true;
    }

    function isQuorumMet(uint32) external pure override returns (bool) {
        return true;
    }

    function isBasisMet(uint32) external pure override returns (bool) {
        return true;
    }

    function isProposer(
        address address_,
        address,
        bytes calldata
    ) external view virtual override returns (bool) {
        return address_ == mockStrategyAdmin;
    }

    function addAuthorizedFreezeVoter(
        address freezeVoterContract
    ) external virtual override {
        if (freezeVoterContract == address(0)) revert InvalidAddress();
        if (!_authorizedFreezeVotersMapping[freezeVoterContract]) {
            _authorizedFreezeVotersMapping[freezeVoterContract] = true;
            _authorizedFreezeVotersArray.push(freezeVoterContract);
            emit FreezeVoterAuthorizationChanged(freezeVoterContract, true);
        }
    }

    function removeAuthorizedFreezeVoter(
        address freezeVoterContract
    ) external virtual override {
        if (freezeVoterContract == address(0)) revert InvalidAddress();
        if (_authorizedFreezeVotersMapping[freezeVoterContract]) {
            _authorizedFreezeVotersMapping[freezeVoterContract] = false;
            for (uint256 i = 0; i < _authorizedFreezeVotersArray.length; ) {
                if (_authorizedFreezeVotersArray[i] == freezeVoterContract) {
                    _authorizedFreezeVotersArray[
                        i
                    ] = _authorizedFreezeVotersArray[
                        _authorizedFreezeVotersArray.length - 1
                    ];
                    _authorizedFreezeVotersArray.pop();
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            emit FreezeVoterAuthorizationChanged(freezeVoterContract, false);
        }
    }

    function isAuthorizedFreezeVoter(
        address freezeVoterContract
    ) external view virtual override returns (bool) {
        return _authorizedFreezeVotersMapping[freezeVoterContract];
    }

    function authorizedFreezeVoters()
        external
        view
        virtual
        override
        returns (address[] memory)
    {
        return _authorizedFreezeVotersArray;
    }

    function voteCastedAfterVotingPeriodEnded(
        uint32 _proposalId
    ) external view override returns (bool) {}

    function validStrategyVote(
        address,
        uint32 proposalId_,
        uint8 voteType_,
        IVotingTypes.VotingConfigVoteData[] calldata votingConfigsData_
    ) external view override returns (bool) {
        if (_shouldCheckExpectedParams) {
            if (proposalId_ != _expected_proposalId) {
                revert("Mismatched proposalId");
            }
            if (voteType_ != _expected_voteType) {
                revert("Mismatched voteType");
            }
            if (
                keccak256(abi.encode(votingConfigsData_)) !=
                _expected_votingConfigsDataHash
            ) {
                revert("Mismatched votingConfigsData");
            }
        }
        return _validStrategyVoteToReturn;
    }
}
