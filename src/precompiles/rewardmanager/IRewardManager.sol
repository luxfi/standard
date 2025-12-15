// SPDX-License-Identifier: MIT
// Copyright (C) 2025, Lux Industries, Inc. All rights reserved.
pragma solidity ^0.8.0;

import "../IAllowList.sol";

/**
 * @title IRewardManager
 * @dev Interface for the Reward Manager precompile
 *
 * This precompile controls how block rewards and fees are distributed.
 * Only addresses with Enabled, Admin, or Manager roles can modify reward settings.
 *
 * Precompile Address: 0x0200000000000000000000000000000000000004
 *
 * Reward Modes:
 * 1. Specific Address: All rewards go to a designated address
 * 2. Fee Recipients: Block producers keep their fees (allowFeeRecipients)
 * 3. Disabled: All rewards are burned (sent to blackhole)
 *
 * Use Cases:
 * - Treasury management: Direct all fees to DAO treasury
 * - Validator rewards: Let validators keep their earned fees
 * - Deflationary tokenomics: Burn all fees
 *
 * Gas Costs:
 * - allowFeeRecipients: ~23,000 gas
 * - areFeeRecipientsAllowed: 2,600 gas
 * - currentRewardAddress: 2,600 gas
 * - disableRewards: ~23,000 gas
 * - setRewardAddress: ~23,000 gas
 * - readAllowList: 2,600 gas
 */
interface IRewardManager is IAllowList {
    /**
     * @notice Emitted when fee recipients are allowed
     * @param sender The address that enabled fee recipients
     */
    event FeeRecipientsAllowed(address indexed sender);

    /**
     * @notice Emitted when reward address is changed
     * @param sender The address that changed the reward address
     * @param oldRewardAddress The previous reward address
     * @param newRewardAddress The new reward address
     */
    event RewardAddressChanged(
        address indexed sender,
        address indexed oldRewardAddress,
        address indexed newRewardAddress
    );

    /**
     * @notice Emitted when rewards are disabled
     * @param sender The address that disabled rewards
     */
    event RewardsDisabled(address indexed sender);

    /**
     * @notice Allow block producers to receive their fees
     * @dev Only callable by enabled addresses
     */
    function allowFeeRecipients() external;

    /**
     * @notice Check if fee recipients mode is enabled
     * @return isAllowed True if block producers keep their fees
     */
    function areFeeRecipientsAllowed() external view returns (bool isAllowed);

    /**
     * @notice Get the current reward address
     * @return rewardAddress The address receiving rewards (zero if fee recipients mode)
     */
    function currentRewardAddress() external view returns (address rewardAddress);

    /**
     * @notice Disable all rewards (burn them)
     * @dev Only callable by enabled addresses
     */
    function disableRewards() external;

    /**
     * @notice Set a specific address to receive all rewards
     * @dev Only callable by enabled addresses
     * @param addr The address to receive rewards (cannot be zero address)
     */
    function setRewardAddress(address addr) external;
}

/**
 * @title RewardManagerLib
 * @dev Library for interacting with the Reward Manager precompile
 */
library RewardManagerLib {
    /// @dev The address of the Reward Manager precompile
    address constant PRECOMPILE_ADDRESS = 0x0200000000000000000000000000000000000004;

    /// @dev The blackhole address (where burned rewards go)
    address constant BLACKHOLE_ADDRESS = 0x0100000000000000000000000000000000000000;

    error NotRewardManagerEnabled();
    error ZeroRewardAddress();

    /**
     * @notice Check if an address can modify rewards
     * @param addr The address to check
     * @return True if the address can modify rewards
     */
    function canModifyRewards(address addr) internal view returns (bool) {
        return AllowListLib.isEnabled(PRECOMPILE_ADDRESS, addr);
    }

    /**
     * @notice Require caller to be able to modify rewards
     */
    function requireCanModifyRewards() internal view {
        if (!canModifyRewards(msg.sender)) {
            revert NotRewardManagerEnabled();
        }
    }

    /**
     * @notice Check the current reward mode
     * @return isFeeRecipients True if fee recipients mode
     * @return isDisabled True if rewards are disabled
     * @return rewardAddress The specific reward address (if set)
     */
    function getRewardMode()
        internal
        view
        returns (bool isFeeRecipients, bool isDisabled, address rewardAddress)
    {
        rewardAddress = IRewardManager(PRECOMPILE_ADDRESS).currentRewardAddress();
        isFeeRecipients = IRewardManager(PRECOMPILE_ADDRESS).areFeeRecipientsAllowed();
        isDisabled = (rewardAddress == BLACKHOLE_ADDRESS);
    }

    /**
     * @notice Enable fee recipients mode
     */
    function enableFeeRecipients() internal {
        IRewardManager(PRECOMPILE_ADDRESS).allowFeeRecipients();
    }

    /**
     * @notice Disable rewards (burn them)
     */
    function disableRewards() internal {
        IRewardManager(PRECOMPILE_ADDRESS).disableRewards();
    }

    /**
     * @notice Set a specific reward address
     * @param addr The address to receive rewards
     */
    function setRewardAddress(address addr) internal {
        if (addr == address(0)) revert ZeroRewardAddress();
        IRewardManager(PRECOMPILE_ADDRESS).setRewardAddress(addr);
    }

    /**
     * @notice Get the role of an address
     * @param addr The address to check
     * @return role The role (0=None, 1=Enabled, 2=Admin, 3=Manager)
     */
    function getRole(address addr) internal view returns (uint256 role) {
        return IRewardManager(PRECOMPILE_ADDRESS).readAllowList(addr);
    }
}

/**
 * @title RewardManagerController
 * @dev Abstract contract for contracts that need to manage rewards
 */
abstract contract RewardManagerController {
    using RewardManagerLib for *;

    /// @dev Modifier to check if caller can modify rewards
    modifier onlyRewardManager() {
        RewardManagerLib.requireCanModifyRewards();
        _;
    }

    /**
     * @notice Configure reward distribution to a treasury
     * @param treasury The treasury address to receive rewards
     */
    function _setTreasuryRewards(address treasury) internal {
        RewardManagerLib.setRewardAddress(treasury);
    }

    /**
     * @notice Enable validators to keep their fees
     */
    function _enableValidatorRewards() internal {
        RewardManagerLib.enableFeeRecipients();
    }

    /**
     * @notice Burn all rewards (deflationary mode)
     */
    function _burnRewards() internal {
        RewardManagerLib.disableRewards();
    }
}
