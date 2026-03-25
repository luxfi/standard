// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVester} from "../staking/interfaces/IVester.sol";
import {IRewardTracker} from "../staking/interfaces/IRewardTracker.sol";

contract xLpxBatchSender {
    using SafeERC20 for IERC20;


    address public admin;
    address public xLpx;

    constructor(address _xLpx) public {
        admin = msg.sender;
        xLpx = _xLpx;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "xLpxBatchSender: forbidden");
        _;
    }

    function send(
        IVester _vester,
        uint256 _minRatio,
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external onlyAdmin {
        IRewardTracker rewardTracker = IRewardTracker(_vester.rewardTracker());

        for (uint256 i = 0; i < _accounts.length; i++) {
            IERC20(xLpx).safeTransferFrom(msg.sender, _accounts[i], _amounts[i]);

            uint256 nextTransferredCumulativeReward = _vester.transferredCumulativeRewards(_accounts[i]) + _amounts[i];
            _vester.setTransferredCumulativeRewards(_accounts[i], nextTransferredCumulativeReward);

            uint256 cumulativeReward = rewardTracker.cumulativeRewards(_accounts[i]);
            uint256 totalCumulativeReward = cumulativeReward + nextTransferredCumulativeReward;

            uint256 combinedAverageStakedAmount = _vester.getCombinedAverageStakedAmount(_accounts[i]);

            if (combinedAverageStakedAmount > totalCumulativeReward * _minRatio) {
                continue;
            }

            uint256 nextTransferredAverageStakedAmount = _minRatio * totalCumulativeReward;
            nextTransferredAverageStakedAmount = nextTransferredAverageStakedAmount -
                rewardTracker.averageStakedAmounts(_accounts[i]) * cumulativeReward / totalCumulativeReward;

            nextTransferredAverageStakedAmount = nextTransferredAverageStakedAmount * totalCumulativeReward / nextTransferredCumulativeReward;

            _vester.setTransferredAverageStakedAmounts(_accounts[i], nextTransferredAverageStakedAmount);
        }
    }
}
