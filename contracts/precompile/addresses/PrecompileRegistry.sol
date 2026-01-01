// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/// @title PrecompileRegistry
/// @notice Central registry of all Lux DeFi precompile addresses
/// @dev All precompiles are in the 0x0200...00XX address range
library PrecompileRegistry {
    /*//////////////////////////////////////////////////////////////
                         CORE PRECOMPILES
    //////////////////////////////////////////////////////////////*/

    /// @notice Deployer allow list management
    address internal constant DEPLOYER_ALLOW_LIST = 0x0200000000000000000000000000000000000001;

    /// @notice Transaction allow list management
    address internal constant TX_ALLOW_LIST = 0x0200000000000000000000000000000000000002;

    /// @notice Fee manager for dynamic gas pricing
    address internal constant FEE_MANAGER = 0x0200000000000000000000000000000000000003;

    /// @notice Native token minting
    address internal constant NATIVE_MINTER = 0x0200000000000000000000000000000000000004;

    /// @notice Cross-chain Warp messaging
    address internal constant WARP = 0x0200000000000000000000000000000000000005;

    /// @notice Reward manager for validators
    address internal constant REWARD_MANAGER = 0x0200000000000000000000000000000000000006;

    /*//////////////////////////////////////////////////////////////
                      CRYPTOGRAPHY PRECOMPILES
    //////////////////////////////////////////////////////////////*/

    /// @notice ML-DSA (FIPS 204) post-quantum signatures
    address internal constant ML_DSA = 0x0200000000000000000000000000000000000007;

    /// @notice SLH-DSA (FIPS 205) hash-based signatures
    address internal constant SLH_DSA = 0x0200000000000000000000000000000000000008;

    /// @notice General post-quantum crypto operations
    address internal constant PQ_CRYPTO = 0x0200000000000000000000000000000000000009;

    /// @notice Quasar quantum consensus operations
    address internal constant QUASAR = address(0x020000000000000000000000000000000000000a);

    /// @notice Ringtail lattice threshold signatures
    address internal constant RINGTAIL = 0x020000000000000000000000000000000000000B;

    /// @notice FROST Schnorr threshold signatures
    address internal constant FROST = 0x020000000000000000000000000000000000000c;

    /// @notice CGGMP21 ECDSA threshold signatures
    address internal constant CGGMP21 = 0x020000000000000000000000000000000000000D;

    /// @notice Bridge verification (reserved)
    address internal constant BRIDGE = 0x020000000000000000000000000000000000000E;

    /*//////////////////////////////////////////////////////////////
                          DEFI PRECOMPILES
    //////////////////////////////////////////////////////////////*/

    /// @notice Native HFT DEX (QuantumSwap/LX)
    /// @dev 434M orders/sec, 2ns latency, 1ms finality
    address internal constant DEX = 0x0200000000000000000000000000000000000010;

    /// @notice Multi-source oracle aggregator
    /// @dev Chainlink, Pyth, Binance, Kraken, Native TWAP
    address internal constant ORACLE = 0x0200000000000000000000000000000000000011;

    /// @notice Lending protocol interface
    address internal constant LENDING = 0x0200000000000000000000000000000000000012;

    /// @notice Staking operations
    address internal constant STAKING = 0x0200000000000000000000000000000000000013;

    /// @notice Yield aggregator
    address internal constant YIELD = 0x0200000000000000000000000000000000000014;

    /// @notice Derivatives/Perpetuals
    address internal constant PERPS = 0x0200000000000000000000000000000000000015;

    /*//////////////////////////////////////////////////////////////
                       ATTESTATION PRECOMPILES
    //////////////////////////////////////////////////////////////*/

    /// @notice GPU/TEE attestation (AI tokens)
    address internal constant ATTESTATION = 0x0200000000000000000000000000000000000300;

    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if address is a known precompile
    function isPrecompile(address addr) internal pure returns (bool) {
        uint256 addrInt = uint256(uint160(addr));

        // Check 0x0200...00XX range
        if (addrInt >= uint256(uint160(0x0200000000000000000000000000000000000001)) &&
            addrInt <= uint256(uint160(0x0200000000000000000000000000000000000015))) {
            return true;
        }

        // Check attestation range
        if (addrInt == uint256(uint160(0x0200000000000000000000000000000000000300))) {
            return true;
        }

        return false;
    }

    /// @notice Get precompile name
    function getPrecompileName(address addr) internal pure returns (string memory) {
        if (addr == DEPLOYER_ALLOW_LIST) return "DeployerAllowList";
        if (addr == TX_ALLOW_LIST) return "TxAllowList";
        if (addr == FEE_MANAGER) return "FeeManager";
        if (addr == NATIVE_MINTER) return "NativeMinter";
        if (addr == WARP) return "Warp";
        if (addr == REWARD_MANAGER) return "RewardManager";
        if (addr == ML_DSA) return "ML-DSA";
        if (addr == SLH_DSA) return "SLH-DSA";
        if (addr == PQ_CRYPTO) return "PQCrypto";
        if (addr == QUASAR) return "Quasar";
        if (addr == RINGTAIL) return "Ringtail";
        if (addr == FROST) return "FROST";
        if (addr == CGGMP21) return "CGGMP21";
        if (addr == BRIDGE) return "Bridge";
        if (addr == DEX) return "DEX";
        if (addr == ORACLE) return "Oracle";
        if (addr == LENDING) return "Lending";
        if (addr == STAKING) return "Staking";
        if (addr == YIELD) return "Yield";
        if (addr == PERPS) return "Perps";
        if (addr == ATTESTATION) return "Attestation";
        return "Unknown";
    }

    /// @notice Get precompile category
    function getPrecompileCategory(address addr) internal pure returns (string memory) {
        uint256 addrInt = uint256(uint160(addr));

        if (addrInt >= uint256(uint160(0x0200000000000000000000000000000000000001)) &&
            addrInt <= uint256(uint160(0x0200000000000000000000000000000000000006))) {
            return "Core";
        }

        if (addrInt >= uint256(uint160(0x0200000000000000000000000000000000000007)) &&
            addrInt <= uint256(uint160(0x020000000000000000000000000000000000000E))) {
            return "Cryptography";
        }

        if (addrInt >= uint256(uint160(0x0200000000000000000000000000000000000010)) &&
            addrInt <= uint256(uint160(0x0200000000000000000000000000000000000015))) {
            return "DeFi";
        }

        if (addrInt == uint256(uint160(0x0200000000000000000000000000000000000300))) {
            return "Attestation";
        }

        return "Unknown";
    }
}

/// @title PrecompileChecker
/// @notice Utility contract for checking precompile availability
contract PrecompileChecker {
    using PrecompileRegistry for address;

    /// @notice Check if all DeFi precompiles are available
    function checkDeFiPrecompiles() external view returns (
        bool dexAvailable,
        bool oracleAvailable,
        bool lendingAvailable,
        bool stakingAvailable
    ) {
        dexAvailable = _isContractLive(PrecompileRegistry.DEX);
        oracleAvailable = _isContractLive(PrecompileRegistry.ORACLE);
        lendingAvailable = _isContractLive(PrecompileRegistry.LENDING);
        stakingAvailable = _isContractLive(PrecompileRegistry.STAKING);
    }

    /// @notice Check if all crypto precompiles are available
    function checkCryptoPrecompiles() external view returns (
        bool mldsaAvailable,
        bool frostAvailable,
        bool cggmp21Available,
        bool ringtailAvailable
    ) {
        mldsaAvailable = _isContractLive(PrecompileRegistry.ML_DSA);
        frostAvailable = _isContractLive(PrecompileRegistry.FROST);
        cggmp21Available = _isContractLive(PrecompileRegistry.CGGMP21);
        ringtailAvailable = _isContractLive(PrecompileRegistry.RINGTAIL);
    }

    /// @notice Get all precompile statuses
    function getAllPrecompileStatuses() external view returns (
        address[] memory addresses,
        string[] memory names,
        bool[] memory available
    ) {
        addresses = new address[](21);
        names = new string[](21);
        available = new bool[](21);

        addresses[0] = PrecompileRegistry.DEPLOYER_ALLOW_LIST;
        addresses[1] = PrecompileRegistry.TX_ALLOW_LIST;
        addresses[2] = PrecompileRegistry.FEE_MANAGER;
        addresses[3] = PrecompileRegistry.NATIVE_MINTER;
        addresses[4] = PrecompileRegistry.WARP;
        addresses[5] = PrecompileRegistry.REWARD_MANAGER;
        addresses[6] = PrecompileRegistry.ML_DSA;
        addresses[7] = PrecompileRegistry.SLH_DSA;
        addresses[8] = PrecompileRegistry.PQ_CRYPTO;
        addresses[9] = PrecompileRegistry.QUASAR;
        addresses[10] = PrecompileRegistry.RINGTAIL;
        addresses[11] = PrecompileRegistry.FROST;
        addresses[12] = PrecompileRegistry.CGGMP21;
        addresses[13] = PrecompileRegistry.BRIDGE;
        addresses[14] = PrecompileRegistry.DEX;
        addresses[15] = PrecompileRegistry.ORACLE;
        addresses[16] = PrecompileRegistry.LENDING;
        addresses[17] = PrecompileRegistry.STAKING;
        addresses[18] = PrecompileRegistry.YIELD;
        addresses[19] = PrecompileRegistry.PERPS;
        addresses[20] = PrecompileRegistry.ATTESTATION;

        for (uint256 i = 0; i < addresses.length; i++) {
            names[i] = addresses[i].getPrecompileName();
            available[i] = _isContractLive(addresses[i]);
        }
    }

    /// @notice Check if precompile is live
    function _isContractLive(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        // Precompiles don't have code but can still be called
        // We check by attempting a static call
        (bool success,) = addr.staticcall("");
        return success || size > 0;
    }
}
