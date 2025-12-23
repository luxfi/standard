//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";
import "@luxfi/standard/lib/utils/ReentrancyGuard.sol";

import "./interfaces/IDistributor.sol";
import "./interfaces/IYieldTracker.sol";
import "./interfaces/IYieldToken.sol";

// code adapated from https://github.com/trusttoken/smart-contracts/blob/master/contracts/truefi/TrueFarm.sol
contract YieldTracker is IYieldTracker, ReentrancyGuard {
    
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e30;

    address public gov;
    address public yieldToken;
    address public distributor;

    uint256 public cumulativeRewardPerToken;
    mapping (address => uint256) public claimableReward;
    mapping (address => uint256) public previousCumulatedRewardPerToken;

    event Claim(address receiver, uint256 amount);

    modifier onlyGov() {
        require(msg.sender == gov, "YieldTracker: forbidden");
        _;
    }

    constructor(address _yieldToken) public {
        gov = msg.sender;
        yieldToken = _yieldToken;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setDistributor(address _distributor) external onlyGov {
        distributor = _distributor;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function claim(address _account, address _receiver) external override returns (uint256) {
        require(msg.sender == yieldToken, "YieldTracker: forbidden");
        updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        address rewardToken = IDistributor(distributor).getRewardToken(address(this));
        IERC20(rewardToken).safeTransfer(_receiver, tokenAmount);
        emit Claim(_account, tokenAmount);

        return tokenAmount;
    }

    function getTokensPerInterval() external override view returns (uint256) {
        return IDistributor(distributor).tokensPerInterval(address(this));
    }

    function claimable(address _account) external override view returns (uint256) {
        uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
        if (stakedBalance == 0) {
            return claimableReward[_account];
        }
        uint256 pendingRewards = IDistributor(distributor).getDistributionAmount(address(this)) * PRECISION;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken + pendingRewards / totalStaked;
        return claimableReward[_account] +
            (stakedBalance * nextCumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION;
    }

    function updateRewards(address _account) public override nonReentrant {
        uint256 blockReward;

        if (distributor != address(0)) {
            blockReward = IDistributor(distributor).distribute();
        }

        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        // only update cumulativeRewardPerToken when there are stakers, i.e. when totalStaked > 0
        // if blockReward == 0, then there will be no change to cumulativeRewardPerToken
        if (totalStaked > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken + blockReward * PRECISION / totalStaked;
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (_account != address(0)) {
            uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
            uint256 _previousCumulatedReward = previousCumulatedRewardPerToken[_account];
            uint256 _claimableReward = claimableReward[_account] +
                (stakedBalance * _cumulativeRewardPerToken - _previousCumulatedReward) / PRECISION;

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;
        }
    }
}
