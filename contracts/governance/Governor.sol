// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IGovernor} from "./interfaces/IGovernor.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {Transaction} from "./base/Transaction.sol";
import {Controller} from "./Controller.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
// Note: Initializable is inherited through Ownable2StepUpgradeable and UUPSUpgradeable

/**
 * @title Governor
 * @author Lux Industries Inc
 * @notice Core governance module for Lux DAOs integrated with Gnosis Safe
 * @dev This contract implements IGovernor, providing the core governance system
 * for DAOs integrated with Gnosis Safe.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage for upgradeability safety
 * - Implements UUPS (Universal Upgradeable Proxy Standard)
 * - Upgrades restricted to contract owner
 * - Supports partial proposal execution for gas efficiency
 * - Uses EIP-712 structured data hashing for transaction integrity
 * - Inherits from Controller for Safe module integration
 * - Uses Ownable2Step for secure ownership transfers
 *
 * Renamed from ModuleAzoriusV1 to align with Lux naming conventions.
 *
 * @custom:security-contact security@lux.network
 */
contract Governor is
    IGovernor,
    Controller,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @dev Contains all governance state
     * @custom:storage-location erc7201:Lux.Governor.main
     */
    struct GovernorStorage {
        uint32 totalProposalCount;
        uint32 timelockPeriod;
        uint32 executionPeriod;
        mapping(uint32 proposalId => Proposal proposal) proposals;
        IStrategy strategy;
    }

    /**
     * @dev Storage slot for GovernorStorage using EIP-7201 formula
     * keccak256(abi.encode(uint256(keccak256("Lux.Governor.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant GOVERNOR_STORAGE_LOCATION =
        0xb4c8b1c40e0c0c5e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0100;

    function _getGovernorStorage() internal pure returns (GovernorStorage storage $) {
        assembly {
            $.slot := GOVERNOR_STORAGE_LOCATION
        }
    }

    /**
     * @notice EIP-712 domain separator type hash
     */
    bytes32 public constant DOMAIN_SEPARATOR_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /**
     * @notice EIP-712 transaction type hash
     */
    bytes32 public constant TRANSACTION_TYPEHASH =
        keccak256(
            "Transaction(address to,uint256 value,bytes data,uint8 operation,uint256 nonce)"
        );

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IGovernor
     */
    function initialize(
        address owner_,
        address vault_,
        address target_,
        address strategy_,
        uint32 timelockPeriod_,
        uint32 executionPeriod_
    ) public virtual override initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(owner_);

        // Set vault and target (was avatar/target in Zodiac)
        vault = vault_;
        target = target_;
        emit VaultSet(address(0), vault_);
        emit TargetSet(address(0), target_);

        _updateStrategy(strategy_);
        _updateTimelockPeriod(timelockPeriod_);
        _updateExecutionPeriod(executionPeriod_);
    }

    /**
     * @notice Alternative initializer following module pattern
     * @param initializeParams_ ABI encoded parameters
     */
    function setUp(bytes memory initializeParams_) public virtual override initializer {
        (
            address owner_,
            address vault_,
            address target_,
            address strategy_,
            uint32 timelockPeriod_,
            uint32 executionPeriod_
        ) = abi.decode(
                initializeParams_,
                (address, address, address, address, uint32, uint32)
            );
        initialize(
            owner_,
            vault_,
            target_,
            strategy_,
            timelockPeriod_,
            executionPeriod_
        );
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyOwner {}

    // ======================================================================
    // IGovernor View Functions
    // ======================================================================

    function totalProposalCount() public view virtual override returns (uint32) {
        GovernorStorage storage $ = _getGovernorStorage();
        return $.totalProposalCount;
    }

    function timelockPeriod() public view virtual override returns (uint32) {
        GovernorStorage storage $ = _getGovernorStorage();
        return $.timelockPeriod;
    }

    function executionPeriod() public view virtual override returns (uint32) {
        GovernorStorage storage $ = _getGovernorStorage();
        return $.executionPeriod;
    }

    function proposals(uint32 proposalId_) public view virtual override returns (Proposal memory) {
        GovernorStorage storage $ = _getGovernorStorage();
        return $.proposals[proposalId_];
    }

    function strategy() public view virtual override returns (address) {
        GovernorStorage storage $ = _getGovernorStorage();
        return address($.strategy);
    }

    function proposalState(uint32 proposalId_) public view virtual override returns (ProposalState) {
        GovernorStorage storage $ = _getGovernorStorage();

        if (proposalId_ >= $.totalProposalCount) revert InvalidProposal();

        Proposal memory _proposal = $.proposals[proposalId_];
        IStrategy strategy_ = IStrategy(_proposal.strategy);

        (, uint48 votingEndTimestamp) = strategy_.getVotingTimestamps(proposalId_);

        // ACTIVE - Still in voting period
        if (block.timestamp <= votingEndTimestamp) {
            return ProposalState.ACTIVE;
        }
        // FAILED - Voting ended but didn't pass
        else if (!strategy_.isPassed(proposalId_)) {
            return ProposalState.FAILED;
        }
        // EXECUTED - All transactions executed
        else if (_proposal.executionCounter == _proposal.txHashes.length) {
            return ProposalState.EXECUTED;
        }
        // TIMELOCKED - Passed but in timelock
        else if (block.timestamp <= votingEndTimestamp + _proposal.timelockPeriod) {
            return ProposalState.TIMELOCKED;
        }
        // EXECUTABLE - Ready for execution
        else if (
            block.timestamp <=
            votingEndTimestamp + _proposal.timelockPeriod + _proposal.executionPeriod
        ) {
            return ProposalState.EXECUTABLE;
        }
        // EXPIRED - Execution window passed
        else {
            return ProposalState.EXPIRED;
        }
    }

    function generateTxHashData(
        Transaction calldata transaction_,
        uint256 nonce_
    ) public view virtual override returns (bytes memory) {
        uint256 chainId = block.chainid;
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_SEPARATOR_TYPEHASH, chainId, this)
        );
        bytes32 transactionHash = keccak256(
            abi.encode(
                TRANSACTION_TYPEHASH,
                transaction_.to,
                transaction_.value,
                keccak256(transaction_.data),
                transaction_.operation,
                nonce_
            )
        );
        return
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                domainSeparator,
                transactionHash
            );
    }

    function getTxHash(Transaction calldata transaction_) public view virtual override returns (bytes32) {
        return keccak256(generateTxHashData(transaction_, 0));
    }

    function getProposalTxHash(
        uint32 proposalId_,
        uint32 txIndex_
    ) public view virtual override returns (bytes32) {
        GovernorStorage storage $ = _getGovernorStorage();
        return $.proposals[proposalId_].txHashes[txIndex_];
    }

    function getProposalTxHashes(uint32 proposalId_) public view virtual override returns (bytes32[] memory) {
        GovernorStorage storage $ = _getGovernorStorage();
        return $.proposals[proposalId_].txHashes;
    }

    function getProposal(
        uint32 proposalId_
    ) public view virtual override returns (address, bytes32[] memory, uint32, uint32, uint32) {
        GovernorStorage storage $ = _getGovernorStorage();
        Proposal memory _proposal = $.proposals[proposalId_];
        return (
            _proposal.strategy,
            _proposal.txHashes,
            _proposal.timelockPeriod,
            _proposal.executionPeriod,
            _proposal.executionCounter
        );
    }

    // ======================================================================
    // IGovernor State-Changing Functions
    // ======================================================================

    function updateTimelockPeriod(uint32 timelockPeriod_) public virtual override onlyOwner {
        _updateTimelockPeriod(timelockPeriod_);
    }

    function updateExecutionPeriod(uint32 executionPeriod_) public virtual override onlyOwner {
        _updateExecutionPeriod(executionPeriod_);
    }

    function updateStrategy(address strategy_) public virtual override onlyOwner {
        _updateStrategy(strategy_);
    }

    function submitProposal(
        Transaction[] calldata transactions_,
        string calldata metadata_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) public virtual override {
        GovernorStorage storage $ = _getGovernorStorage();

        // Validate proposer through strategy's adapter system
        if (
            !$.strategy.isProposer(
                msg.sender,
                proposerAdapter_,
                proposerAdapterData_
            )
        ) revert InvalidProposer();

        // Compute transaction hashes
        bytes32[] memory txHashes = new bytes32[](transactions_.length);
        uint256 transactionsLength = transactions_.length;
        for (uint256 i; i < transactionsLength; ) {
            txHashes[i] = getTxHash(transactions_[i]);
            unchecked {
                ++i;
            }
        }

        // Store proposal
        Proposal storage proposal = $.proposals[$.totalProposalCount];
        proposal.strategy = address($.strategy);
        proposal.txHashes = txHashes;
        proposal.timelockPeriod = $.timelockPeriod;
        proposal.executionPeriod = $.executionPeriod;

        // Initialize voting in strategy
        $.strategy.initializeProposal($.totalProposalCount);

        emit ProposalCreated(
            address($.strategy),
            $.totalProposalCount,
            msg.sender,
            transactions_,
            metadata_
        );

        $.totalProposalCount++;
    }

    function executeProposal(
        uint32 proposalId_,
        Transaction[] calldata transactions_
    ) public virtual override {
        if (transactions_.length == 0) revert InvalidTxs();

        GovernorStorage storage $ = _getGovernorStorage();
        Proposal memory proposal = $.proposals[proposalId_];

        if (
            proposal.executionCounter + transactions_.length >
            proposal.txHashes.length
        ) revert InvalidTxs();

        uint256 transactionsLength = transactions_.length;
        bytes32[] memory txHashes = new bytes32[](transactionsLength);
        for (uint256 i; i < transactionsLength; ) {
            txHashes[i] = _executeProposalTx(proposalId_, transactions_[i]);
            unchecked {
                ++i;
            }
        }

        emit ProposalExecuted(proposalId_, txHashes);
    }

    // ======================================================================
    // Ownable2StepUpgradeable
    // ======================================================================

    function transferOwnership(
        address newOwner_
    ) public virtual override(Ownable2StepUpgradeable) onlyOwner {
        Ownable2StepUpgradeable.transferOwnership(newOwner_);
    }

    function _transferOwnership(
        address newOwner_
    ) internal virtual override(Ownable2StepUpgradeable) {
        Ownable2StepUpgradeable._transferOwnership(newOwner_);
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IGovernor).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _executeProposalTx(
        uint32 proposalId_,
        Transaction calldata transaction_
    ) internal virtual returns (bytes32) {
        if (proposalState(proposalId_) != ProposalState.EXECUTABLE)
            revert ProposalNotExecutable();

        bytes32 txHash = getTxHash(transaction_);

        GovernorStorage storage $ = _getGovernorStorage();
        Proposal storage proposal = $.proposals[proposalId_];

        if (proposal.txHashes[proposal.executionCounter] != txHash)
            revert InvalidTxHash();

        proposal.executionCounter++;

        if (
            !exec(
                transaction_.to,
                transaction_.value,
                transaction_.data,
                transaction_.operation
            )
        ) revert TxFailed();

        return txHash;
    }

    function _updateTimelockPeriod(uint32 timelockPeriod_) internal virtual {
        GovernorStorage storage $ = _getGovernorStorage();
        $.timelockPeriod = timelockPeriod_;
        emit TimelockPeriodUpdated(timelockPeriod_);
    }

    function _updateExecutionPeriod(uint32 executionPeriod_) internal virtual {
        GovernorStorage storage $ = _getGovernorStorage();
        $.executionPeriod = executionPeriod_;
        emit ExecutionPeriodUpdated(executionPeriod_);
    }

    function _updateStrategy(address strategy_) internal virtual {
        if (strategy_ == address(0)) revert InvalidStrategy();

        GovernorStorage storage $ = _getGovernorStorage();
        $.strategy = IStrategy(strategy_);
        emit StrategyUpdated(strategy_);
    }
}
