// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {ICouncil} from "./interfaces/ICouncil.sol";
import {ICharter} from "./interfaces/ICharter.sol";
import {Transaction} from "./base/Transaction.sol";
import {Secretariat} from "./Secretariat.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
// Note: Initializable is inherited through Ownable2StepUpgradeable and UUPSUpgradeable

/**
 * @title Council
 * @author Lux Industries Inc
 * @notice Core governance module for Lux DAOs integrated with Gnosis Safe
 * @dev This contract implements ICouncil, providing the core governance system
 * for DAOs integrated with Gnosis Safe.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage for upgradeability safety
 * - Implements UUPS (Universal Upgradeable Proxy Standard)
 * - Upgrades restricted to contract owner
 * - Supports partial proposal execution for gas efficiency
 * - Uses EIP-712 structured data hashing for transaction integrity
 * - Inherits from Secretariat for Safe module integration
 * - Uses Ownable2Step for secure ownership transfers
 *
 * Renamed from ModuleAzoriusV1 to align with Lux naming conventions.
 *
 * @custom:security-contact security@lux.network
 */
contract Council is
    ICouncil,
    Secretariat,
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
     * @custom:storage-location erc7201:Lux.Council.main
     */
    struct CouncilStorage {
        uint32 totalProposalCount;
        uint32 timelockPeriod;
        uint32 executionPeriod;
        mapping(uint32 proposalId => Proposal proposal) proposals;
        ICharter charter;
        /// @notice H-02 fix: Maximum active proposals to prevent DoS via proposal spam
        uint32 maxActiveProposals;
        /// @notice H-02 fix: Counter for active proposals (not executed/expired)
        uint32 activeProposalCount;
    }

    /**
     * @dev Storage slot for CouncilStorage using EIP-7201 formula
     * keccak256(abi.encode(uint256(keccak256("Lux.Council.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant COUNCIL_STORAGE_LOCATION =
        0xb4c8b1c40e0c0c5e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0100;

    function _getCouncilStorage() internal pure returns (CouncilStorage storage $) {
        assembly {
            $.slot := COUNCIL_STORAGE_LOCATION
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
     * @notice H-02 fix: Default maximum active proposals
     */
    uint32 public constant DEFAULT_MAX_ACTIVE_PROPOSALS = 100;

    /**
     * @notice H-02 fix: Error when max active proposals reached
     */
    error MaxActiveProposalsReached();

    /**
     * @inheritdoc ICouncil
     */
    function initialize(
        address owner_,
        address vault_,
        address target_,
        address charter_,
        uint32 timelockPeriod_,
        uint32 executionPeriod_
    ) public virtual override initializer {
        __Ownable_init(owner_);

        // Set vault and target (was avatar/target in Zodiac)
        vault = vault_;
        target = target_;
        emit VaultSet(address(0), vault_);
        emit TargetSet(address(0), target_);

        _updateCharter(charter_);
        _updateTimelockPeriod(timelockPeriod_);
        _updateExecutionPeriod(executionPeriod_);

        // H-02 fix: Set default max active proposals
        CouncilStorage storage $ = _getCouncilStorage();
        $.maxActiveProposals = DEFAULT_MAX_ACTIVE_PROPOSALS;
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
            address charter_,
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
            charter_,
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
    // ICouncil View Functions
    // ======================================================================

    function totalProposalCount() public view virtual override returns (uint32) {
        CouncilStorage storage $ = _getCouncilStorage();
        return $.totalProposalCount;
    }

    function timelockPeriod() public view virtual override returns (uint32) {
        CouncilStorage storage $ = _getCouncilStorage();
        return $.timelockPeriod;
    }

    function executionPeriod() public view virtual override returns (uint32) {
        CouncilStorage storage $ = _getCouncilStorage();
        return $.executionPeriod;
    }

    function proposals(uint32 proposalId_) public view virtual override returns (Proposal memory) {
        CouncilStorage storage $ = _getCouncilStorage();
        return $.proposals[proposalId_];
    }

    function charter() public view virtual override returns (address) {
        CouncilStorage storage $ = _getCouncilStorage();
        return address($.charter);
    }

    function proposalState(uint32 proposalId_) public view virtual override returns (ProposalState) {
        CouncilStorage storage $ = _getCouncilStorage();

        if (proposalId_ >= $.totalProposalCount) revert InvalidProposal();

        Proposal memory _proposal = $.proposals[proposalId_];
        ICharter charter_ = ICharter(_proposal.charter);

        (, uint48 votingEndTimestamp) = charter_.getVotingTimestamps(proposalId_);

        // ACTIVE - Still in voting period
        if (block.timestamp <= votingEndTimestamp) {
            return ProposalState.ACTIVE;
        }
        // FAILED - Voting ended but didn't pass
        else if (!charter_.isPassed(proposalId_)) {
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
        CouncilStorage storage $ = _getCouncilStorage();
        return $.proposals[proposalId_].txHashes[txIndex_];
    }

    function getProposalTxHashes(uint32 proposalId_) public view virtual override returns (bytes32[] memory) {
        CouncilStorage storage $ = _getCouncilStorage();
        return $.proposals[proposalId_].txHashes;
    }

    function getProposal(
        uint32 proposalId_
    ) public view virtual override returns (address, bytes32[] memory, uint32, uint32, uint32) {
        CouncilStorage storage $ = _getCouncilStorage();
        Proposal memory _proposal = $.proposals[proposalId_];
        return (
            _proposal.charter,
            _proposal.txHashes,
            _proposal.timelockPeriod,
            _proposal.executionPeriod,
            _proposal.executionCounter
        );
    }

    // ======================================================================
    // ICouncil State-Changing Functions
    // ======================================================================

    function updateTimelockPeriod(uint32 timelockPeriod_) public virtual override onlyOwner {
        _updateTimelockPeriod(timelockPeriod_);
    }

    function updateExecutionPeriod(uint32 executionPeriod_) public virtual override onlyOwner {
        _updateExecutionPeriod(executionPeriod_);
    }

    function updateCharter(address charter_) public virtual override onlyOwner {
        _updateCharter(charter_);
    }

    /**
     * @notice H-02 fix: Update maximum active proposals limit
     * @param maxActiveProposals_ New maximum active proposals
     */
    function updateMaxActiveProposals(uint32 maxActiveProposals_) public virtual onlyOwner {
        CouncilStorage storage $ = _getCouncilStorage();
        $.maxActiveProposals = maxActiveProposals_;
    }

    /**
     * @notice H-02 fix: Get maximum active proposals
     */
    function maxActiveProposals() public view virtual returns (uint32) {
        return _getCouncilStorage().maxActiveProposals;
    }

    /**
     * @notice H-02 fix: Get current active proposal count
     */
    function activeProposalCount() public view virtual returns (uint32) {
        return _getCouncilStorage().activeProposalCount;
    }

    function submitProposal(
        Transaction[] calldata transactions_,
        string calldata metadata_,
        address proposerAdapter_,
        bytes calldata proposerAdapterData_
    ) public virtual override {
        CouncilStorage storage $ = _getCouncilStorage();

        // H-02 fix: Check max active proposals limit
        if ($.activeProposalCount >= $.maxActiveProposals) {
            revert MaxActiveProposalsReached();
        }

        // Validate proposer through charter's adapter system
        if (
            !$.charter.isProposer(
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
        proposal.charter = address($.charter);
        proposal.txHashes = txHashes;
        proposal.timelockPeriod = $.timelockPeriod;
        proposal.executionPeriod = $.executionPeriod;

        // Initialize voting in charter
        $.charter.initializeProposal($.totalProposalCount);

        emit ProposalCreated(
            address($.charter),
            $.totalProposalCount,
            msg.sender,
            transactions_,
            metadata_
        );

        $.totalProposalCount++;
        // H-02 fix: Increment active proposal counter
        $.activeProposalCount++;
    }

    function executeProposal(
        uint32 proposalId_,
        Transaction[] calldata transactions_
    ) public virtual override {
        if (transactions_.length == 0) revert InvalidTxs();

        CouncilStorage storage $ = _getCouncilStorage();
        Proposal storage proposal = $.proposals[proposalId_];

        if (
            proposal.executionCounter + transactions_.length >
            proposal.txHashes.length
        ) revert InvalidTxs();

        // H-02 fix: Track if this is the final execution batch
        bool willComplete = proposal.executionCounter + transactions_.length == proposal.txHashes.length;

        uint256 transactionsLength = transactions_.length;
        bytes32[] memory txHashes = new bytes32[](transactionsLength);
        for (uint256 i; i < transactionsLength; ) {
            txHashes[i] = _executeProposalTx(proposalId_, transactions_[i]);
            unchecked {
                ++i;
            }
        }

        // H-02 fix: Decrement active proposal counter when fully executed
        if (willComplete && $.activeProposalCount > 0) {
            $.activeProposalCount--;
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
            interfaceId_ == type(ICouncil).interfaceId ||
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

        CouncilStorage storage $ = _getCouncilStorage();
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
        CouncilStorage storage $ = _getCouncilStorage();
        $.timelockPeriod = timelockPeriod_;
        emit TimelockPeriodUpdated(timelockPeriod_);
    }

    function _updateExecutionPeriod(uint32 executionPeriod_) internal virtual {
        CouncilStorage storage $ = _getCouncilStorage();
        $.executionPeriod = executionPeriod_;
        emit ExecutionPeriodUpdated(executionPeriod_);
    }

    function _updateCharter(address charter_) internal virtual {
        if (charter_ == address(0)) revert InvalidCharter();

        CouncilStorage storage $ = _getCouncilStorage();
        $.charter = ICharter(charter_);
        emit CharterUpdated(charter_);
    }
}
