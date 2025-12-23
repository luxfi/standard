// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";
import "@luxfi/standard/lib/utils/ReentrancyGuard.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";
import "../access/Governable.sol";

contract BonusDistributor is IRewardDistributor, ReentrancyGuard, Governable {
    
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant BONUS_DURATION = 365 days;

    uint256 public bonusMultiplierBasisPoints;

    address public override rewardToken;
    uint256 public lastDistributionTime;
    address public rewardTracker;

    address public admin;

    event Distribute(uint256 amount);
    event BonusMultiplierChange(uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "BonusDistributor: forbidden");
        _;
    }

    constructor(address _rewardToken, address _rewardTracker) public {
        rewardToken = _rewardToken;
        rewardTracker = _rewardTracker;
        admin = msg.sender;
    }

    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function updateLastDistributionTime() external onlyAdmin {
        lastDistributionTime = block.timestamp;
    }

    function setBonusMultiplier(uint256 _bonusMultiplierBasisPoints) external onlyAdmin {
        require(lastDistributionTime != 0, "BonusDistributor: invalid lastDistributionTime");
        IRewardTracker(rewardTracker).updateRewards();
        bonusMultiplierBasisPoints = _bonusMultiplierBasisPoints;
        emit BonusMultiplierChange(_bonusMultiplierBasisPoints);
    }

    function tokensPerInterval() public view override returns (uint256) {
        uint256 supply = IERC20(rewardTracker).totalSupply();
        return supply * bonusMultiplierBasisPoints / BASIS_POINTS_DIVISOR / BONUS_DURATION;
    }

    function pendingRewards() public view override returns (uint256) {
        if (block.timestamp == lastDistributionTime) {
            return 0;
        }

        uint256 supply = IERC20(rewardTracker).totalSupply();
        uint256 timeDiff = block.timestamp - lastDistributionTime;

        return timeDiff * supply * bonusMultiplierBasisPoints / BASIS_POINTS_DIVISOR / BONUS_DURATION;
    }

    function distribute() external override returns (uint256) {
        require(msg.sender == rewardTracker, "BonusDistributor: invalid msg.sender");
        uint256 amount = pendingRewards();
        if (amount == 0) { return 0; }

        lastDistributionTime = block.timestamp;

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (amount > balance) { amount = balance; }

        IERC20(rewardToken).safeTransfer(msg.sender, amount);

        emit Distribute(amount);
        return amount;
    }
}
