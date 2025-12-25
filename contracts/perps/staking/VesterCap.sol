// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../access/Governable.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/Token.sol";

/// @title VesterCap
/// @notice Manages DLUX (governance token) staking caps and conversions
/// @dev DLUX is the single governance rewards token across the Lux ecosystem
contract VesterCap is ReentrancyGuard, Governable {

    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    address public immutable lpxVester;
    address public immutable stakedLPXTracker;
    address public immutable bonusLPXTracker;
    address public immutable feeLPXTracker;
    address public immutable dlux;  // DLUX governance token
    address public immutable xLPX;  // Escrowed LPX

    uint256 public immutable maxBoostBasisPoints;
    uint256 public immutable dluxToXLPXConversionDivisor;

    mapping (address => bool) public isUpdateCompleted;

    constructor (
        address _lpxVester,
        address _stakedLPXTracker,
        address _bonusLPXTracker,
        address _feeLPXTracker,
        address _dlux,
        address _xLPX,
        uint256 _maxBoostBasisPoints,
        uint256 _dluxToXLPXConversionDivisor
    ) public {
        lpxVester = _lpxVester;
        stakedLPXTracker = _stakedLPXTracker;
        bonusLPXTracker = _bonusLPXTracker;
        feeLPXTracker = _feeLPXTracker;
        dlux = _dlux;
        xLPX = _xLPX;

        maxBoostBasisPoints = _maxBoostBasisPoints;
        dluxToXLPXConversionDivisor = _dluxToXLPXConversionDivisor;
    }

    function updateDLUXForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i; i < _accounts.length; i++) {
            _updateDLUXForAccount(_accounts[i]);
        }
    }

    function syncFeeLPXTrackerBalance(address _account) external nonReentrant onlyGov {
        uint256 stakedAmount = IRewardTracker(feeLPXTracker).stakedAmounts(_account);
        uint256 feeLPXTrackerBalance = IERC20(feeLPXTracker).balanceOf(_account);

        if (feeLPXTrackerBalance <= stakedAmount) {
            return;
        }

        uint256 amountToTransfer = feeLPXTrackerBalance - stakedAmount;
        IERC20(feeLPXTracker).safeTransferFrom(_account, lpxVester, amountToTransfer);
    }

    function _updateDLUXForAccount(address _account) internal {
        if (isUpdateCompleted[_account]) {
            return;
        }

        isUpdateCompleted[_account] = true;

        uint256 stakedDLUXAmount = IRewardTracker(feeLPXTracker).depositBalances(_account, dlux);
        uint256 claimableDLUXAmount = IRewardTracker(bonusLPXTracker).claimable(_account);
        uint256 dluxBalance = IERC20(dlux).balanceOf(_account);
        uint256 totalDLUXAmount = stakedDLUXAmount + claimableDLUXAmount + dluxBalance;

        uint256 xLPXToMint = totalDLUXAmount / dluxToXLPXConversionDivisor;

        // mint xLPX to account and increase vestable xLPX amount
        if (xLPXToMint > 0) {
            Token(xLPX).mint(_account, xLPXToMint);
            uint256 bonusReward = IVester(lpxVester).bonusRewards(_account);
            IVester(lpxVester).setBonusRewards(_account, bonusReward + xLPXToMint);
        }

        uint256 baseStakedAmount = IRewardTracker(stakedLPXTracker).stakedAmounts(_account);
        uint256 maxAllowedDLUXAmount = baseStakedAmount * maxBoostBasisPoints / BASIS_POINTS_DIVISOR;

        if (stakedDLUXAmount <= maxAllowedDLUXAmount) {
            return;
        }

        uint256 amountToUnstake = stakedDLUXAmount - maxAllowedDLUXAmount;
        uint256 feeLPXTrackerBalance = IERC20(feeLPXTracker).balanceOf(_account);

        // a user's feeLPXTracker tokens could be transferred to the lpxVester contract
        // if the amountToUnstake is greater than the feeLPXTrackerBalance then
        // feeLPXTracker.unstakeForAccount would revert as the reduction of the user's staked
        // amount would cause an underflow
        // to avoid this issue, transfer the required amount from the feeLPXTracker back to the
        // user's account
        if (amountToUnstake > feeLPXTrackerBalance) {
            uint256 amountToUnvest = amountToUnstake - feeLPXTrackerBalance;
            IERC20(feeLPXTracker).safeTransferFrom(lpxVester, _account, amountToUnvest);
        }

        IRewardTracker(feeLPXTracker).unstakeForAccount(_account, dlux, amountToUnstake, _account);
    }
}
