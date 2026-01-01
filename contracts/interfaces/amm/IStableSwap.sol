// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IStableSwap
 * @author Lux Industries
 * @notice Interface for Curve-style StableSwap AMM optimized for stablecoins and pegged assets
 * @dev Implements the StableSwap invariant: A * n^n * sum(x_i) + D = A * D * n^n + D^(n+1) / (n^n * prod(x_i))
 */
interface IStableSwap {
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when token count is invalid (must be 2-4)
    error InvalidTokenCount();

    /// @notice Thrown when duplicate token is provided
    error DuplicateToken();

    /// @notice Thrown when token address is invalid
    error InvalidToken();

    /// @notice Thrown when output amount is below minimum
    error InsufficientOutput();

    /// @notice Thrown when liquidity is insufficient for operation
    error InsufficientLiquidity();

    /// @notice Thrown when invariant calculation fails
    error InvariantViolation();

    /// @notice Thrown when transaction deadline has passed
    error DeadlineExpired();

    /// @notice Thrown when pool is killed (emergency mode)
    error PoolKilled();

    /// @notice Thrown when fee exceeds maximum allowed
    error InvalidFee();

    /// @notice Thrown when amplification coefficient is invalid
    error InvalidA();

    /// @notice Thrown when a ramp is already active
    error RampActive();

    /// @notice Thrown when trying to ramp too soon after previous ramp
    error RampTooSoon();

    /// @notice Thrown when A change exceeds maximum allowed
    error RampChangeTooLarge();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when token index is out of range
    error TokenIndexOutOfRange();

    /// @notice Thrown when Newton's method fails to converge
    error ConvergenceFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when tokens are exchanged
     * @param buyer Address of the buyer
     * @param soldId Index of token sold
     * @param tokensSold Amount of tokens sold
     * @param boughtId Index of token bought
     * @param tokensBought Amount of tokens bought
     */
    event TokenExchange(
        address indexed buyer,
        uint256 soldId,
        uint256 tokensSold,
        uint256 boughtId,
        uint256 tokensBought
    );

    /**
     * @notice Emitted when liquidity is added
     * @param provider Address of liquidity provider
     * @param tokenAmounts Amounts of each token added
     * @param fees Fees charged for imbalanced deposit
     * @param invariant Pool invariant after deposit
     * @param lpTokenSupply Total LP token supply after mint
     */
    event AddLiquidity(
        address indexed provider,
        uint256[] tokenAmounts,
        uint256[] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );

    /**
     * @notice Emitted when liquidity is removed proportionally
     * @param provider Address of liquidity provider
     * @param tokenAmounts Amounts of each token removed
     * @param fees Fees charged (zero for proportional)
     * @param lpTokenSupply Total LP token supply after burn
     */
    event RemoveLiquidity(
        address indexed provider,
        uint256[] tokenAmounts,
        uint256[] fees,
        uint256 lpTokenSupply
    );

    /**
     * @notice Emitted when liquidity is removed in a single token
     * @param provider Address of liquidity provider
     * @param tokenIndex Index of token withdrawn
     * @param tokenAmount LP tokens burned
     * @param coinAmount Amount of token received
     */
    event RemoveLiquidityOne(
        address indexed provider,
        uint256 tokenIndex,
        uint256 tokenAmount,
        uint256 coinAmount
    );

    /**
     * @notice Emitted when liquidity is removed in imbalanced amounts
     * @param provider Address of liquidity provider
     * @param tokenAmounts Amounts of each token removed
     * @param fees Fees charged for imbalanced withdrawal
     * @param invariant Pool invariant after withdrawal
     * @param lpTokenSupply Total LP token supply after burn
     */
    event RemoveLiquidityImbalance(
        address indexed provider,
        uint256[] tokenAmounts,
        uint256[] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );

    /**
     * @notice Emitted when amplification coefficient ramp starts
     * @param oldA Previous A value
     * @param newA Target A value
     * @param initialTime Ramp start time
     * @param futureTime Ramp end time
     */
    event RampA(
        uint256 oldA,
        uint256 newA,
        uint256 initialTime,
        uint256 futureTime
    );

    /**
     * @notice Emitted when A ramp is stopped
     * @param A Current A value
     * @param t Timestamp when stopped
     */
    event StopRampA(uint256 A, uint256 t);

    /**
     * @notice Emitted when admin fees are collected
     * @param collector Address that collected fees
     * @param amounts Amounts collected per token
     */
    event FeesCollected(address indexed collector, uint256[] amounts);

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current amplification coefficient
     * @return Current A value (without precision)
     */
    function A() external view returns (uint256);

    /**
     * @notice Get amplification coefficient with precision
     * @return Current A value with A_PRECISION multiplier
     */
    function APrecise() external view returns (uint256);

    /**
     * @notice Get number of tokens in pool
     * @return Number of tokens (2-4)
     */
    function nCoins() external view returns (uint256);

    /**
     * @notice Get token at index
     * @param i Token index
     * @return Token address
     */
    function getToken(uint256 i) external view returns (address);

    /**
     * @notice Get all tokens
     * @return Array of token addresses
     */
    function getTokens() external view returns (address[] memory);

    /**
     * @notice Get balance of token at index
     * @param i Token index
     * @return Normalized balance (18 decimals)
     */
    function getBalance(uint256 i) external view returns (uint256);

    /**
     * @notice Get all balances
     * @return Array of normalized balances
     */
    function getBalances() external view returns (uint256[] memory);

    /**
     * @notice Get virtual price of LP token
     * @dev Price of one LP token in terms of underlying tokens
     * @return Virtual price (18 decimals)
     */
    function getVirtualPrice() external view returns (uint256);

    /**
     * @notice Calculate output amount for a swap
     * @param i Index of input token
     * @param j Index of output token
     * @param dx Amount of input token
     * @return Expected output amount (after fees)
     */
    function getSwapAmount(uint256 i, uint256 j, uint256 dx) external view returns (uint256);

    /**
     * @notice Calculate LP tokens for adding/removing liquidity
     * @param amounts Array of token amounts
     * @param isDeposit True for deposit, false for withdrawal
     * @return Amount of LP tokens to mint/burn
     */
    function calcTokenAmount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);

    /**
     * @notice Calculate amount received for withdrawing single token
     * @param tokenAmount LP tokens to burn
     * @param i Index of token to withdraw
     * @return Amount of token received
     */
    function calcWithdrawOneCoin(uint256 tokenAmount, uint256 i) external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════
    // SWAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Swap token i for token j
     * @param i Index of input token
     * @param j Index of output token
     * @param dx Amount of token i to swap
     * @param minDy Minimum amount of token j to receive
     * @param deadline Transaction deadline
     * @return dy Amount of token j received
     */
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external returns (uint256 dy);

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDITY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add liquidity to the pool
     * @param amounts Array of token amounts to add
     * @param minMintAmount Minimum LP tokens to receive
     * @param deadline Transaction deadline
     * @return mintAmount Amount of LP tokens minted
     */
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minMintAmount,
        uint256 deadline
    ) external returns (uint256 mintAmount);

    /**
     * @notice Remove liquidity proportionally
     * @param amount LP tokens to burn
     * @param minAmounts Minimum amounts of each token to receive
     * @param deadline Transaction deadline
     * @return amounts Actual amounts received
     */
    function removeLiquidity(
        uint256 amount,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Remove liquidity in a single token
     * @param tokenAmount LP tokens to burn
     * @param i Index of token to withdraw
     * @param minAmount Minimum amount to receive
     * @param deadline Transaction deadline
     * @return dy Amount of token received
     */
    function removeLiquidityOneCoin(
        uint256 tokenAmount,
        uint256 i,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256 dy);

    /**
     * @notice Remove liquidity in imbalanced amounts
     * @param amounts Exact amounts to withdraw
     * @param maxBurnAmount Maximum LP tokens to burn
     * @param deadline Transaction deadline
     * @return burnAmount Actual LP tokens burned
     */
    function removeLiquidityImbalance(
        uint256[] calldata amounts,
        uint256 maxBurnAmount,
        uint256 deadline
    ) external returns (uint256 burnAmount);

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Start ramping A to a new value
     * @dev Must be called by ADMIN_ROLE
     * @param futureA_ Target A value
     * @param futureTime_ Time when ramp completes
     */
    function rampA(uint256 futureA_, uint256 futureTime_) external;

    /**
     * @notice Stop ramping A immediately
     * @dev Must be called by ADMIN_ROLE
     */
    function stopRampA() external;
}
