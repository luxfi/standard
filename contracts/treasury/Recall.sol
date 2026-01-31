// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20, SafeERC20} from "@luxfi/standard/tokens/ERC20.sol";
import {Ownable} from "@luxfi/standard/access/Access.sol";

/**
 * @title Recall
 * @author Lux Industries Inc
 * @notice Fund recall mechanism for hierarchical DAOs
 * @dev Tracks fund sources and allows parent to recall ONLY allocated funds
 *
 * CRITICAL DISTINCTION:
 * - ALLOCATED funds (from parent budget) → Can be recalled
 * - BONDED funds (community bought tokens) → CANNOT be recalled
 *
 * This preserves community sovereignty - people who buy into a DAO
 * keep their stake even if the parent disagrees.
 *
 * Example:
 * Security Committee goes rogue
 * ├── ALLOCATED: $50K → Parent CAN recall
 * ├── BONDED: $200K → Parent CANNOT recall
 * └── Security Committee continues with $200K community funds
 */
contract Recall is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Fund source types
    enum FundSource {
        ALLOCATED,  // From parent budget - recallable
        BONDED      // From community bonds - NOT recallable
    }

    /// @notice Child Safe this module is attached to
    address public immutable childSafe;

    /// @notice Parent Safe that can initiate recalls
    address public immutable parentSafe;

    /// @notice Grace period before recall can execute (default 30 days)
    uint256 public recallGracePeriod = 30 days;

    /// @notice Allocated balance per token (recallable)
    mapping(address => uint256) public allocatedBalance;

    /// @notice Bonded balance per token (non-recallable)
    mapping(address => uint256) public bondedBalance;

    /// @notice Pending recall requests
    struct RecallRequest {
        address token;
        uint256 amount;
        uint256 initiatedAt;
        bool executed;
        bool cancelled;
    }

    /// @notice Recall requests by ID
    mapping(uint256 => RecallRequest) public recallRequests;

    /// @notice Next recall ID
    uint256 public nextRecallId;

    /// @notice Approved controllers that can execute transfers on behalf of an address
    /// @dev Maps controller => source => approved
    mapping(address => mapping(address => bool)) public isApprovedController;

    /// @notice Events
    event FundingReceived(address indexed token, uint256 amount, FundSource source);
    event RecallInitiated(uint256 indexed recallId, address token, uint256 amount);
    event RecallExecuted(uint256 indexed recallId, address token, uint256 amount);
    event RecallCancelled(uint256 indexed recallId);
    event GracePeriodUpdated(uint256 newPeriod);
    event ControllerApprovalSet(address indexed controller, bool approved);

    /// @notice Errors
    error OnlyParent();
    error InsufficientAllocated();
    error GracePeriodNotElapsed();
    error RecallAlreadyExecuted();
    error RecallAlreadyCancelled();
    error InvalidAmount();
    error UnauthorizedSource();

    modifier onlyParent() {
        if (msg.sender != parentSafe) revert OnlyParent();
        _;
    }

    constructor(address childSafe_, address parentSafe_, address owner_) Ownable(owner_) {
        childSafe = childSafe_;
        parentSafe = parentSafe_;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUND TRACKING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Record incoming funds and their source
     * @dev Should be called when funds are received by the Safe
     * @param token Token address (address(0) for native)
     * @param amount Amount received
     * @param source Whether ALLOCATED (from parent) or BONDED (from community)
     */
    function recordFunding(address token, uint256 amount, FundSource source) external onlyOwner {
        if (amount == 0) revert InvalidAmount();

        if (source == FundSource.ALLOCATED) {
            allocatedBalance[token] += amount;
        } else {
            bondedBalance[token] += amount;
        }

        emit FundingReceived(token, amount, source);
    }

    /**
     * @notice Record spending from allocated funds first
     * @dev Should be called when Safe executes a transaction
     * @param token Token spent
     * @param amount Amount spent
     */
    function recordSpending(address token, uint256 amount) external onlyOwner {
        // Spend from allocated first, then bonded
        if (allocatedBalance[token] >= amount) {
            allocatedBalance[token] -= amount;
        } else {
            uint256 fromAllocated = allocatedBalance[token];
            allocatedBalance[token] = 0;
            bondedBalance[token] -= (amount - fromAllocated);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECALL MECHANISM
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initiate a recall request (parent only)
     * @param token Token to recall
     * @param amount Amount to recall (must be <= allocated balance)
     * @return recallId The recall request ID
     */
    function initiateRecall(address token, uint256 amount) external onlyParent returns (uint256 recallId) {
        if (amount > allocatedBalance[token]) revert InsufficientAllocated();

        recallId = nextRecallId++;
        recallRequests[recallId] = RecallRequest({
            token: token,
            amount: amount,
            initiatedAt: block.timestamp,
            executed: false,
            cancelled: false
        });

        emit RecallInitiated(recallId, token, amount);
    }

    /**
     * @notice Execute a recall after grace period
     * @param recallId Recall request ID
     */
    function executeRecall(uint256 recallId) external onlyParent {
        RecallRequest storage request = recallRequests[recallId];

        if (request.executed) revert RecallAlreadyExecuted();
        if (request.cancelled) revert RecallAlreadyCancelled();
        if (block.timestamp < request.initiatedAt + recallGracePeriod) {
            revert GracePeriodNotElapsed();
        }

        // Verify caller has authority over the source address
        // Either the childSafe itself is calling, or the caller is an approved controller
        if (childSafe != msg.sender && !isApprovedController[msg.sender][childSafe]) {
            revert UnauthorizedSource();
        }

        // Update balances
        allocatedBalance[request.token] -= request.amount;
        request.executed = true;

        // Transfer funds from child Safe to parent Safe
        // Note: This requires the Recall contract to be a module on the child Safe
        // The actual transfer is executed via Safe's execTransactionFromModule
        IERC20(request.token).safeTransferFrom(childSafe, parentSafe, request.amount);

        emit RecallExecuted(recallId, request.token, request.amount);
    }

    /**
     * @notice Cancel a recall request (child DAO negotiated with parent)
     * @param recallId Recall request ID
     */
    function cancelRecall(uint256 recallId) external onlyParent {
        RecallRequest storage request = recallRequests[recallId];
        if (request.executed) revert RecallAlreadyExecuted();

        request.cancelled = true;
        emit RecallCancelled(recallId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update grace period (governance only)
     * @param newPeriod New grace period in seconds
     */
    function setGracePeriod(uint256 newPeriod) external onlyOwner {
        recallGracePeriod = newPeriod;
        emit GracePeriodUpdated(newPeriod);
    }

    /**
     * @notice Set approved controller status for the childSafe
     * @dev Only the childSafe itself can approve controllers for its funds
     * @param controller Address to approve/revoke as controller
     * @param approved Whether the controller is approved
     */
    function setApprovedController(address controller, bool approved) external {
        // Only the childSafe can approve controllers for itself
        require(msg.sender == childSafe, "Recall: only childSafe can approve");
        isApprovedController[controller][childSafe] = approved;
        emit ControllerApprovalSet(controller, approved);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get allocated (recallable) balance
     * @param token Token address
     * @return Allocated balance
     */
    function getAllocatedBalance(address token) external view returns (uint256) {
        return allocatedBalance[token];
    }

    /**
     * @notice Get bonded (non-recallable) balance
     * @param token Token address
     * @return Bonded balance
     */
    function getBondedBalance(address token) external view returns (uint256) {
        return bondedBalance[token];
    }

    /**
     * @notice Get total balance
     * @param token Token address
     * @return Total balance (allocated + bonded)
     */
    function getTotalBalance(address token) external view returns (uint256) {
        return allocatedBalance[token] + bondedBalance[token];
    }

    /**
     * @notice Get recall request details
     * @param recallId Recall request ID
     * @return request The recall request
     */
    function getRecallRequest(uint256 recallId) external view returns (RecallRequest memory) {
        return recallRequests[recallId];
    }

    /**
     * @notice Check if recall can be executed
     * @param recallId Recall request ID
     * @return True if executable
     */
    function canExecuteRecall(uint256 recallId) external view returns (bool) {
        RecallRequest storage request = recallRequests[recallId];
        return !request.executed &&
               !request.cancelled &&
               block.timestamp >= request.initiatedAt + recallGracePeriod;
    }
}
