// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IOptionsVault
 * @author Lux Industries
 * @notice Interface for collateral vault managing margin for option writers
 * @dev Supports spread margin where long positions reduce collateral requirements
 */
interface IOptionsVault {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Per-user collateral account for a given token
    struct Account {
        uint256 deposited;
        uint256 locked;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when deposit or withdrawal amount is zero
    error ZeroAmount();

    /// @notice Thrown when address is the zero address
    error ZeroAddress();

    /// @notice Thrown when withdrawal exceeds available balance
    error InsufficientAvailable();

    /// @notice Thrown when caller is not the authorized options contract
    error UnauthorizedCaller();

    /// @notice Thrown when maintenance margin is breached
    error MaintenanceMarginBreached();

    /// @notice Thrown when user is above liquidation threshold
    error AboveLiquidationThreshold();

    /// @notice Thrown when token is not supported
    error UnsupportedToken();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a user deposits collateral
    event Deposited(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when a user withdraws collateral
    event Withdrawn(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when collateral is locked for a position
    event CollateralLocked(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when collateral is released from a position
    event CollateralReleased(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted when a position is liquidated
    event Liquidated(address indexed user, address indexed token, uint256 amount, address indexed liquidator);

    // ═══════════════════════════════════════════════════════════════════════
    // USER OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deposit collateral into the vault
     * @param token ERC20 token to deposit
     * @param amount Amount to deposit
     */
    function deposit(address token, uint256 amount) external;

    /**
     * @notice Withdraw available (unlocked) collateral
     * @param token ERC20 token to withdraw
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external;

    // ═══════════════════════════════════════════════════════════════════════
    // OPTIONS CONTRACT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Lock collateral for an option position (called by Options contract)
     * @param user Writer address
     * @param token Collateral token
     * @param amount Amount to lock
     */
    function lockCollateral(address user, address token, uint256 amount) external;

    /**
     * @notice Release collateral from a closed position (called by Options contract)
     * @param user Writer address
     * @param token Collateral token
     * @param amount Amount to release
     */
    function releaseCollateral(address user, address token, uint256 amount) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get available (unlocked) collateral for a user
     * @param user User address
     * @param token Token address
     * @return Available collateral
     */
    function getAvailableCollateral(address user, address token) external view returns (uint256);

    /**
     * @notice Get the maintenance margin requirement for a user
     * @param user User address
     * @param token Token address
     * @return Maintenance margin requirement
     */
    function getMaintenanceRequirement(address user, address token) external view returns (uint256);

    /**
     * @notice Get account details
     * @param user User address
     * @param token Token address
     * @return Account data
     */
    function getAccount(address user, address token) external view returns (Account memory);

    /**
     * @notice Calculate spread margin reduction for a user holding a long position
     * @param user User address
     * @param shortSeriesId Series written (short)
     * @param longSeriesId Series held (long)
     * @param quantity Position size
     * @return reduction Amount of collateral reduction from spread
     */
    function calculateSpreadMargin(address user, uint256 shortSeriesId, uint256 longSeriesId, uint256 quantity)
        external
        view
        returns (uint256 reduction);
}
