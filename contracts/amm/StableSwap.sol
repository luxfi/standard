// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StableSwap
 * @author Lux Industries
 * @notice Curve-style StableSwap AMM optimized for stablecoins and pegged assets
 * @dev Implements the StableSwap invariant: A * n^n * sum(x_i) + D = A * D * n^n + D^(n+1) / (n^n * prod(x_i))
 *      This provides low-slippage swaps for assets that should trade near 1:1
 *
 * Key features:
 * - Dynamic amplification coefficient (A) for optimal liquidity
 * - Support for 2-4 tokens per pool
 * - Admin fees separate from LP fees
 * - Ramping A for safe parameter updates
 */
contract StableSwap is ERC20, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant FEE_DENOMINATOR = 1e10;
    uint256 public constant MAX_FEE = 5e8; // 5%
    uint256 public constant MAX_ADMIN_FEE = 1e10; // 100% of swap fee
    uint256 public constant MAX_A = 1e6;
    uint256 public constant A_PRECISION = 100;
    uint256 public constant MIN_RAMP_TIME = 1 days;
    uint256 public constant MAX_A_CHANGE = 10;
    uint256 private constant PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Pool tokens (stablecoins)
    address[] public tokens;

    /// @notice Token decimals for normalization
    uint256[] public tokenDecimals;

    /// @notice Token balances (normalized to 18 decimals)
    uint256[] public balances;

    /// @notice Swap fee (in FEE_DENOMINATOR units, e.g., 4e6 = 0.04%)
    uint256 public fee;

    /// @notice Admin fee as percentage of swap fee (e.g., 5e9 = 50%)
    uint256 public adminFee;

    /// @notice Accumulated admin fees per token
    uint256[] public adminBalances;

    /// @notice Initial amplification coefficient
    uint256 public initialA;

    /// @notice Future amplification coefficient (after ramp)
    uint256 public futureA;

    /// @notice Ramp start time
    uint256 public initialATime;

    /// @notice Ramp end time
    uint256 public futureATime;

    /// @notice Pool is killed (withdrawals only)
    bool public isKilled;

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidTokenCount();
    error DuplicateToken();
    error InvalidToken();
    error InsufficientOutput();
    error InsufficientLiquidity();
    error InvariantViolation();
    error DeadlineExpired();
    error PoolKilled();
    error InvalidFee();
    error InvalidA();
    error RampActive();
    error RampTooSoon();
    error RampChangeTooLarge();
    error ZeroAmount();
    error TokenIndexOutOfRange();
    error ConvergenceFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event TokenExchange(
        address indexed buyer,
        uint256 soldId,
        uint256 tokensSold,
        uint256 boughtId,
        uint256 tokensBought
    );

    event AddLiquidity(
        address indexed provider,
        uint256[] tokenAmounts,
        uint256[] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );

    event RemoveLiquidity(
        address indexed provider,
        uint256[] tokenAmounts,
        uint256[] fees,
        uint256 lpTokenSupply
    );

    event RemoveLiquidityOne(
        address indexed provider,
        uint256 tokenIndex,
        uint256 tokenAmount,
        uint256 coinAmount
    );

    event RemoveLiquidityImbalance(
        address indexed provider,
        uint256[] tokenAmounts,
        uint256[] fees,
        uint256 invariant,
        uint256 lpTokenSupply
    );

    event RampA(
        uint256 oldA,
        uint256 newA,
        uint256 initialTime,
        uint256 futureTime
    );

    event StopRampA(uint256 A, uint256 t);

    event FeesCollected(address indexed collector, uint256[] amounts);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploy a new StableSwap pool
     * @param _tokens Array of token addresses (2-4 tokens)
     * @param _decimals Array of token decimals
     * @param _name LP token name
     * @param _symbol LP token symbol
     * @param _A Initial amplification coefficient (e.g., 100)
     * @param _fee Swap fee (e.g., 4e6 for 0.04%)
     * @param _adminFee Admin fee as % of swap fee (e.g., 5e9 for 50%)
     * @param _admin Admin address
     */
    constructor(
        address[] memory _tokens,
        uint256[] memory _decimals,
        string memory _name,
        string memory _symbol,
        uint256 _A,
        uint256 _fee,
        uint256 _adminFee,
        address _admin
    ) ERC20(_name, _symbol) {
        if (_tokens.length < 2 || _tokens.length > 4) revert InvalidTokenCount();
        if (_tokens.length != _decimals.length) revert InvalidTokenCount();
        if (_A == 0 || _A > MAX_A) revert InvalidA();
        if (_fee > MAX_FEE) revert InvalidFee();
        if (_adminFee > MAX_ADMIN_FEE) revert InvalidFee();

        // Validate tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == address(0)) revert InvalidToken();
            for (uint256 j = 0; j < i; j++) {
                if (_tokens[i] == _tokens[j]) revert DuplicateToken();
            }
        }

        tokens = _tokens;
        tokenDecimals = _decimals;
        fee = _fee;
        adminFee = _adminFee;

        initialA = _A * A_PRECISION;
        futureA = _A * A_PRECISION;
        initialATime = block.timestamp;
        futureATime = block.timestamp;

        // Initialize balance arrays
        balances = new uint256[](_tokens.length);
        adminBalances = new uint256[](_tokens.length);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get current amplification coefficient
    function A() public view returns (uint256) {
        return _A() / A_PRECISION;
    }

    /// @notice Get amplification coefficient with precision
    function APrecise() public view returns (uint256) {
        return _A();
    }

    /// @notice Get number of tokens in pool
    function nCoins() public view returns (uint256) {
        return tokens.length;
    }

    /// @notice Get token at index
    function getToken(uint256 i) external view returns (address) {
        return tokens[i];
    }

    /// @notice Get all tokens
    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    /// @notice Get balance of token at index
    function getBalance(uint256 i) external view returns (uint256) {
        return balances[i];
    }

    /// @notice Get all balances
    function getBalances() external view returns (uint256[] memory) {
        return balances;
    }

    /// @notice Get virtual price (price of LP token in underlying)
    function getVirtualPrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return PRECISION;
        uint256 D = _getD(balances, _A());
        return (D * PRECISION) / supply;
    }

    /// @notice Calculate output amount for a swap
    function getSwapAmount(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256) {
        return _getSwapAmount(i, j, dx);
    }

    /// @notice Calculate LP tokens for adding liquidity
    function calcTokenAmount(
        uint256[] calldata amounts,
        bool isDeposit
    ) external view returns (uint256) {
        return _calcTokenAmount(amounts, isDeposit);
    }

    /// @notice Calculate amount received for withdrawing single token
    function calcWithdrawOneCoin(
        uint256 tokenAmount,
        uint256 i
    ) external view returns (uint256) {
        return _calcWithdrawOneCoin(tokenAmount, i);
    }

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
    ) external nonReentrant returns (uint256 dy) {
        if (isKilled) revert PoolKilled();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (dx == 0) revert ZeroAmount();
        if (i >= tokens.length || j >= tokens.length) revert TokenIndexOutOfRange();
        if (i == j) revert InvalidToken();

        // Transfer tokens in
        IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), dx);

        // Normalize to 18 decimals
        uint256 dxNorm = _normalize(dx, tokenDecimals[i]);

        // Calculate output
        dy = _exchange(i, j, dxNorm);

        if (dy < minDy) revert InsufficientOutput();

        // Denormalize and transfer out
        uint256 dyActual = _denormalize(dy, tokenDecimals[j]);
        IERC20(tokens[j]).safeTransfer(msg.sender, dyActual);

        emit TokenExchange(msg.sender, i, dx, j, dyActual);
    }

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
    ) external nonReentrant returns (uint256 mintAmount) {
        if (isKilled) revert PoolKilled();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (amounts.length != tokens.length) revert InvalidTokenCount();

        uint256 _A = _A();
        uint256 D0 = 0;
        uint256[] memory oldBalances = balances;

        if (totalSupply() > 0) {
            D0 = _getD(oldBalances, _A);
        }

        uint256[] memory newBalances = new uint256[](tokens.length);
        uint256[] memory fees = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
                newBalances[i] = oldBalances[i] + _normalize(amounts[i], tokenDecimals[i]);
            } else {
                newBalances[i] = oldBalances[i];
            }
        }

        uint256 D1 = _getD(newBalances, _A);
        if (D1 <= D0) revert InvariantViolation();

        uint256 D2 = D1;
        uint256 supply = totalSupply();

        if (supply > 0) {
            // Calculate imbalance fees
            uint256 _fee = (fee * tokens.length) / (4 * (tokens.length - 1));
            uint256 _adminFee = adminFee;

            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 idealBalance = (D1 * oldBalances[i]) / D0;
                uint256 diff = idealBalance > newBalances[i]
                    ? idealBalance - newBalances[i]
                    : newBalances[i] - idealBalance;
                fees[i] = (_fee * diff) / FEE_DENOMINATOR;
                adminBalances[i] += (fees[i] * _adminFee) / FEE_DENOMINATOR;
                newBalances[i] -= fees[i];
            }
            D2 = _getD(newBalances, _A);
            mintAmount = (supply * (D2 - D0)) / D0;
        } else {
            mintAmount = D1;
        }

        if (mintAmount < minMintAmount) revert InsufficientOutput();

        // Update balances
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = newBalances[i];
        }

        _mint(msg.sender, mintAmount);

        emit AddLiquidity(msg.sender, amounts, fees, D2, supply + mintAmount);
    }

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
    ) external nonReentrant returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (minAmounts.length != tokens.length) revert InvalidTokenCount();

        uint256 supply = totalSupply();
        amounts = new uint256[](tokens.length);
        uint256[] memory fees = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 value = (balances[i] * amount) / supply;
            if (value < minAmounts[i]) revert InsufficientOutput();

            balances[i] -= value;
            uint256 actualAmount = _denormalize(value, tokenDecimals[i]);
            amounts[i] = actualAmount;
            IERC20(tokens[i]).safeTransfer(msg.sender, actualAmount);
        }

        _burn(msg.sender, amount);

        emit RemoveLiquidity(msg.sender, amounts, fees, supply - amount);
    }

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
    ) external nonReentrant returns (uint256 dy) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (i >= tokens.length) revert TokenIndexOutOfRange();

        uint256 dyFee;
        (dy, dyFee) = _calcWithdrawOneCoinWithFee(tokenAmount, i);

        if (dy < minAmount) revert InsufficientOutput();

        balances[i] -= (dy + (dyFee * adminFee) / FEE_DENOMINATOR);
        adminBalances[i] += (dyFee * adminFee) / FEE_DENOMINATOR;

        _burn(msg.sender, tokenAmount);

        uint256 actualAmount = _denormalize(dy, tokenDecimals[i]);
        IERC20(tokens[i]).safeTransfer(msg.sender, actualAmount);

        emit RemoveLiquidityOne(msg.sender, i, tokenAmount, actualAmount);
    }

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
    ) external nonReentrant returns (uint256 burnAmount) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (amounts.length != tokens.length) revert InvalidTokenCount();

        uint256 _A = _A();
        uint256[] memory oldBalances = balances;
        uint256 D0 = _getD(oldBalances, _A);

        uint256[] memory newBalances = new uint256[](tokens.length);
        uint256[] memory fees = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amountNorm = _normalize(amounts[i], tokenDecimals[i]);
            newBalances[i] = oldBalances[i] - amountNorm;
        }

        uint256 D1 = _getD(newBalances, _A);

        // Calculate fees
        uint256 _fee = (fee * tokens.length) / (4 * (tokens.length - 1));
        uint256 _adminFee = adminFee;

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 idealBalance = (D1 * oldBalances[i]) / D0;
            uint256 diff = idealBalance > newBalances[i]
                ? idealBalance - newBalances[i]
                : newBalances[i] - idealBalance;
            fees[i] = (_fee * diff) / FEE_DENOMINATOR;
            adminBalances[i] += (fees[i] * _adminFee) / FEE_DENOMINATOR;
            newBalances[i] -= fees[i];
        }

        uint256 D2 = _getD(newBalances, _A);

        uint256 supply = totalSupply();
        burnAmount = ((D0 - D2) * supply) / D0 + 1; // +1 for rounding

        if (burnAmount > maxBurnAmount) revert InsufficientLiquidity();

        // Update balances
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = newBalances[i];
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransfer(msg.sender, amounts[i]);
            }
        }

        _burn(msg.sender, burnAmount);

        emit RemoveLiquidityImbalance(msg.sender, amounts, fees, D2, supply - burnAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Start ramping A to a new value
     * @param futureA_ Target A value
     * @param futureTime_ Time when ramp completes
     */
    function rampA(
        uint256 futureA_,
        uint256 futureTime_
    ) external onlyRole(ADMIN_ROLE) {
        if (block.timestamp < initialATime + MIN_RAMP_TIME) revert RampTooSoon();
        if (futureTime_ < block.timestamp + MIN_RAMP_TIME) revert RampTooSoon();

        uint256 currentA = _A();
        uint256 _futureA = futureA_ * A_PRECISION;

        if (_futureA == 0 || _futureA > MAX_A * A_PRECISION) revert InvalidA();
        if (
            (_futureA > currentA && _futureA > currentA * MAX_A_CHANGE) ||
            (_futureA < currentA && currentA > _futureA * MAX_A_CHANGE)
        ) revert RampChangeTooLarge();

        initialA = currentA;
        futureA = _futureA;
        initialATime = block.timestamp;
        futureATime = futureTime_;

        emit RampA(currentA, _futureA, block.timestamp, futureTime_);
    }

    /// @notice Stop ramping A
    function stopRampA() external onlyRole(ADMIN_ROLE) {
        uint256 currentA = _A();
        initialA = currentA;
        futureA = currentA;
        initialATime = block.timestamp;
        futureATime = block.timestamp;

        emit StopRampA(currentA, block.timestamp);
    }

    /// @notice Set swap fee
    function setFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
        if (_fee > MAX_FEE) revert InvalidFee();
        fee = _fee;
    }

    /// @notice Set admin fee
    function setAdminFee(uint256 _adminFee) external onlyRole(ADMIN_ROLE) {
        if (_adminFee > MAX_ADMIN_FEE) revert InvalidFee();
        adminFee = _adminFee;
    }

    /// @notice Collect accumulated admin fees
    function collectAdminFees() external onlyRole(OPERATOR_ROLE) {
        uint256[] memory collected = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = _denormalize(adminBalances[i], tokenDecimals[i]);
            if (amount > 0) {
                adminBalances[i] = 0;
                collected[i] = amount;
                IERC20(tokens[i]).safeTransfer(msg.sender, amount);
            }
        }

        emit FeesCollected(msg.sender, collected);
    }

    /// @notice Kill the pool (emergency, withdrawals only)
    function killPool() external onlyRole(ADMIN_ROLE) {
        isKilled = true;
    }

    /// @notice Unkill the pool
    function unkillPool() external onlyRole(ADMIN_ROLE) {
        isKilled = false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get current A with ramping
    function _A() internal view returns (uint256) {
        uint256 t1 = futureATime;
        uint256 A1 = futureA;

        if (block.timestamp < t1) {
            uint256 t0 = initialATime;
            uint256 A0 = initialA;

            if (A1 > A0) {
                return A0 + ((A1 - A0) * (block.timestamp - t0)) / (t1 - t0);
            } else {
                return A0 - ((A0 - A1) * (block.timestamp - t0)) / (t1 - t0);
            }
        }
        return A1;
    }

    /// @notice Calculate D (invariant) using Newton's method
    function _getD(uint256[] memory xp, uint256 amp) internal view returns (uint256) {
        uint256 n = xp.length;
        uint256 S = 0;

        for (uint256 i = 0; i < n; i++) {
            S += xp[i];
        }

        if (S == 0) return 0;

        uint256 D = S;
        uint256 Ann = amp * n;

        for (uint256 iter = 0; iter < 255; iter++) {
            uint256 D_P = D;

            for (uint256 i = 0; i < n; i++) {
                D_P = (D_P * D) / (xp[i] * n + 1); // +1 prevents division by zero
            }

            uint256 Dprev = D;
            D = ((Ann * S + D_P * n) * D) / ((Ann - 1) * D + (n + 1) * D_P);

            // Check convergence
            if (D > Dprev) {
                if (D - Dprev <= 1) return D;
            } else {
                if (Dprev - D <= 1) return D;
            }
        }

        revert ConvergenceFailed();
    }

    /// @notice Calculate y given x for swap
    function _getY(
        uint256 i,
        uint256 j,
        uint256 x,
        uint256[] memory xp
    ) internal view returns (uint256) {
        uint256 n = xp.length;
        uint256 amp = _A();
        uint256 D = _getD(xp, amp);

        uint256 Ann = amp * n;
        uint256 c = D;
        uint256 S = 0;

        for (uint256 k = 0; k < n; k++) {
            uint256 _x;
            if (k == i) {
                _x = x;
            } else if (k != j) {
                _x = xp[k];
            } else {
                continue;
            }
            S += _x;
            c = (c * D) / (_x * n);
        }

        c = (c * D) / (Ann * n);
        uint256 b = S + D / Ann;
        uint256 y = D;

        for (uint256 iter = 0; iter < 255; iter++) {
            uint256 yPrev = y;
            y = (y * y + c) / (2 * y + b - D);

            if (y > yPrev) {
                if (y - yPrev <= 1) return y;
            } else {
                if (yPrev - y <= 1) return y;
            }
        }

        revert ConvergenceFailed();
    }

    /// @notice Execute exchange internally
    function _exchange(
        uint256 i,
        uint256 j,
        uint256 dx
    ) internal returns (uint256 dy) {
        uint256[] memory xp = balances;
        uint256 x = xp[i] + dx;
        uint256 y = _getY(i, j, x, xp);
        dy = xp[j] - y - 1; // -1 for rounding in favor of pool

        uint256 dyFee = (dy * fee) / FEE_DENOMINATOR;
        dy -= dyFee;

        adminBalances[j] += (dyFee * adminFee) / FEE_DENOMINATOR;

        balances[i] = x;
        balances[j] = y + (dyFee * adminFee) / FEE_DENOMINATOR;
    }

    /// @notice Calculate swap output amount (view)
    function _getSwapAmount(
        uint256 i,
        uint256 j,
        uint256 dx
    ) internal view returns (uint256 dy) {
        uint256[] memory xp = balances;
        uint256 dxNorm = _normalize(dx, tokenDecimals[i]);
        uint256 x = xp[i] + dxNorm;
        uint256 y = _getY(i, j, x, xp);
        dy = xp[j] - y - 1;

        uint256 dyFee = (dy * fee) / FEE_DENOMINATOR;
        dy = _denormalize(dy - dyFee, tokenDecimals[j]);
    }

    /// @notice Calculate LP tokens for deposit/withdraw
    function _calcTokenAmount(
        uint256[] calldata amounts,
        bool isDeposit
    ) internal view returns (uint256) {
        uint256 _A = _A();
        uint256[] memory oldBalances = balances;
        uint256 D0 = _getD(oldBalances, _A);

        uint256[] memory newBalances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amountNorm = _normalize(amounts[i], tokenDecimals[i]);
            if (isDeposit) {
                newBalances[i] = oldBalances[i] + amountNorm;
            } else {
                newBalances[i] = oldBalances[i] - amountNorm;
            }
        }

        uint256 D1 = _getD(newBalances, _A);
        uint256 supply = totalSupply();

        if (isDeposit) {
            return ((D1 - D0) * supply) / D0;
        } else {
            return ((D0 - D1) * supply) / D0;
        }
    }

    /// @notice Calculate single coin withdrawal
    function _calcWithdrawOneCoin(
        uint256 tokenAmount,
        uint256 i
    ) internal view returns (uint256) {
        (uint256 dy,) = _calcWithdrawOneCoinWithFee(tokenAmount, i);
        return _denormalize(dy, tokenDecimals[i]);
    }

    /// @notice Calculate single coin withdrawal with fee
    function _calcWithdrawOneCoinWithFee(
        uint256 tokenAmount,
        uint256 i
    ) internal view returns (uint256 dy, uint256 dyFee) {
        uint256 _A = _A();
        uint256[] memory xp = balances;
        uint256 D0 = _getD(xp, _A);
        uint256 D1 = D0 - (tokenAmount * D0) / totalSupply();

        uint256[] memory xpReduced = new uint256[](tokens.length);
        uint256 _fee = (fee * tokens.length) / (4 * (tokens.length - 1));

        for (uint256 j = 0; j < tokens.length; j++) {
            uint256 dxExpected;
            if (j == i) {
                dxExpected = (xp[j] * D1) / D0 - _getY(0, j, D1, xp);
            } else {
                dxExpected = xp[j] - (xp[j] * D1) / D0;
            }
            xpReduced[j] = xp[j] - (_fee * dxExpected) / FEE_DENOMINATOR;
        }

        uint256 y = _getY(0, i, D1, xpReduced);
        dy = xpReduced[i] - y - 1;
        dyFee = (xp[i] - _getY(0, i, D1, xp)) - dy;
    }

    /// @notice Normalize amount to 18 decimals
    function _normalize(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return amount * 10 ** (18 - decimals);
        } else if (decimals > 18) {
            return amount / 10 ** (decimals - 18);
        }
        return amount;
    }

    /// @notice Denormalize from 18 decimals
    function _denormalize(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return amount / 10 ** (18 - decimals);
        } else if (decimals > 18) {
            return amount * 10 ** (decimals - 18);
        }
        return amount;
    }
}
