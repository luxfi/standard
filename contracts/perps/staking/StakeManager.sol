// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import { IRewardTracker } from "./interfaces/IRewardTracker.sol";
import { Governable } from "../access/Governable.sol";

contract StakeManager is Governable {
    function stakeForAccount(address _rewardTracker, address _account, address _token, uint256 _amount)
        external
        onlyGov
    {
        IRewardTracker(_rewardTracker).stakeForAccount(_account, _account, _token, _amount);
    }
}
