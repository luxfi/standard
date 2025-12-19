// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IFreezable} from "../interfaces/dao/deployables/IFreezable.sol";

/**
 * @title MockFreezable
 * @notice Mock implementation of IFreezable for testing freeze guards
 * @dev Provides simple getter/setter functionality for freeze state
 */
contract MockFreezable is IFreezable {
    bool private _isFrozen;
    uint48 private _lastFreezeTimestamp;

    /**
     * @notice Sets the frozen state for testing
     * @param frozen Whether the DAO should be frozen
     */
    function setIsFrozen(bool frozen) external {
        _isFrozen = frozen;
    }

    /**
     * @notice Sets the last known freeze timestamp for testing
     * @param timestamp The most recent freeze timestamp
     */
    function setLastKnownFreezeTime(uint48 timestamp) external {
        _lastFreezeTimestamp = timestamp;
    }

    /**
     * @inheritdoc IFreezable
     */
    function isFrozen() external view override returns (bool) {
        return _isFrozen;
    }

    /**
     * @inheritdoc IFreezable
     */
    function lastFreezeTime() external view override returns (uint48) {
        return _lastFreezeTimestamp;
    }
}
