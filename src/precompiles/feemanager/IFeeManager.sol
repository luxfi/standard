// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

import "../IAllowList.sol";

/**
 * @title IFeeManager
 * @dev Interface for the Fee Manager precompile
 *
 * This precompile allows dynamic configuration of network fee parameters.
 * Only addresses with Enabled, Admin, or Manager roles can modify fees.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000003
 *
 * Fee Configuration Parameters:
 * - gasLimit: Maximum gas per block
 * - targetBlockRate: Target seconds between blocks
 * - minBaseFee: Minimum base fee (floor)
 * - targetGas: Target gas per block for fee adjustment
 * - baseFeeChangeDenominator: How quickly base fee adjusts
 * - minBlockGasCost: Minimum gas cost per block
 * - maxBlockGasCost: Maximum gas cost per block
 * - blockGasCostStep: How much block gas cost changes per block
 *
 * Gas Costs:
 * - getFeeConfig: ~20,800 gas (8 storage reads)
 * - getFeeConfigLastChangedAt: 2,600 gas
 * - setFeeConfig: ~22,600 gas (9 storage writes)
 * - readAllowList: 2,600 gas
 */
interface IFeeManager is IAllowList {
    /**
     * @notice Fee configuration structure
     */
    struct FeeConfig {
        uint256 gasLimit;
        uint256 targetBlockRate;
        uint256 minBaseFee;
        uint256 targetGas;
        uint256 baseFeeChangeDenominator;
        uint256 minBlockGasCost;
        uint256 maxBlockGasCost;
        uint256 blockGasCostStep;
    }

    /**
     * @notice Emitted when fee configuration is changed
     * @param sender The address that changed the fee config
     * @param oldFeeConfig The previous fee configuration
     * @param newFeeConfig The new fee configuration
     */
    event FeeConfigChanged(address indexed sender, FeeConfig oldFeeConfig, FeeConfig newFeeConfig);

    /**
     * @notice Get the current fee configuration
     * @return gasLimit Maximum gas per block
     * @return targetBlockRate Target seconds between blocks
     * @return minBaseFee Minimum base fee
     * @return targetGas Target gas per block
     * @return baseFeeChangeDenominator Base fee change denominator
     * @return minBlockGasCost Minimum block gas cost
     * @return maxBlockGasCost Maximum block gas cost
     * @return blockGasCostStep Block gas cost step
     */
    function getFeeConfig()
        external
        view
        returns (
            uint256 gasLimit,
            uint256 targetBlockRate,
            uint256 minBaseFee,
            uint256 targetGas,
            uint256 baseFeeChangeDenominator,
            uint256 minBlockGasCost,
            uint256 maxBlockGasCost,
            uint256 blockGasCostStep
        );

    /**
     * @notice Get the block number when fee config was last changed
     * @return blockNumber The block number of last change
     */
    function getFeeConfigLastChangedAt() external view returns (uint256 blockNumber);

    /**
     * @notice Set the fee configuration
     * @dev Only callable by enabled addresses
     * @param gasLimit Maximum gas per block
     * @param targetBlockRate Target seconds between blocks
     * @param minBaseFee Minimum base fee
     * @param targetGas Target gas per block
     * @param baseFeeChangeDenominator Base fee change denominator
     * @param minBlockGasCost Minimum block gas cost
     * @param maxBlockGasCost Maximum block gas cost
     * @param blockGasCostStep Block gas cost step
     */
    function setFeeConfig(
        uint256 gasLimit,
        uint256 targetBlockRate,
        uint256 minBaseFee,
        uint256 targetGas,
        uint256 baseFeeChangeDenominator,
        uint256 minBlockGasCost,
        uint256 maxBlockGasCost,
        uint256 blockGasCostStep
    ) external;
}

/**
 * @title FeeManagerLib
 * @dev Library for interacting with the Fee Manager precompile
 */
library FeeManagerLib {
    /// @dev The address of the Fee Manager precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000003;

    error NotFeeManagerEnabled();
    error InvalidFeeConfig();

    /**
     * @notice Check if an address can modify fee config
     * @param addr The address to check
     * @return True if the address can modify fees
     */
    function canModifyFees(address addr) internal view returns (bool) {
        return AllowListLib.isEnabled(PRECOMPILE_ADDRESS, addr);
    }

    /**
     * @notice Require caller to be able to modify fees
     */
    function requireCanModifyFees() internal view {
        if (!canModifyFees(msg.sender)) {
            revert NotFeeManagerEnabled();
        }
    }

    /**
     * @notice Get the current fee configuration as a struct
     * @return config The current fee configuration
     */
    function getFeeConfigStruct() internal view returns (IFeeManager.FeeConfig memory config) {
        (
            config.gasLimit,
            config.targetBlockRate,
            config.minBaseFee,
            config.targetGas,
            config.baseFeeChangeDenominator,
            config.minBlockGasCost,
            config.maxBlockGasCost,
            config.blockGasCostStep
        ) = IFeeManager(PRECOMPILE_ADDRESS).getFeeConfig();
    }

    /**
     * @notice Set the fee configuration from a struct
     * @param config The fee configuration to set
     */
    function setFeeConfigStruct(IFeeManager.FeeConfig memory config) internal {
        IFeeManager(PRECOMPILE_ADDRESS).setFeeConfig(
            config.gasLimit,
            config.targetBlockRate,
            config.minBaseFee,
            config.targetGas,
            config.baseFeeChangeDenominator,
            config.minBlockGasCost,
            config.maxBlockGasCost,
            config.blockGasCostStep
        );
    }

    /**
     * @notice Get the current gas limit
     * @return gasLimit The current gas limit
     */
    function getGasLimit() internal view returns (uint256 gasLimit) {
        (gasLimit, , , , , , , ) = IFeeManager(PRECOMPILE_ADDRESS).getFeeConfig();
    }

    /**
     * @notice Get the current minimum base fee
     * @return minBaseFee The current minimum base fee
     */
    function getMinBaseFee() internal view returns (uint256 minBaseFee) {
        (, , minBaseFee, , , , , ) = IFeeManager(PRECOMPILE_ADDRESS).getFeeConfig();
    }

    /**
     * @notice Get the role of an address
     * @param addr The address to check
     * @return role The role (0=None, 1=Enabled, 2=Admin, 3=Manager)
     */
    function getRole(address addr) internal view returns (uint256 role) {
        return IFeeManager(PRECOMPILE_ADDRESS).readAllowList(addr);
    }
}

/**
 * @title FeeManagerController
 * @dev Abstract contract for contracts that need to manage fees
 */
abstract contract FeeManagerController {
    using FeeManagerLib for *;

    /// @dev Modifier to check if caller can modify fees
    modifier onlyFeeManager() {
        FeeManagerLib.requireCanModifyFees();
        _;
    }

    /**
     * @notice Update the fee configuration
     * @param config The new fee configuration
     */
    function _updateFeeConfig(IFeeManager.FeeConfig memory config) internal {
        FeeManagerLib.setFeeConfigStruct(config);
    }

    /**
     * @notice Get the current fee configuration
     * @return config The current fee configuration
     */
    function _getFeeConfig() internal view returns (IFeeManager.FeeConfig memory config) {
        return FeeManagerLib.getFeeConfigStruct();
    }
}
