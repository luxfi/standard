// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDead - Dead Precompile Interface (Configurable)
/// @notice Routes burns to dead addresses (0x0, 0xdead) to DAO treasury
/// @dev LP-aligned address: P=0 (Core), C=0 (Universal), II=dead
/// @dev Deployed at 0x000000000000000000000000000000000000dEaD
///
/// The Dead Precompile intercepts all transfers to "dead" addresses and routes them:
/// - Configurable burn ratio (default 50%) actually burned (deflationary)
/// - Remainder to X-Chain DAO treasury (protocol-owned liquidity)
///
/// Settings are configurable per-chain via admin (DAO MPC / governance gauges):
/// - Admin can set treasury address
/// - Admin can adjust burn/treasury ratio (0-100%)
/// - Admin can enable/disable the precompile
///
/// To truly delete an asset, users must destroy the contract itself.
///
/// See: LP-0150 Dead Precompile specification
interface IDead {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when ERC20 tokens are routed through Dead Precompile
    /// @param token The token address
    /// @param sender The address that sent to dead address
    /// @param totalAmount Total amount sent
    /// @param burnedAmount Amount actually burned
    /// @param treasuryAmount Amount sent to treasury
    event BurnRouted(
        address indexed token,
        address indexed sender,
        uint256 totalAmount,
        uint256 burnedAmount,
        uint256 treasuryAmount
    );

    /// @notice Emitted when native LUX is routed through Dead Precompile
    /// @param sender The address that sent to dead address
    /// @param totalAmount Total amount sent
    /// @param burnedAmount Amount actually burned
    /// @param treasuryAmount Amount sent to treasury
    event NativeBurnRouted(
        address indexed sender,
        uint256 totalAmount,
        uint256 burnedAmount,
        uint256 treasuryAmount
    );

    /// @notice Emitted when admin is changed
    /// @param previousAdmin The previous admin address
    /// @param newAdmin The new admin address
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);

    /// @notice Emitted when treasury is changed
    /// @param previousTreasury The previous treasury address
    /// @param newTreasury The new treasury address
    event TreasuryChanged(address indexed previousTreasury, address indexed newTreasury);

    /// @notice Emitted when burn ratio is changed
    /// @param previousRatio The previous burn ratio in basis points
    /// @param newRatio The new burn ratio in basis points
    event BurnRatioChanged(uint256 previousRatio, uint256 newRatio);

    /// @notice Emitted when precompile is enabled/disabled
    /// @param enabled Whether the precompile is now enabled
    event EnabledChanged(bool enabled);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when caller is not the admin
    error NotAdmin();

    /// @notice Thrown when treasury address is not set
    error TreasuryNotSet();

    /// @notice Thrown when transfer to treasury fails
    error TreasuryTransferFailed();

    /// @notice Thrown when burn ratio exceeds maximum (10000 bps = 100%)
    error InvalidBurnRatio();

    /// @notice Thrown when precompile is disabled
    error PrecompileDisabled();

    /// @notice Thrown when setting zero address as admin
    error ZeroAdmin();

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The primary zero address
    /// @return The zero address
    function ZERO_ADDRESS() external pure returns (address);

    /// @notice The standard dead address
    /// @return The dead address (0x...dEaD)
    function DEAD_ADDRESS() external pure returns (address);

    /// @notice Maximum burn ratio in basis points (10000 = 100%)
    /// @return The maximum burn ratio
    function MAX_BURN_RATIO_BPS() external pure returns (uint256);

    /// @notice Basis points denominator
    /// @return 10000
    function BPS_DENOMINATOR() external pure returns (uint256);

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the current admin address
    /// @return The admin address that can configure the precompile
    function getAdmin() external view returns (address);

    /// @notice Set a new admin address
    /// @param newAdmin The new admin address
    /// @dev Only callable by current admin
    function setAdmin(address newAdmin) external;

    /// @notice Get the DAO treasury address
    /// @return The treasury address that receives the treasury portion
    function getTreasury() external view returns (address);

    /// @notice Set the DAO treasury address
    /// @param newTreasury The new treasury address
    /// @dev Only callable by admin
    function setTreasury(address newTreasury) external;

    /// @notice Get the current burn ratio in basis points
    /// @return The burn ratio (0-10000, where 10000 = 100% burned)
    function getBurnRatio() external view returns (uint256);

    /// @notice Set the burn ratio in basis points
    /// @param newRatio The new burn ratio (0-10000)
    /// @dev Only callable by admin
    /// @dev 0 = all to treasury, 10000 = all burned
    function setBurnRatio(uint256 newRatio) external;

    /// @notice Check if the precompile is enabled
    /// @return True if the precompile is active
    function isEnabled() external view returns (bool);

    /// @notice Enable or disable the precompile
    /// @param enabled Whether to enable or disable
    /// @dev Only callable by admin
    /// @dev When disabled, transfers to dead addresses pass through unchanged
    function setEnabled(bool enabled) external;

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the DAO treasury address (legacy alias for getTreasury)
    /// @return The treasury address that receives the treasury portion
    function treasury() external view returns (address);

    /// @notice Check if an address is considered "dead"
    /// @param addr The address to check
    /// @return True if transfers to this address trigger the Dead Precompile
    /// @dev Returns true for:
    ///      - 0x0000000000000000000000000000000000000000
    ///      - 0x000000000000000000000000000000000000dEaD
    ///      - 0xdEaD000000000000000000000000000000000000
    ///      - Any address < 0x100 (first 256 addresses)
    function isDeadAddress(address addr) external pure returns (bool);

    /// @notice Get total amount burned through this precompile (native)
    /// @return Total burned amount in native units (wei)
    function totalBurned() external view returns (uint256);

    /// @notice Get total amount sent to treasury through this precompile (native)
    /// @return Total treasury amount in native units (wei)
    function totalToTreasury() external view returns (uint256);

    /// @notice Get burn/treasury statistics for a specific token
    /// @param token The token address (address(0) for native LUX)
    /// @return burned Total amount burned for this token
    /// @return toTreasury Total amount sent to treasury for this token
    function tokenStats(address token) external view returns (uint256 burned, uint256 toTreasury);

    /// @notice Get all-time statistics
    /// @return nativeBurned Total native LUX burned
    /// @return nativeToTreasury Total native LUX to treasury
    /// @return tokenCount Number of unique tokens routed
    function stats() external view returns (
        uint256 nativeBurned,
        uint256 nativeToTreasury,
        uint256 tokenCount
    );

    /// @notice Calculate split amounts for a given value
    /// @param amount The total amount to split
    /// @return burnAmount The amount that will be burned
    /// @return treasuryAmount The amount that will go to treasury
    function calculateSplit(uint256 amount) external view returns (uint256 burnAmount, uint256 treasuryAmount);
}

/// @title Dead - Dead Precompile Library
/// @notice Utilities for working with the Dead Precompile
library Dead {
    /// @notice The Dead Precompile address
    /// @dev The precompile lives at 0xdead itself - thematically appropriate!
    address public constant PRECOMPILE = 0x000000000000000000000000000000000000dEaD;

    /// @notice The zero address (primary dead address)
    address public constant ZERO = address(0);

    /// @notice The standard dead address
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @notice The alternate dead address (dead prefix)
    address public constant DEAD_FULL = 0xdEad000000000000000000000000000000000000;

    /// @notice Default burn ratio (5000 = 50%)
    uint256 public constant DEFAULT_BURN_RATIO = 5000;

    /// @notice Default treasury ratio (5000 = 50%)
    uint256 public constant DEFAULT_TREASURY_RATIO = 5000;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    /// @notice Check if an address is a dead address
    /// @param addr The address to check
    /// @return True if the address triggers the Dead Precompile
    function isDeadAddress(address addr) internal pure returns (bool) {
        // Explicit dead addresses
        if (addr == ZERO || addr == DEAD || addr == DEAD_FULL) {
            return true;
        }
        // Pattern: any address < 0x100 (first 256 addresses reserved)
        if (uint160(addr) < 0x100) {
            return true;
        }
        return false;
    }

    /// @notice Calculate the burn amount using current on-chain ratio
    /// @param amount The total amount
    /// @return The amount that will be burned
    function burnAmount(uint256 amount) internal view returns (uint256) {
        uint256 ratio = precompile().getBurnRatio();
        return (amount * ratio) / BPS;
    }

    /// @notice Calculate the treasury amount using current on-chain ratio
    /// @param amount The total amount
    /// @return The amount that will go to treasury
    function treasuryAmount(uint256 amount) internal view returns (uint256) {
        return amount - burnAmount(amount);
    }

    /// @notice Calculate burn amount with a specific ratio
    /// @param amount The total amount
    /// @param burnRatioBps The burn ratio in basis points
    /// @return The amount that will be burned
    function burnAmountWithRatio(uint256 amount, uint256 burnRatioBps) internal pure returns (uint256) {
        return (amount * burnRatioBps) / BPS;
    }

    /// @notice Calculate treasury amount with a specific ratio
    /// @param amount The total amount
    /// @param burnRatioBps The burn ratio in basis points
    /// @return The amount that will go to treasury
    function treasuryAmountWithRatio(uint256 amount, uint256 burnRatioBps) internal pure returns (uint256) {
        return amount - burnAmountWithRatio(amount, burnRatioBps);
    }

    /// @notice Get the Dead Precompile interface
    /// @return The IDead interface at the precompile address
    function precompile() internal pure returns (IDead) {
        return IDead(PRECOMPILE);
    }

    /// @notice Get the current treasury address from the precompile
    /// @return The configured treasury address
    function getTreasury() internal view returns (address) {
        return precompile().getTreasury();
    }

    /// @notice Get the current burn ratio from the precompile
    /// @return The configured burn ratio in basis points
    function getBurnRatio() internal view returns (uint256) {
        return precompile().getBurnRatio();
    }

    /// @notice Check if the precompile is currently enabled
    /// @return True if enabled
    function isEnabled() internal view returns (bool) {
        return precompile().isEnabled();
    }
}
