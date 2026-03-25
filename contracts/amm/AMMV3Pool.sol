// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AMMV3Pool - Concentrated Liquidity Pool
/// @notice Implements Uniswap V3-style concentrated liquidity
/// @dev Supports range orders and capital-efficient liquidity provision
contract AMMV3Pool is ReentrancyGuard {
    using SafeERC20 for IERC20;
    // Tick math constants
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    address public factory;
    address public token0;
    address public token1;
    uint24 public fee;
    int24 public tickSpacing;

    // Pool state
    uint160 public sqrtPriceX96;
    int24 public tick;
    uint128 public liquidity;
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;
    uint128 public protocolFees0;
    uint128 public protocolFees1;

    // Position tracking
    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }
    mapping(bytes32 => Position) public positions;

    // Tick tracking
    struct TickInfo {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        bool initialized;
    }
    mapping(int24 => TickInfo) public ticks;

    // Events
    event Initialize(uint160 sqrtPriceX96, int24 tick);
    event Mint(address sender, address indexed owner, int24 indexed tickLower, int24 indexed tickUpper, uint128 amount, uint256 amount0, uint256 amount1);
    event Burn(address indexed owner, int24 indexed tickLower, int24 indexed tickUpper, uint128 amount, uint256 amount0, uint256 amount1);
    event Swap(address indexed sender, address indexed recipient, int256 amount0, int256 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick);
    event Collect(address indexed owner, address recipient, int24 indexed tickLower, int24 indexed tickUpper, uint128 amount0, uint128 amount1);
    event Flash(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1, uint256 paid0, uint256 paid1);

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1, uint24 _fee, int24 _tickSpacing) external {
        require(msg.sender == factory, "AMMV3: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    /// @notice Sets the initial price for the pool
    /// @param _sqrtPriceX96 The initial sqrt price of the pool as a Q64.96
    function initializePrice(uint160 _sqrtPriceX96) external {
        require(msg.sender == factory, "AMMV3: FORBIDDEN");
        require(sqrtPriceX96 == 0, "AMMV3: ALREADY_INITIALIZED");
        require(_sqrtPriceX96 >= MIN_SQRT_RATIO && _sqrtPriceX96 < MAX_SQRT_RATIO, "AMMV3: SQRT_RATIO_OUT_OF_BOUNDS");

        sqrtPriceX96 = _sqrtPriceX96;
        tick = _getTickAtSqrtRatio(_sqrtPriceX96);

        emit Initialize(_sqrtPriceX96, tick);
    }

    /// @notice Adds liquidity for the given recipient/tickLower/tickUpper position
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(amount > 0, "AMMV3: ZERO_AMOUNT");
        require(tickLower < tickUpper, "AMMV3: INVALID_TICK_RANGE");
        require(tickLower >= MIN_TICK && tickUpper <= MAX_TICK, "AMMV3: TICK_OUT_OF_BOUNDS");
        require(tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0, "AMMV3: TICK_SPACING");

        // Calculate amounts
        (amount0, amount1) = _getAmountsForLiquidity(sqrtPriceX96, tickLower, tickUpper, amount);

        // Pull tokens from caller and verify balance delta
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        if (amount1 > 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        require(IERC20(token0).balanceOf(address(this)) >= balance0Before + amount0, "AMMV3: INSUFFICIENT_TOKEN0");
        require(IERC20(token1).balanceOf(address(this)) >= balance1Before + amount1, "AMMV3: INSUFFICIENT_TOKEN1");

        // Update position
        bytes32 key = keccak256(abi.encodePacked(recipient, tickLower, tickUpper));
        Position storage position = positions[key];
        position.liquidity += amount;

        // Update ticks
        // forge-lint: disable-next-line(unsafe-typecast)
        _updateTick(tickLower, int128(uint128(amount)));
        // forge-lint: disable-next-line(unsafe-typecast)
        _updateTick(tickUpper, -int128(uint128(amount)));

        // Update global liquidity if in range
        if (tick >= tickLower && tick < tickUpper) {
            liquidity += amount;
        }

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @notice Removes liquidity from the sender
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        bytes32 key = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        Position storage position = positions[key];
        require(position.liquidity >= amount, "AMMV3: INSUFFICIENT_LIQUIDITY");

        // Calculate amounts
        (amount0, amount1) = _getAmountsForLiquidity(sqrtPriceX96, tickLower, tickUpper, amount);

        // Update position
        position.liquidity -= amount;
        // forge-lint: disable-next-line(unsafe-typecast)
        position.tokensOwed0 += uint128(amount0);
        // forge-lint: disable-next-line(unsafe-typecast)
        position.tokensOwed1 += uint128(amount1);

        // Update ticks
        // forge-lint: disable-next-line(unsafe-typecast)
        _updateTick(tickLower, -int128(uint128(amount)));
        // forge-lint: disable-next-line(unsafe-typecast)
        _updateTick(tickUpper, int128(uint128(amount)));

        // Update global liquidity if in range
        if (tick >= tickLower && tick < tickUpper) {
            liquidity -= amount;
        }

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @notice Collects tokens owed to a position
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external nonReentrant returns (uint128 amount0, uint128 amount1) {
        bytes32 key = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        Position storage position = positions[key];

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).safeTransfer(recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).safeTransfer(recipient, amount1);
        }

        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    /// @notice Swap token0 for token1, or token1 for token0
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata
    ) external nonReentrant returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "AMMV3: ZERO_AMOUNT");
        require(sqrtPriceX96 != 0, "AMMV3: NOT_INITIALIZED");

        // Simplified swap: constant product at current price
        uint256 balanceBefore0 = IERC20(token0).balanceOf(address(this));
        uint256 balanceBefore1 = IERC20(token1).balanceOf(address(this));

        if (zeroForOne) {
            require(sqrtPriceLimitX96 < sqrtPriceX96 && sqrtPriceLimitX96 >= MIN_SQRT_RATIO, "AMMV3: SPL");
        } else {
            require(sqrtPriceLimitX96 > sqrtPriceX96 && sqrtPriceLimitX96 < MAX_SQRT_RATIO, "AMMV3: SPL");
        }

        bool exactInput = amountSpecified > 0;
        uint256 amountIn;
        uint256 amountOut;

        if (exactInput) {
            // forge-lint: disable-next-line(unsafe-typecast)
            amountIn = uint256(amountSpecified);
            // Calculate output with fee
            uint256 amountInWithFee = amountIn * (1000000 - uint256(fee)) / 1000000;
            if (zeroForOne) {
                amountOut = (amountInWithFee * balanceBefore1) / (balanceBefore0 + amountInWithFee);
            } else {
                amountOut = (amountInWithFee * balanceBefore0) / (balanceBefore1 + amountInWithFee);
            }
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            amountOut = uint256(-amountSpecified);
            // Calculate input with fee
            if (zeroForOne) {
                amountIn = (amountOut * balanceBefore0 * 1000000) / ((balanceBefore1 - amountOut) * (1000000 - uint256(fee))) + 1;
            } else {
                amountIn = (amountOut * balanceBefore1 * 1000000) / ((balanceBefore0 - amountOut) * (1000000 - uint256(fee))) + 1;
            }
        }

        if (zeroForOne) {
            // forge-lint: disable-next-line(unsafe-typecast)
            amount0 = int256(amountIn);
            // forge-lint: disable-next-line(unsafe-typecast)
            amount1 = -int256(amountOut);
            // Pull input tokens from caller, then transfer output
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(token1).safeTransfer(recipient, amountOut);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            amount0 = -int256(amountOut);
            // forge-lint: disable-next-line(unsafe-typecast)
            amount1 = int256(amountIn);
            // Pull input tokens from caller, then transfer output
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(token0).safeTransfer(recipient, amountOut);
        }

        // Update sqrtPriceX96 and tick based on post-swap balances
        uint256 balanceAfter0 = IERC20(token0).balanceOf(address(this));
        uint256 balanceAfter1 = IERC20(token1).balanceOf(address(this));
        if (balanceAfter0 > 0 && balanceAfter1 > 0) {
            // sqrtPriceX96 = sqrt(balance1/balance0) * 2^96
            // = sqrt(balance1 * 2^192 / balance0)
            uint256 ratioX192 = (balanceAfter1 << 192) / balanceAfter0;
            uint160 newSqrtPriceX96 = uint160(_sqrt(ratioX192));
            if (newSqrtPriceX96 >= MIN_SQRT_RATIO && newSqrtPriceX96 < MAX_SQRT_RATIO) {
                sqrtPriceX96 = newSqrtPriceX96;
                tick = _getTickAtSqrtRatio(newSqrtPriceX96);
            }
        }

        emit Swap(msg.sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick);
    }

    /// @notice Flash loan tokens from the pool
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external nonReentrant {
        uint256 fee0 = amount0 > 0 ? (amount0 * fee) / 1000000 + 1 : 0;
        uint256 fee1 = amount1 > 0 ? (amount1 * fee) / 1000000 + 1 : 0;

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) IERC20(token0).safeTransfer(recipient, amount0);
        if (amount1 > 0) IERC20(token1).safeTransfer(recipient, amount1);

        // Callback
        IFlashCallback(msg.sender).flashCallback(fee0, fee1, data);

        require(IERC20(token0).balanceOf(address(this)) >= balance0Before + fee0, "AMMV3: FLASH_FEE0");
        require(IERC20(token1).balanceOf(address(this)) >= balance1Before + fee1, "AMMV3: FLASH_FEE1");

        emit Flash(msg.sender, recipient, amount0, amount1, fee0, fee1);
    }

    // Internal functions
    function _updateTick(int24 tick_, int128 liquidityDelta) internal {
        TickInfo storage info = ticks[tick_];
        if (!info.initialized) {
            info.initialized = true;
        }
        // liquidityGross tracks total liquidity referencing this tick (always use absolute value)
        // liquidityNet tracks the net change when price crosses this tick
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 absDelta = liquidityDelta > 0 ? uint128(liquidityDelta) : uint128(-liquidityDelta);
        info.liquidityGross = info.liquidityGross + absDelta;
        // For liquidityNet, use the original signed delta
        info.liquidityNet += liquidityDelta;
    }

    function _getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidityAmount
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = _getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = _getSqrtRatioAtTick(tickUpper);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = _getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidityAmount);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = _getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidityAmount);
            amount1 = _getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidityAmount);
        } else {
            amount1 = _getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidityAmount);
        }
    }

    function _getAmount0ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidityAmount) internal pure returns (uint256) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        // Reorder operations to avoid overflow: divide by sqrtRatioAX96 first
        // Original: (L << 96) * (B - A) / B / A
        // Rewritten: L * (B - A) * (2^96 / A) / B
        // = L * (B - A) / A * 2^96 / B (but this still overflows)
        // Use mulDiv pattern: (L * (B - A)) / A * 2^96 / B = L * (B - A) * 2^96 / (A * B)
        // To avoid overflow: (L * 2^96 / A) * (B - A) / B (divide before multiply)
        uint256 intermediate = (uint256(liquidityAmount) << 96) / sqrtRatioAX96;
        return intermediate * (sqrtRatioBX96 - sqrtRatioAX96) / sqrtRatioBX96;
    }

    function _getAmount1ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidityAmount) internal pure returns (uint256) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return uint256(liquidityAmount) * (sqrtRatioBX96 - sqrtRatioAX96) / (1 << 96);
    }

    function _getSqrtRatioAtTick(int24 tick_) internal pure returns (uint160) {
        // Simplified: approximate sqrt price ratio
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 absTick = tick_ < 0 ? uint256(uint24(-tick_)) : uint256(uint24(tick_));
        // forge-lint: disable-next-line(unsafe-typecast)
        require(absTick <= uint256(int256(MAX_TICK)), "AMMV3: TICK_OUT_OF_BOUNDS");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick_ > 0) ratio = type(uint256).max / ratio;
        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    /// @dev Integer square root via Newton's method (Babylonian)
    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = x / 2 + 1;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }

    function _getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick_) {
        require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, "AMMV3: SQRT_RATIO_OUT_OF_BOUNDS");

        uint256 ratio = uint256(sqrtPriceX96) << 32;
        uint256 r = ratio;
        uint256 msb = 0;

        assembly {
            let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(5, gt(r, 0xFFFFFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(4, gt(r, 0xFFFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(3, gt(r, 0xFF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(2, gt(r, 0xF))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := shl(1, gt(r, 0x3))
            msb := or(msb, f)
            r := shr(f, r)
        }
        assembly {
            let f := gt(r, 0x1)
            msb := or(msb, f)
        }

        if (msb >= 128) r = ratio >> (msb - 127);
        else r = ratio << (127 - msb);

        // forge-lint: disable-next-line(unsafe-typecast)
        int256 log_2 = (int256(msb) - 128) << 64;

        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(55, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(54, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(53, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(52, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(51, f))
            r := shr(f, r)
        }
        assembly {
            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(50, f))
        }

        int256 log_sqrt10001 = log_2 * 255738958999603826347141;

        int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
        int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

        tick_ = tickLow == tickHi ? tickLow : _getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
    }
}

interface IFlashCallback {
    function flashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}
