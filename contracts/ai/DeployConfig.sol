// SPDX-License-Identifier: MIT
// Copyright (C) 2019-2025, Lux Industries Inc. All rights reserved.
pragma solidity ^0.8.0;

/**
 * @title AIDeployConfig
 * @notice Configuration for AI Token deployment across 10 launch chains
 * @dev Each chain gets 1B AI supply cap with Bitcoin-aligned halving schedule
 *
 * TOKENOMICS (Per Chain):
 * - 100M AI (10%) - LP seeding allocation
 * - 900M AI (90%) - Mining allocation (79.4 AI/block, 6.3M block halving)
 * - 1B AI total supply cap per chain
 *
 * LAUNCH STRATEGY:
 * 1. Deploy AIToken to each chain via CREATE2 (same address)
 * 2. Safe multi-sig mints 100M AI for LP seeding
 * 3. Setup LP pools at $0.10/AI (~$10M depth)
 * 4. Enable Teleport bridge between chains (CGGMP21)
 * 5. Deploy mining contracts, set genesis block
 * 6. 900M AI mineable via NVTrust GPU attestation
 *
 * PRICING:
 * - Initial: $0.10/AI (96% discount from $2.50 market)
 * - Target LP depth: $10M per chain
 * - Each chain competes on price/compute
 *
 * GOVERNANCE TRANSITION:
 * - Phase 1: Lux Safe multi-sig (MPC managed, CGGMP21)
 * - Phase 2: DAO governance on Lux chain (AI voting)
 * - Phase 3: Cross-chain governance via Teleport
 */
library AIDeployConfig {
    // ============ Lux Network Chains (Native) ============

    /// @notice Lux C-Chain - Primary EVM
    uint256 constant LUX_C_CHAIN = 96369;

    /// @notice Hanzo EVM - AI-focused applications
    uint256 constant HANZO_EVM = 36963;

    /// @notice Zoo EVM - Research/DeSci focus
    uint256 constant ZOO_EVM = 200200;

    // ============ Top 20 External EVMs ============

    /// @notice Ethereum Mainnet
    uint256 constant ETHEREUM = 1;

    /// @notice BNB Smart Chain
    uint256 constant BSC = 56;

    /// @notice Polygon PoS
    uint256 constant POLYGON = 137;

    /// @notice Arbitrum One
    uint256 constant ARBITRUM = 42161;

    /// @notice Optimism
    uint256 constant OPTIMISM = 10;

    /// @notice Base
    uint256 constant BASE = 8453;

    /// @notice Avalanche C-Chain
    uint256 constant AVALANCHE = 43114;

    /// @notice Fantom Opera
    uint256 constant FANTOM = 250;

    /// @notice Cronos
    uint256 constant CRONOS = 25;

    /// @notice Gnosis Chain
    uint256 constant GNOSIS = 100;

    /// @notice zkSync Era
    uint256 constant ZKSYNC = 324;

    /// @notice Linea
    uint256 constant LINEA = 59144;

    /// @notice Scroll
    uint256 constant SCROLL = 534352;

    /// @notice Mantle
    uint256 constant MANTLE = 5000;

    /// @notice Blast
    uint256 constant BLAST = 81457;

    /// @notice Mode Network
    uint256 constant MODE = 34443;

    /// @notice Manta Pacific
    uint256 constant MANTA = 169;

    // ============ Chain Info ============

    struct ChainConfig {
        uint256 chainId;
        string name;
        string symbol;
        bool isLuxNative;      // Part of Lux network
        bool hasNativeWarp;    // Has Warp precompile
        uint256 treasuryBps;   // Treasury allocation (default 200 = 2%)
    }

    /// @notice Get configuration for a chain
    function getConfig(uint256 chainId) internal pure returns (ChainConfig memory) {
        // Lux Native Chains
        if (chainId == LUX_C_CHAIN) {
            return ChainConfig(chainId, "Lux C-Chain", "AI", true, true, 200);
        }
        if (chainId == HANZO_EVM) {
            return ChainConfig(chainId, "Hanzo EVM", "AI", true, true, 200);
        }
        if (chainId == ZOO_EVM) {
            return ChainConfig(chainId, "Zoo EVM", "AI", true, true, 250); // Higher treasury for research
        }

        // External EVMs (use Teleport bridge)
        if (chainId == ETHEREUM) {
            return ChainConfig(chainId, "Ethereum", "AI", false, false, 200);
        }
        if (chainId == BSC) {
            return ChainConfig(chainId, "BNB Chain", "AI", false, false, 200);
        }
        if (chainId == POLYGON) {
            return ChainConfig(chainId, "Polygon", "AI", false, false, 200);
        }
        if (chainId == ARBITRUM) {
            return ChainConfig(chainId, "Arbitrum", "AI", false, false, 200);
        }
        if (chainId == OPTIMISM) {
            return ChainConfig(chainId, "Optimism", "AI", false, false, 200);
        }
        if (chainId == BASE) {
            return ChainConfig(chainId, "Base", "AI", false, false, 200);
        }
        if (chainId == AVALANCHE) {
            return ChainConfig(chainId, "Avalanche", "AI", false, false, 200);
        }
        if (chainId == FANTOM) {
            return ChainConfig(chainId, "Fantom", "AI", false, false, 200);
        }
        if (chainId == CRONOS) {
            return ChainConfig(chainId, "Cronos", "AI", false, false, 200);
        }
        if (chainId == GNOSIS) {
            return ChainConfig(chainId, "Gnosis", "AI", false, false, 200);
        }
        if (chainId == ZKSYNC) {
            return ChainConfig(chainId, "zkSync Era", "AI", false, false, 200);
        }
        if (chainId == LINEA) {
            return ChainConfig(chainId, "Linea", "AI", false, false, 200);
        }
        if (chainId == SCROLL) {
            return ChainConfig(chainId, "Scroll", "AI", false, false, 200);
        }
        if (chainId == MANTLE) {
            return ChainConfig(chainId, "Mantle", "AI", false, false, 200);
        }
        if (chainId == BLAST) {
            return ChainConfig(chainId, "Blast", "AI", false, false, 200);
        }
        if (chainId == MODE) {
            return ChainConfig(chainId, "Mode", "AI", false, false, 200);
        }
        if (chainId == MANTA) {
            return ChainConfig(chainId, "Manta Pacific", "AI", false, false, 200);
        }

        // Unknown chain
        return ChainConfig(chainId, "Unknown", "AI", false, false, 200);
    }

    /// @notice Get all supported chain IDs
    function getSupportedChains() internal pure returns (uint256[] memory) {
        uint256[] memory chains = new uint256[](20);

        // Lux Native (3)
        chains[0] = LUX_C_CHAIN;
        chains[1] = HANZO_EVM;
        chains[2] = ZOO_EVM;

        // External EVMs (17)
        chains[3] = ETHEREUM;
        chains[4] = BSC;
        chains[5] = POLYGON;
        chains[6] = ARBITRUM;
        chains[7] = OPTIMISM;
        chains[8] = BASE;
        chains[9] = AVALANCHE;
        chains[10] = FANTOM;
        chains[11] = CRONOS;
        chains[12] = GNOSIS;
        chains[13] = ZKSYNC;
        chains[14] = LINEA;
        chains[15] = SCROLL;
        chains[16] = MANTLE;
        chains[17] = BLAST;
        chains[18] = MODE;
        chains[19] = MANTA;

        return chains;
    }

    /// @notice Check if chain is Lux native (has Warp)
    function isLuxNative(uint256 chainId) internal pure returns (bool) {
        return chainId == LUX_C_CHAIN || chainId == HANZO_EVM || chainId == ZOO_EVM;
    }
}

/**
 * @title SafeAddresses
 * @notice Safe multi-sig addresses for each chain
 * @dev These are the MPC-managed wallets that control AI contracts initially
 */
library SafeAddresses {
    // Lux Native Safes
    address constant LUX_SAFE = address(0); // TODO: Deploy
    address constant HANZO_SAFE = address(0); // TODO: Deploy
    address constant ZOO_SAFE = address(0); // TODO: Deploy

    // External Chain Safes (same Safe address across all EVM chains via CREATE2)
    address constant EXTERNAL_SAFE = address(0); // TODO: Deploy via Safe Factory

    function getSafe(uint256 chainId) internal pure returns (address) {
        if (chainId == AIDeployConfig.LUX_C_CHAIN) return LUX_SAFE;
        if (chainId == AIDeployConfig.HANZO_EVM) return HANZO_SAFE;
        if (chainId == AIDeployConfig.ZOO_EVM) return ZOO_SAFE;
        return EXTERNAL_SAFE;
    }
}

/**
 * @title InitialLPConfig
 * @notice Configuration for initial LP seeding
 *
 * LP STRATEGY:
 * - 100M AI per chain for LP seeding (10% of supply)
 * - Initial price: $0.10/AI (96% discount from $2.50 market)
 * - Target depth: $10M per chain
 * - One-sided liquidity: AI tokens provided, native tokens from swappers
 */
library InitialLPConfig {
    /// @notice Initial AI allocation for LP (10% = 100M per chain)
    uint256 constant LP_ALLOCATION = 100_000_000 ether;

    /// @notice Target initial price in USD ($0.10 per AI)
    uint256 constant TARGET_PRICE_USD = 100_000_000_000_000_000; // 0.1 ether = $0.10

    /// @notice Target LP depth in USD per chain
    uint256 constant TARGET_DEPTH_USD = 10_000_000 ether; // $10M

    /// @notice AI amount for LP pool (50M AI = $5M at $0.10)
    uint256 constant LP_AI_AMOUNT = 50_000_000 ether; // 50M for pool, 50M reserve

    /// @notice Calculate native token needed for balanced LP
    /// @dev For balanced pool: 50M AI ($5M) + native token ($5M) = $10M depth
    function calculateLPSetup(
        uint256 aiAmount,
        uint256 nativeTokenPriceUsd
    ) internal pure returns (uint256 nativeTokenAmount) {
        // AI at $0.10, calculate native token needed
        uint256 aiValueUsd = (aiAmount * TARGET_PRICE_USD) / 1 ether;
        nativeTokenAmount = (aiValueUsd * 1 ether) / nativeTokenPriceUsd;
    }

    /// @notice Calculate initial price from pool reserves
    /// @dev Constant product AMM: k = AI * Native
    function calculatePrice(
        uint256 aiReserve,
        uint256 nativeReserve,
        uint256 nativeTokenPriceUsd
    ) internal pure returns (uint256 aiPriceUsd) {
        // Price = (Native reserve / AI reserve) * Native USD price
        aiPriceUsd = (nativeReserve * nativeTokenPriceUsd) / aiReserve;
    }
}
