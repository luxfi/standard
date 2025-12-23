// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

/// @title DeployConfig
/// @notice Configuration management for multi-chain deployments
abstract contract DeployConfig is Script {
    
    // ═══════════════════════════════════════════════════════════════════════
    // CHAIN IDs
    // ═══════════════════════════════════════════════════════════════════════
    
    uint256 constant LUX_MAINNET = 96369;
    uint256 constant LUX_TESTNET = 96368;
    uint256 constant HANZO_MAINNET = 36963;
    uint256 constant HANZO_TESTNET = 36962;
    uint256 constant ZOO_MAINNET = 200200;
    uint256 constant ZOO_TESTNET = 200201;
    
    // ═══════════════════════════════════════════════════════════════════════
    // PROTOCOL ADDRESSES (per chain)
    // ═══════════════════════════════════════════════════════════════════════
    
    struct ChainConfig {
        // Core tokens
        address wlux;           // Wrapped LUX
        address usdc;           // USDC stablecoin
        address usdt;           // USDT stablecoin
        address dai;            // DAI stablecoin
        address weth;           // Wrapped ETH
        address wbtc;           // Wrapped BTC
        
        // DEX
        address uniV2Factory;   // UniswapV2 factory
        address uniV2Router;    // UniswapV2 router
        address uniV3Factory;   // UniswapV3 factory
        address uniV3Router;    // UniswapV3 swap router
        
        // Oracle
        address chainlinkETH;   // Chainlink ETH/USD
        address chainlinkBTC;   // Chainlink BTC/USD
        address chainlinkLUX;   // Chainlink LUX/USD
        
        // Governance
        address multisig;       // Treasury multisig
        address timelock;       // Timelock contract
        
        // Warp (cross-chain)
        address warpMessenger;  // Warp precompile
    }
    
    mapping(uint256 => ChainConfig) internal configs;
    
    function _initConfigs() internal {
        // Lux Mainnet
        configs[LUX_MAINNET] = ChainConfig({
            wlux: 0x0000000000000000000000000000000000000000, // To be deployed
            usdc: 0x0000000000000000000000000000000000000000,
            usdt: 0x0000000000000000000000000000000000000000,
            dai: 0x0000000000000000000000000000000000000000,
            weth: 0x0000000000000000000000000000000000000000,
            wbtc: 0x0000000000000000000000000000000000000000,
            uniV2Factory: 0x0000000000000000000000000000000000000000,
            uniV2Router: 0x0000000000000000000000000000000000000000,
            uniV3Factory: 0x0000000000000000000000000000000000000000,
            uniV3Router: 0x0000000000000000000000000000000000000000,
            chainlinkETH: 0x0000000000000000000000000000000000000000,
            chainlinkBTC: 0x0000000000000000000000000000000000000000,
            chainlinkLUX: 0x0000000000000000000000000000000000000000,
            multisig: 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714, // Treasury
            timelock: 0x0000000000000000000000000000000000000000,
            warpMessenger: 0x0200000000000000000000000000000000000005 // Warp precompile
        });
        
        // Lux Testnet
        configs[LUX_TESTNET] = ChainConfig({
            wlux: 0x0000000000000000000000000000000000000000,
            usdc: 0x0000000000000000000000000000000000000000,
            usdt: 0x0000000000000000000000000000000000000000,
            dai: 0x0000000000000000000000000000000000000000,
            weth: 0x0000000000000000000000000000000000000000,
            wbtc: 0x0000000000000000000000000000000000000000,
            uniV2Factory: 0x0000000000000000000000000000000000000000,
            uniV2Router: 0x0000000000000000000000000000000000000000,
            uniV3Factory: 0x0000000000000000000000000000000000000000,
            uniV3Router: 0x0000000000000000000000000000000000000000,
            chainlinkETH: 0x0000000000000000000000000000000000000000,
            chainlinkBTC: 0x0000000000000000000000000000000000000000,
            chainlinkLUX: 0x0000000000000000000000000000000000000000,
            multisig: msg.sender, // Deployer for testnet
            timelock: 0x0000000000000000000000000000000000000000,
            warpMessenger: 0x0200000000000000000000000000000000000005
        });
    }
    
    function getConfig() internal view returns (ChainConfig memory) {
        return configs[block.chainid];
    }
    
    function isMainnet() internal view returns (bool) {
        return block.chainid == LUX_MAINNET || 
               block.chainid == HANZO_MAINNET || 
               block.chainid == ZOO_MAINNET;
    }
    
    function isTestnet() internal view returns (bool) {
        return block.chainid == LUX_TESTNET || 
               block.chainid == HANZO_TESTNET || 
               block.chainid == ZOO_TESTNET;
    }
}

/// @title CREATE2 Factory
/// @notice Deterministic deployment using CREATE2
contract Create2Factory {
    event Deployed(address addr, bytes32 salt);
    
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        emit Deployed(addr, salt);
    }
    
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }
}
