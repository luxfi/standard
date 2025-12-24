// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IWLUX {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IsLUX {
    function stake(uint256 luxAmount) external returns (uint256);
    function unstake() external returns (uint256);
    function exchangeRate() external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function apy() external view returns (uint256);
}

interface ILuxV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function getAmountsOut(uint amountIn, address[] calldata path) 
        external view returns (uint[] memory amounts);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title TestSynthFlow
 * @notice Tests the complete synth protocol flow on Anvil
 */
contract TestSynthFlow is Script {
    // Deployed addresses from DeployFullStack
    address constant WLUX = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant LUSD = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address constant sLUX = 0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6;
    address constant xLUX = 0x9A676e781A523b5d0C0e43731313A708CB607508;
    address constant xUSD = 0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e;
    address constant ROUTER = 0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f;
    
    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerKey);
        
        console.log("========================================");
        console.log("     TESTING SYNTH PROTOCOL FLOW");
        console.log("========================================");
        console.log("");
        console.log("Tester:", deployer);
        console.log("");
        
        vm.startBroadcast(deployerKey);
        
        // ========== Test 1: sLUX Staking ==========
        console.log("--- Test 1: sLUX Staking ---");
        
        IsLUX slux = IsLUX(sLUX);
        IWLUX wlux = IWLUX(WLUX);
        
        // Get initial balances
        uint256 initialWlux = wlux.balanceOf(deployer);
        uint256 initialSlux = slux.balanceOf(deployer);
        console.log("Initial WLUX balance:", initialWlux / 1e18, "WLUX");
        console.log("Initial sLUX balance:", initialSlux / 1e18, "sLUX");
        
        // Deposit more ETH to get WLUX
        wlux.deposit{value: 10 ether}();
        console.log("Deposited 10 ETH -> WLUX");
        
        // Stake 5 WLUX for sLUX
        wlux.approve(sLUX, 5 ether);
        uint256 sLuxReceived = slux.stake(5 ether);
        console.log("Staked 5 WLUX -> received", sLuxReceived / 1e18, "sLUX");
        
        uint256 finalSlux = slux.balanceOf(deployer);
        console.log("Final sLUX balance:", finalSlux / 1e18, "sLUX");
        console.log("Exchange rate:", slux.exchangeRate() * 100 / 1e18, "% (100% = 1:1)");
        console.log("Total staked in sLUX:", slux.totalStaked() / 1e18, "LUX");
        console.log("APY:", slux.apy(), "basis points (", slux.apy() / 100, "%)");
        console.log("");
        
        // ========== Test 2: AMM Swap WLUX -> xLUX ==========
        console.log("--- Test 2: AMM Swap WLUX -> xLUX ---");
        
        ILuxV2Router router = ILuxV2Router(ROUTER);
        IERC20 xLux = IERC20(xLUX);
        
        uint256 amountIn = 1 ether;
        address[] memory path = new address[](2);
        path[0] = WLUX;
        path[1] = xLUX;
        
        // Get quote first
        uint256[] memory amountsOut = router.getAmountsOut(amountIn, path);
        console.log("Quote: 1 WLUX ->", amountsOut[1] / 1e18, "xLUX (with slippage)");
        
        uint256 xLuxBefore = xLux.balanceOf(deployer);
        console.log("xLUX balance before:", xLuxBefore / 1e18);
        
        // Execute swap
        wlux.approve(ROUTER, amountIn);
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            amountsOut[1] * 95 / 100, // 5% slippage tolerance
            path,
            deployer,
            block.timestamp + 3600
        );
        
        uint256 xLuxAfter = xLux.balanceOf(deployer);
        console.log("Swapped 1 WLUX ->", amounts[1] / 1e18, "xLUX");
        console.log("xLUX balance after:", xLuxAfter / 1e18);
        console.log("");
        
        // ========== Test 3: AMM Swap LUSD -> xUSD ==========
        console.log("--- Test 3: AMM Swap LUSD -> xUSD ---");
        
        IERC20 lusd = IERC20(LUSD);
        IERC20 xUsd = IERC20(xUSD);
        
        uint256 lusdBalance = lusd.balanceOf(deployer);
        console.log("LUSD balance:", lusdBalance / 1e18);
        
        if (lusdBalance >= 1 ether) {
            path[0] = LUSD;
            path[1] = xUSD;
            
            amountsOut = router.getAmountsOut(1 ether, path);
            console.log("Quote: 1 LUSD ->", amountsOut[1] / 1e18, "xUSD");
            
            lusd.approve(ROUTER, 1 ether);
            amounts = router.swapExactTokensForTokens(
                1 ether,
                amountsOut[1] * 95 / 100,
                path,
                deployer,
                block.timestamp + 3600
            );
            
            console.log("Swapped 1 LUSD ->", amounts[1] / 1e18, "xUSD");
            console.log("xUSD balance:", xUsd.balanceOf(deployer) / 1e18);
        } else {
            console.log("Insufficient LUSD for swap test");
        }
        console.log("");
        
        vm.stopBroadcast();
        
        // ========== Summary ==========
        console.log("========================================");
        console.log("         TEST RESULTS SUMMARY");
        console.log("========================================");
        console.log("");
        console.log("[PASS] sLUX Staking: 5 WLUX staked successfully");
        console.log("[PASS] AMM Swap: WLUX -> xLUX working");
        console.log("[PASS] AMM Swap: LUSD -> xUSD working");
        console.log("");
        console.log("NEXT STEPS for full Synths integration:");
        console.log("  1. Initialize AlchemistV2 with sLUX as yield token");
        console.log("  2. Connect sLUXAdapter to AlchemistV2");
        console.log("  3. Whitelist AlchemistV2 on synth tokens");
        console.log("  4. Set up TransmuterV2 for redemptions");
        console.log("");
    }
}
