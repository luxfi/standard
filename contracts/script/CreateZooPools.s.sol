// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AMMV3Factory} from "@luxfi/contracts/amm/AMMV3Factory.sol";
import {AMMV3Pool} from "@luxfi/contracts/amm/AMMV3Pool.sol";
import {ZooMainnet} from "@luxfi/contracts/deployments/Addresses.sol";

/**
 * @title CreateZooPools
 * @notice Creates V3 concentrated liquidity pool on Zoo chain with one-sided ZOO liquidity
 *
 * Pool created:
 *   1. WZOO/ZLUX - 0.3% fee tier, ZOO=$0.10, LUX=$1  (1 LUX = 10 ZOO)
 *
 * One-sided liquidity strategy:
 *   We only hold ZOO (native token). WZOO sorts lower than ZLUX, so WZOO=token0.
 *   A range entirely below the current tick requires only token0 (WZOO), which is
 *   exactly what we want: provide ZOO liquidity that gets bought as price rises.
 *
 * Usage:
 *   LUX_PRIVATE_KEY=0x... ZOO_AMOUNT=10000 forge script contracts/script/CreateZooPools.s.sol \
 *     --rpc-url https://api.lux.network/mainnet/ext/bc/zoo/rpc --broadcast --legacy -vvv
 */
contract CreateZooPools is Script {
    using SafeERC20 for IERC20;
    // --- V3 constants ---
    uint24 constant FEE_30BPS = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant MIN_TICK = -887272;
    int24 constant MAX_TICK = 887272;
    int24 constant RANGE_TICKS = 10000;

    // --- Zoo mainnet addresses ---
    address constant WZOO = ZooMainnet.WZOO;
    address constant ZLUX = ZooMainnet.ZLUX;
    address constant V3_FACTORY = ZooMainnet.V3_FACTORY;

    function run() external {
        uint256 deployerKey = vm.envUint("LUX_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        uint256 totalZoo = vm.envOr("ZOO_AMOUNT", uint256(10000)) * 1 ether;

        console.log("=== Create Zoo V3 Pools ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Total ZOO for liquidity:", totalZoo / 1e18);
        console.log("");

        vm.startBroadcast(deployerKey);

        // Wrap native ZOO if needed
        uint256 bal = IERC20(WZOO).balanceOf(deployer);
        if (bal < totalZoo) {
            uint256 needed = totalZoo - bal;
            console.log("Wrapping", needed / 1e18, "ZOO...");
            (bool ok,) = WZOO.call{value: needed}(abi.encodeWithSignature("deposit()"));
            require(ok, "WZOO deposit failed");
        }

        _createPoolWzooZlux(deployer, totalZoo);

        vm.stopBroadcast();

        console.log("");
        console.log("=== ZOO POOL CREATED ===");
    }

    // =========================================================================
    // WZOO/ZLUX  (token0=WZOO, token1=ZLUX, both 18 decimals)
    // =========================================================================
    // Price = ZLUX_per_WZOO (raw, same decimals)
    // At ZOO=$0.10, LUX=$1: 1 WZOO = 0.1 ZLUX => price = 0.1
    //   sqrtPriceX96 = sqrt(0.1) * 2^96 = 0.316228 * 2^96
    //                = 25,054,144,837,504,792,519,158,666,362
    //
    // One-sided WZOO (token0): range below current tick => only token0.
    function _createPoolWzooZlux(address deployer, uint256 zooAmount) internal {
        console.log("--- WZOO/ZLUX Pool (ZOO=$0.10, LUX=$1) ---");
        require(WZOO < ZLUX, "token order");

        address pool = _getOrCreatePool(WZOO, ZLUX, FEE_30BPS);
        AMMV3Pool v3 = AMMV3Pool(pool);

        if (v3.sqrtPriceX96() == 0) {
            uint160 sqrtPrice = 25054144837504792519158666362;
            v3.initializePrice(sqrtPrice);
            console.log("  Initialized sqrtPriceX96:", uint256(sqrtPrice));
        }

        int24 currentTick = v3.tick();
        int24 tickUpper = _roundDown(currentTick, TICK_SPACING);
        int24 tickLower = _roundDown(currentTick - RANGE_TICKS, TICK_SPACING);
        tickLower = _clampLower(tickLower);
        require(tickLower < tickUpper, "bad range");

        uint160 sqrtA = _getSqrtRatioAtTick(tickLower);
        uint160 sqrtB = _getSqrtRatioAtTick(tickUpper);
        uint128 liq = _liquidityFromToken0(sqrtA, sqrtB, zooAmount);

        if (liq == 0) {
            console.log("  WARN: Zero liquidity, skipping");
            return;
        }

        IERC20(WZOO).safeTransfer(pool, zooAmount);
        v3.mint(deployer, tickLower, tickUpper, liq);

        console.log("  Minted one-sided ZOO position:");
        console.log("    ZOO deposited:", zooAmount / 1e18);
        console.log("    Liquidity:", uint256(liq));
        console.log(string.concat("    Ticks: [", _tickStr(tickLower), ", ", _tickStr(tickUpper), ")"));
    }

    // =========================================================================
    // Pool creation
    // =========================================================================

    function _getOrCreatePool(address tokenA, address tokenB, uint24 fee) internal returns (address pool) {
        AMMV3Factory factory = AMMV3Factory(V3_FACTORY);
        pool = factory.getPool(tokenA, tokenB, fee);
        if (pool == address(0)) {
            pool = factory.createPool(tokenA, tokenB, fee);
            console.log("  Created pool:", pool);
        } else {
            console.log("  Pool exists:", pool);
        }
    }

    // =========================================================================
    // Tick math (Uniswap V3 TickMath, matches AMMV3Pool)
    // =========================================================================

    function _getSqrtRatioAtTick(int24 tick_) internal pure returns (uint160) {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 absTick = tick_ < 0 ? uint256(uint24(-tick_)) : uint256(uint24(tick_));
        // forge-lint: disable-next-line(unsafe-typecast)
        require(absTick <= uint256(int256(MAX_TICK)), "tick OOB");

        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
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

    // =========================================================================
    // Liquidity math
    // =========================================================================

    function _liquidityFromToken0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) internal pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 diff = uint256(sqrtB) - uint256(sqrtA);
        if (diff == 0) return 0;
        uint256 intermediate = (amount0 * uint256(sqrtA)) / (1 << 96);
        uint256 liq = (intermediate * uint256(sqrtB)) / diff;
        // forge-lint: disable-next-line(unsafe-typecast)
        return liq > type(uint128).max ? type(uint128).max : uint128(liq);
    }

    // =========================================================================
    // Tick helpers
    // =========================================================================

    function _roundDown(int24 t, int24 s) internal pure returns (int24) {
        int24 c = t / s;
        if (t < 0 && t % s != 0) c--;
        return c * s;
    }

    function _roundUp(int24 t, int24 s) internal pure returns (int24) {
        int24 c = t / s;
        if (t > 0 && t % s != 0) c++;
        return c * s;
    }

    function _clampLower(int24 t) internal pure returns (int24) {
        int24 minAligned = _roundUp(MIN_TICK, TICK_SPACING);
        return t < minAligned ? minAligned : t;
    }

    function _tickStr(int24 t) internal pure returns (string memory) {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (t >= 0) return vm.toString(uint256(uint24(t)));
        // forge-lint: disable-next-line(unsafe-typecast)
        return string.concat("-", vm.toString(uint256(uint24(-t))));
    }
}
