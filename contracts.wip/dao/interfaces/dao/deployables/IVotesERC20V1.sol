// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

/**
 * @title IVotesERC20V1
 * @notice Governance token with voting capabilities and transfer restrictions
 * @dev This interface defines a flexible governance token that extends ERC20 with voting
 * delegation features and optional transfer restrictions. It supports snapshots for
 * historical voting power queries and can be configured as non-transferable.
 *
 * Key features:
 * - ERC20Votes compatibility for governance systems
 * - Optional transfer locking (non-transferable tokens)
 * - Maximum supply cap enforcement
 * - Role-based transfer overrides when locked
 * - Timestamp-based voting snapshots
 * - Minting controlled by role
 *
 * Usage:
 * - Primary governance token for DAOs
 * - Voting weight in Azorius proposals
 * - Can be locked to prevent token transfers
 * - Supports delegation for liquid democracy
 */
interface IVotesERC20V1 {
    // --- Errors ---

    /** @notice Thrown when attempting transfers on a locked (non-transferable) token */
    error IsLocked();

    /** @notice Thrown when locking token from unlocked state */
    error LockFromUnlockedState();

    /** @notice Thrown when minting is disabled */
    error MintingDisabled();

    /** @notice Thrown when minting would exceed the maximum total supply */
    error ExceedMaxTotalSupply();

    /** @notice Thrown when setting max supply below current total supply */
    error InvalidMaxTotalSupply();

    // --- Events ---

    /**
     * @notice Emitted when the token's transfer lock status changes
     * @param isLocked True if transfers are now locked, false if unlocked
     */
    event Locked(bool isLocked);

    /**
     * @notice Emitted when the token's minting is renounced
     */
    event MintingRenounced();

    /**
     * @notice Emitted when the maximum total supply is updated
     * @param newMaxTotalSupply The new maximum supply cap
     */
    event MaxTotalSupplyUpdated(uint256 newMaxTotalSupply);

    // --- Structs ---

    /**
     * @notice Token metadata
     * @param name The token name (e.g., "MyDAO Governance Token")
     * @param symbol The token symbol (e.g., "MYDAO")
     */
    struct Metadata {
        string name;
        string symbol;
    }

    /**
     * @notice Initial token allocation
     * @param to Recipient address
     * @param amount Number of tokens to allocate
     */
    struct Allocation {
        address to;
        uint256 amount;
    }

    // --- Initializer Functions ---

    /**
     * @notice Initializes the governance token with initial allocations
     * @dev Can only be called once during deployment. Sets up the token with
     * initial distribution and configuration. Decimals are fixed at 18.
     * @param metadata_ Token name and symbol
     * @param allocations_ Initial token distributions
     * @param owner_ Address that will have admin and minter roles
     * @param locked_ Whether the token should be non-transferable
     * @param maxTotalSupply_ Maximum supply cap
     */
    function initialize(
        Metadata calldata metadata_,
        Allocation[] calldata allocations_,
        address owner_,
        bool locked_,
        uint256 maxTotalSupply_
    ) external;

    // --- Pure Functions ---

    /**
     * @notice Returns the clock mode for voting snapshots
     * @dev Returns "mode=timestamp" indicating timestamp-based timing
     * @return clockMode The clock mode string per EIP-6372
     */
    function CLOCK_MODE() external pure returns (string memory clockMode);
    // solhint-disable-previous-line func-name-mixedcase

    // --- View Functions ---

    /**
     * @notice Returns the current clock value (timestamp)
     * @dev Used for voting snapshot timing, returns current block timestamp
     * @return clock The current timestamp as uint48
     */
    function clock() external view returns (uint48 clock);

    /**
     * @notice Returns whether the token is locked (non-transferable)
     * @dev When locked, only addresses with special roles can transfer
     * @return isLocked True if transfers are restricted
     */
    function locked() external view returns (bool isLocked);

    /**
     * @notice Returns whether minting is disabled
     * @dev When disabled, no new tokens can be minted
     * @return isMintingRenounced True if minting is disabled
     */
    function mintingRenounced() external view returns (bool isMintingRenounced);

    /**
     * @notice Returns the maximum total supply cap
     * @return maxTotalSupply The maximum number of tokens that can exist
     */
    function maxTotalSupply() external view returns (uint256 maxTotalSupply);

    /**
     * @notice Returns when the token was last unlocked
     * @dev Returns the timestamp of the most recent unlock operation.
     * Updated whenever lock(false) is called. Returns 0 if never unlocked.
     * @return unlockTime The timestamp when the token was last unlocked
     */
    function getUnlockTime() external view returns (uint48 unlockTime);

    // --- State-Changing Functions ---

    /**
     * @notice Updates the token's transfer lock status
     * @dev Only callable by admin. When unlocking, records the timestamp in unlockTime.
     * @param locked_ True to lock transfers, false to unlock
     * @custom:access Restricted to admin role
     * @custom:emits Locked
     */
    function lock(bool locked_) external;

    /**
     * @notice Renounces the ability to mint new tokens
     * @dev Only callable by admin. Once called, minting is permanently disabled.
     * @custom:access Restricted to admin role
     * @custom:emits MintingDisabled
     */
    function renounceMinting() external;

    /**
     * @notice Updates the maximum total supply cap
     * @dev Only callable by admin. Cannot set below current total supply.
     * @param newMaxTotalSupply_ The new maximum supply
     * @custom:access Restricted to admin role
     * @custom:throws InvalidMaxTotalSupply if below current supply
     * @custom:emits MaxTotalSupplyUpdated
     */
    function setMaxTotalSupply(uint256 newMaxTotalSupply_) external;

    /**
     * @notice Mints new tokens to a specified address
     * @dev Only callable by addresses with MINTER_ROLE. Respects max supply.
     * @param to_ The address to receive tokens
     * @param amount_ The number of tokens to mint
     * @custom:access Restricted to minter role
     * @custom:throws ExceedMaxTotalSupply if would exceed cap
     */
    function mint(address to_, uint256 amount_) external;

    /**
     * @notice Burns tokens from the caller's balance
     * @dev Anyone can burn their own tokens. No access control.
     * Works even when the token is locked.
     * @param amount_ The number of tokens to burn
     */
    function burn(uint256 amount_) external;
}
