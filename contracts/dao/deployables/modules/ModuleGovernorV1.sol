// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IModuleGovernorV1
} from "../../interfaces/deployables/IModuleGovernorV1.sol";
import {IStrategyV1} from "../../interfaces/deployables/IStrategyV1.sol";
import {Transaction} from "../../interfaces/Module.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {GuardableModule} from "../../base/GuardableModule.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title ModuleGovernorV1
 * @author Lux Industriesn Inc
 * @notice Implementation of the Governor Protocol governance module
 * @dev This contract implements IModuleGovernorV1, providing the core governance system
 * for DAOs integrated with Gnosis Safe.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Implements UUPS (Universal Upgradeable Proxy Standard) pattern
 * - Upgrades are restricted to the contract owner
 * - Storage layout must be preserved in future implementations
 * - Supports partial proposal execution for gas efficiency
 * - Uses EIP-712 structured data hashing for transaction integrity
 * - Inherits from GuardableModule for Zodiac pattern integration
 * - Uses Ownable2Step for secure ownership transfers
 *
 * @custom:security-contact security@lux.network
 */
contract ModuleGovernorV1 is
    IModuleGovernorV1,
    IVersion,
    GuardableModule,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for ModuleGovernorV1 following EIP-7201
     * @dev Contains all governance state including proposals and configuration
     * @custom:storage-location erc7201:DAO.ModuleGovernor.main
     */
    struct ModuleGovernorStorage {
        /** @notice Counter tracking total proposals created (0-indexed) */
        uint32 totalProposalCount;
        /** @notice Default timelock delay in seconds for new proposals */
        uint32 timelockPeriod;
        /** @notice Default execution window in seconds for new proposals */
        uint32 executionPeriod;
        /** @notice Mapping from proposal ID to proposal data */
        mapping(uint32 proposalId => Proposal proposal) proposals;
        /** @notice Default voting strategy contract for new proposals */
        IStrategyV1 strategy;
    }

    /**
     * @dev Storage slot for ModuleGovernorStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.ModuleGovernor.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant MODULE_GOVERNOR_STORAGE_LOCATION =
        0xedd394c11bb1dac1602ad0766d0e03cc697fdaf9a9996bf169d40a2c3b6fa100;

    /**
     * @dev Returns the storage struct for ModuleGovernorV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for ModuleGovernorV1
     */
    function _getModuleGovernorStorage()
        internal
        pure
        returns (ModuleGovernorStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := MODULE_GOVERNOR_STORAGE_LOCATION
        }
    }

    /**
     * @notice EIP-712 domain separator type hash for transaction validation
     * @dev Used to create unique domain separators per chain and contract instance
     */
    bytes32 public constant DOMAIN_SEPARATOR_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /**
     * @notice EIP-712 transaction type hash for secure transaction hashing
     * @dev Ensures transaction details cannot be tampered with between proposal and execution
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
     * @inheritdoc IModuleGovernorV1
     */
    function initialize(
        address owner_,
        address avatar_,
        address target_,
        address strategy_,
        uint32 timelockPeriod_,
        uint32 executionPeriod_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(
                owner_,
                avatar_,
                target_,
                strategy_,
                timelockPeriod_,
                executionPeriod_
            )
        );
        __UUPSUpgradeable_init();
        __Ownable_init(owner_);
        __DeploymentBlockInitializable_init();

        // avoids onlyOwner requirement on setAvatar and setTarget
        avatar = avatar_;
        target = target_;
        emit AvatarSet(address(0), avatar_);
        emit TargetSet(address(0), target_);

        _updateStrategy(strategy_);
        _updateTimelockPeriod(timelockPeriod_);
        _updateExecutionPeriod(executionPeriod_);
    }

    /**
     * @notice Alternative initializer following Zodiac module pattern
     * @dev Decodes packed initialization parameters and calls initialize
     * @param initializeParams_ ABI encoded parameters (owner, avatar, target, strategy, timelockPeriod, executionPeriod)
     */
    function setUp(
        bytes memory initializeParams_
    ) public virtual override initializer {
        (
            address owner_,
            address avatar_,
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
            avatar_,
            target_,
            strategy_,
            timelockPeriod_,
            executionPeriod_
        );
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev Restricted to contract owner for security
     */
    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
        // Intentionally empty - authorization logic handled by onlyOwner modifier
    }

    // ======================================================================
    // IModuleGovernorV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function totalProposalCount()
        public
        view
        virtual
        override
        returns (uint32)
    {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return $.totalProposalCount;
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function timelockPeriod() public view virtual override returns (uint32) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return $.timelockPeriod;
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function executionPeriod() public view virtual override returns (uint32) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return $.executionPeriod;
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function proposals(
        uint32 proposalId_
    ) public view virtual override returns (Proposal memory) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return $.proposals[proposalId_];
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function strategy() public view virtual override returns (address) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return address($.strategy);
    }

    /**
     * @inheritdoc IModuleGovernorV1
     * @dev Dynamically calculates state based on current timestamp and voting results.
     * State transitions follow a strict progression through the proposal lifecycle.
     */
    function proposalState(
        uint32 proposalId_
    ) public view virtual override returns (ProposalState) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();

        // Validate proposal exists
        if (proposalId_ >= $.totalProposalCount) revert InvalidProposal();

        Proposal memory _proposal = $.proposals[proposalId_];
        IStrategyV1 strategy_ = IStrategyV1(_proposal.strategy);

        // Get voting end timestamp from the strategy to determine state transitions
        (, uint48 votingEndTimestamp) = strategy_.getVotingTimestamps(
            proposalId_
        );

        // State 1: ACTIVE - Still in voting period
        if (block.timestamp <= votingEndTimestamp) {
            return ProposalState.ACTIVE;
        }
        // State 2: FAILED - Voting ended but didn't pass
        else if (!strategy_.isPassed(proposalId_)) {
            return ProposalState.FAILED;
        }
        // State 3: EXECUTED - All transactions have been executed
        else if (_proposal.executionCounter == _proposal.txHashes.length) {
            return ProposalState.EXECUTED;
        }
        // State 4: TIMELOCKED - Passed but still in timelock period
        else if (
            block.timestamp <= votingEndTimestamp + _proposal.timelockPeriod
        ) {
            return ProposalState.TIMELOCKED;
        }
        // State 5: EXECUTABLE - Ready for execution within the execution window
        else if (
            block.timestamp <=
            votingEndTimestamp +
                _proposal.timelockPeriod +
                _proposal.executionPeriod
        ) {
            return ProposalState.EXECUTABLE;
        }
        // State 6: EXPIRED - Execution window has passed
        else {
            return ProposalState.EXPIRED;
        }
    }

    /**
     * @inheritdoc IModuleGovernorV1
     * @dev Implements EIP-712 structured data hashing for transaction integrity
     */
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

    /**
     * @inheritdoc IModuleGovernorV1
     * @dev Uses nonce of 0 for deterministic hashing
     */
    function getTxHash(
        Transaction calldata transaction_
    ) public view virtual override returns (bytes32) {
        return keccak256(generateTxHashData(transaction_, 0));
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function getProposalTxHash(
        uint32 proposalId_,
        uint32 txIndex_
    ) public view virtual override returns (bytes32) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return $.proposals[proposalId_].txHashes[txIndex_];
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function getProposalTxHashes(
        uint32 proposalId_
    ) public view virtual override returns (bytes32[] memory) {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        return $.proposals[proposalId_].txHashes;
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function getProposal(
        uint32 proposalId_
    )
        public
        view
        virtual
        override
        returns (address, bytes32[] memory, uint32, uint32, uint32)
    {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        Proposal memory _proposal = $.proposals[proposalId_];
        return (
            _proposal.strategy,
            _proposal.txHashes,
            _proposal.timelockPeriod,
            _proposal.executionPeriod,
            _proposal.executionCounter
        );
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function updateTimelockPeriod(
        uint32 timelockPeriod_
    ) public virtual override onlyOwner {
        _updateTimelockPeriod(timelockPeriod_);
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function updateExecutionPeriod(
        uint32 executionPeriod_
    ) public virtual override onlyOwner {
        _updateExecutionPeriod(executionPeriod_);
    }

    /**
     * @inheritdoc IModuleGovernorV1
     */
    function updateStrategy(
        address strategy_
    ) public virtual override onlyOwner {
        _updateStrategy(strategy_);
    }

    /**
     * @inheritdoc IModuleGovernorV1
     * @dev Validates proposer through strategy, computes transaction hashes,
     * stores proposal data, and notifies strategy to initialize voting
     */
    function submitProposal(
        Transaction[] calldata transactions_,
        string calldata metadata_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) public virtual override {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();

        // Step 1: Validate the proposer through the strategy's adapter system
        if (
            !$.strategy.isProposer(
                msg.sender,
                proposerAdapter_,
                proposerAdapterData_
            )
        ) revert InvalidProposer();

        // Step 2: Compute and store transaction hashes for integrity verification
        bytes32[] memory txHashes = new bytes32[](transactions_.length);
        uint256 transactionsLength = transactions_.length;
        for (uint256 i; i < transactionsLength; ) {
            txHashes[i] = getTxHash(transactions_[i]);
            unchecked {
                ++i;
            }
        }

        // Step 3: Store proposal data using current configuration
        // Note: proposalId is the current totalProposalCount (before increment)
        Proposal storage proposal = $.proposals[$.totalProposalCount];
        proposal.strategy = address($.strategy);
        proposal.txHashes = txHashes;
        proposal.timelockPeriod = $.timelockPeriod;
        proposal.executionPeriod = $.executionPeriod;

        // Step 4: Initialize voting period in the strategy contract
        $.strategy.initializeProposal($.totalProposalCount);

        // Step 5: Emit event with full proposal details for indexing
        emit ProposalCreated(
            address($.strategy),
            $.totalProposalCount,
            msg.sender,
            transactions_,
            metadata_
        );

        // Step 6: Increment proposal counter for next proposal
        $.totalProposalCount++;
    }

    /**
     * @inheritdoc IModuleGovernorV1
     * @dev Supports partial execution - transactions are executed in order
     * and executionCounter tracks progress
     */
    function executeProposal(
        uint32 proposalId_,
        Transaction[] calldata transactions_
    ) public virtual override {
        // Validate at least one transaction is being executed
        if (transactions_.length == 0) revert InvalidTxs();

        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        Proposal memory proposal = $.proposals[proposalId_];

        // Ensure we don't execute more transactions than exist in the proposal
        // This supports partial execution - caller can execute a subset of transactions
        if (
            proposal.executionCounter + transactions_.length >
            proposal.txHashes.length
        ) revert InvalidTxs();

        // Execute each transaction in order and collect their hashes
        uint256 transactionsLength = transactions_.length;
        bytes32[] memory txHashes = new bytes32[](transactionsLength);
        for (uint256 i; i < transactionsLength; ) {
            // Execute single transaction and verify it matches the stored hash
            txHashes[i] = _executeProposalTx(proposalId_, transactions_[i]);
            unchecked {
                ++i;
            }
        }

        // Emit event with executed transaction hashes for tracking
        emit ProposalExecuted(proposalId_, txHashes);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // Ownable2StepUpgradeable
    // ======================================================================

    // --- State-Changing Functions ---

    /**
     * @inheritdoc Ownable2StepUpgradeable
     * @dev Overrides both Ownable2StepUpgradeable and OwnableUpgradeable to use
     * the two-step ownership transfer process
     */
    function transferOwnership(
        address newOwner_
    )
        public
        virtual
        override(Ownable2StepUpgradeable)
        onlyOwner
    {
        Ownable2StepUpgradeable.transferOwnership(newOwner_);
    }

    // --- Internal Functions ---

    /**
     * @inheritdoc Ownable2StepUpgradeable
     * @dev Overrides both Ownable2StepUpgradeable and OwnableUpgradeable to use
     * the two-step ownership transfer process
     */
    function _transferOwnership(
        address newOwner_
    ) internal virtual override(Ownable2StepUpgradeable) {
        Ownable2StepUpgradeable._transferOwnership(newOwner_);
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports IModuleGovernorV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IModuleGovernorV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @dev Executes a single transaction from a proposal
     * @param proposalId_ The proposal containing the transaction
     * @param transaction_ The transaction details to execute
     * @return txHash The hash of the executed transaction
     * @custom:throws ProposalNotExecutable if proposal is not in EXECUTABLE state
     * @custom:throws InvalidTxHash if transaction doesn't match stored hash
     * @custom:throws TxFailed if transaction execution fails
     */
    function _executeProposalTx(
        uint32 proposalId_,
        Transaction calldata transaction_
    ) internal virtual returns (bytes32) {
        // Verify proposal is in EXECUTABLE state (passed voting, timelock expired, not expired)
        if (proposalState(proposalId_) != ProposalState.EXECUTABLE)
            revert ProposalNotExecutable();

        // Calculate hash of the transaction to execute
        bytes32 txHash = getTxHash(transaction_);

        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        Proposal storage proposal = $.proposals[proposalId_];

        // Verify transaction hash matches the expected hash at current execution position
        // This ensures transactions are executed in the exact order they were proposed
        if (proposal.txHashes[proposal.executionCounter] != txHash)
            revert InvalidTxHash();

        // Increment execution counter before external call (checks-effects-interactions pattern)
        proposal.executionCounter++;

        // Execute the transaction through the Zodiac module's exec function
        // This will execute through the Safe if properly configured
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

    /**
     * @dev Updates the default timelock period for new proposals
     * @param timelockPeriod_ New timelock period in seconds
     */
    function _updateTimelockPeriod(uint32 timelockPeriod_) internal virtual {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        $.timelockPeriod = timelockPeriod_;
        emit TimelockPeriodUpdated(timelockPeriod_);
    }

    /**
     * @dev Updates the default execution period for new proposals
     * @param executionPeriod_ New execution period in seconds
     */
    function _updateExecutionPeriod(uint32 executionPeriod_) internal virtual {
        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        $.executionPeriod = executionPeriod_;
        emit ExecutionPeriodUpdated(executionPeriod_);
    }

    /**
     * @dev Updates the default strategy for new proposals
     * @param strategy_ New strategy contract address
     * @custom:throws InvalidStrategy if strategy_ is zero address
     */
    function _updateStrategy(address strategy_) internal virtual {
        if (strategy_ == address(0)) revert InvalidStrategy();

        ModuleGovernorStorage storage $ = _getModuleGovernorStorage();
        $.strategy = IStrategyV1(strategy_);
        emit StrategyUpdated(strategy_);
    }
}
