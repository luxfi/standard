// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/ILLPManager.sol";
import "../access/Governable.sol";

/// @title RewardRouter
/// @notice Routes staking and rewards for LPX perpetuals protocol
/// @dev DLUX is the single governance rewards token across the Lux ecosystem
contract RewardRouter is IRewardRouter, ReentrancyGuard, Governable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    enum VotingPowerType {
        None,
        BaseStakedAmount,
        BaseAndBonusStakedAmount
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    bool public isInitialized;

    address public weth;

    address public lpx;
    address public xLPX;
    address public dlux;  // DLUX governance token - single reward token

    address public llp; // LLP - Lux Liquidity Provider token

    address public stakedLPXTracker;
    address public bonusLPXTracker;
    address public feeLPXTracker;

    address public override stakedLLPTracker;
    address public override feeLLPTracker;

    address public llpManager;

    address public lpxVester;
    address public llpVester;

    uint256 public maxBoostBasisPoints;
    bool public inStrictTransferMode;

    address public govToken;
    VotingPowerType public votingPowerType;

    mapping (address => address) public pendingReceivers;

    event StakeLPX(address account, address token, uint256 amount);
    event UnstakeLPX(address account, address token, uint256 amount);

    event StakeLLP(address account, uint256 amount);
    event UnstakeLLP(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _lpx,
        address _xLPX,
        address _dlux,
        address _llp,
        address _stakedLPXTracker,
        address _bonusLPXTracker,
        address _feeLPXTracker,
        address _feeLLPTracker,
        address _stakedLLPTracker,
        address _llpManager,
        address _lpxVester,
        address _llpVester,
        address _govToken
    ) external onlyGov {
        require(!isInitialized, "already initialized");
        isInitialized = true;

        weth = _weth;

        lpx = _lpx;
        xLPX = _xLPX;
        dlux = _dlux;

        llp = _llp;

        stakedLPXTracker = _stakedLPXTracker;
        bonusLPXTracker = _bonusLPXTracker;
        feeLPXTracker = _feeLPXTracker;

        feeLLPTracker = _feeLLPTracker;
        stakedLLPTracker = _stakedLLPTracker;

        llpManager = _llpManager;

        lpxVester = _lpxVester;
        llpVester = _llpVester;

        govToken = _govToken;
    }

    function setInStrictTransferMode(bool _inStrictTransferMode) external onlyGov {
        inStrictTransferMode = _inStrictTransferMode;
    }

    function setMaxBoostBasisPoints(uint256 _maxBoostBasisPoints) external onlyGov {
        maxBoostBasisPoints = _maxBoostBasisPoints;
    }

    function setVotingPowerType(VotingPowerType _votingPowerType) external onlyGov {
        votingPowerType = _votingPowerType;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeLPXForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _lpx = lpx;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeLPX(msg.sender, _accounts[i], _lpx, _amounts[i]);
        }
    }

    function stakeLPXForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeLPX(msg.sender, _account, lpx, _amount);
    }

    function stakeLPX(uint256 _amount) external nonReentrant {
        _stakeLPX(msg.sender, msg.sender, lpx, _amount);
    }

    function stakeXLPX(uint256 _amount) external nonReentrant {
        _stakeLPX(msg.sender, msg.sender, xLPX, _amount);
    }

    function unstakeLPX(uint256 _amount) external nonReentrant {
        _unstakeLPX(msg.sender, lpx, _amount, true);
    }

    function unstakeXLPX(uint256 _amount) external nonReentrant {
        _unstakeLPX(msg.sender, xLPX, _amount, true);
    }

    function mintAndStakeLLP(address _token, uint256 _amount, uint256 _minLPUSD, uint256 _minLLP) external nonReentrant returns (uint256) {
        require(_amount > 0, "invalid _amount");

        address account = msg.sender;
        uint256 llpAmount = ILLPManager(llpManager).addLiquidityForAccount(account, account, _token, _amount, _minLPUSD, _minLLP);
        IRewardTracker(feeLLPTracker).stakeForAccount(account, account, llp, llpAmount);
        IRewardTracker(stakedLLPTracker).stakeForAccount(account, account, feeLLPTracker, llpAmount);

        emit StakeLLP(account, llpAmount);

        return llpAmount;
    }

    function mintAndStakeLLPETH(uint256 _minLPUSD, uint256 _minLLP) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(llpManager, msg.value);

        address account = msg.sender;
        uint256 llpAmount = ILLPManager(llpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minLPUSD, _minLLP);

        IRewardTracker(feeLLPTracker).stakeForAccount(account, account, llp, llpAmount);
        IRewardTracker(stakedLLPTracker).stakeForAccount(account, account, feeLLPTracker, llpAmount);

        emit StakeLLP(account, llpAmount);

        return llpAmount;
    }

    function unstakeAndRedeemLLP(address _tokenOut, uint256 _llpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_llpAmount > 0, "invalid _llpAmount");

        address account = msg.sender;
        IRewardTracker(stakedLLPTracker).unstakeForAccount(account, feeLLPTracker, _llpAmount, account);
        IRewardTracker(feeLLPTracker).unstakeForAccount(account, llp, _llpAmount, account);
        uint256 amountOut = ILLPManager(llpManager).removeLiquidityForAccount(account, _tokenOut, _llpAmount, _minOut, _receiver);

        emit UnstakeLLP(account, _llpAmount);

        return amountOut;
    }

    function unstakeAndRedeemLLPETH(uint256 _llpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_llpAmount > 0, "invalid _llpAmount");

        address account = msg.sender;
        IRewardTracker(stakedLLPTracker).unstakeForAccount(account, feeLLPTracker, _llpAmount, account);
        IRewardTracker(feeLLPTracker).unstakeForAccount(account, llp, _llpAmount, account);
        uint256 amountOut = ILLPManager(llpManager).removeLiquidityForAccount(account, weth, _llpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeLLP(account, _llpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeLPXTracker).claimForAccount(account, account);
        IRewardTracker(feeLLPTracker).claimForAccount(account, account);

        IRewardTracker(stakedLPXTracker).claimForAccount(account, account);
        IRewardTracker(stakedLLPTracker).claimForAccount(account, account);
    }

    function claimXLPX() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedLPXTracker).claimForAccount(account, account);
        IRewardTracker(stakedLLPTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeLPXTracker).claimForAccount(account, account);
        IRewardTracker(feeLLPTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimLPX,
        bool _shouldStakeLPX,
        bool _shouldClaimXLPX,
        bool _shouldStakeXLPX,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 lpxAmount = 0;
        if (_shouldClaimLPX) {
            uint256 lpxAmount0 = IVester(lpxVester).claimForAccount(account, account);
            uint256 lpxAmount1 = IVester(llpVester).claimForAccount(account, account);
            lpxAmount = lpxAmount0 + lpxAmount1;
        }

        if (_shouldStakeLPX && lpxAmount > 0) {
            _stakeLPX(account, account, lpx, lpxAmount);
        }

        uint256 xLPXAmount = 0;
        if (_shouldClaimXLPX) {
            uint256 xLPXAmount0 = IRewardTracker(stakedLPXTracker).claimForAccount(account, account);
            uint256 xLPXAmount1 = IRewardTracker(stakedLLPTracker).claimForAccount(account, account);
            xLPXAmount = xLPXAmount0 + xLPXAmount1;
        }

        if (_shouldStakeXLPX && xLPXAmount > 0) {
            _stakeLPX(account, account, xLPX, xLPXAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            _stakeDLUX(account);
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeLPXTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeLLPTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0 + weth1;
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeLPXTracker).claimForAccount(account, account);
                IRewardTracker(feeLLPTracker).claimForAccount(account, account);
            }
        }

        _syncVotingPower(account);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    // the _validateReceiver function checks that the averageStakedAmounts and cumulativeRewards
    // values of an account are zero, this is to help ensure that vesting calculations can be
    // done correctly
    // averageStakedAmounts and cumulativeRewards are updated if the claimable reward for an account
    // is more than zero
    // it is possible for multiple transfers to be sent into a single account, using signalTransfer and
    // acceptTransfer, if those values have not been updated yet
    // for LLP transfers it is also possible to transfer LLP into an account using the StakedLLP contract
    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(lpxVester).balanceOf(msg.sender) == 0, "sender has vested tokens");
        require(IERC20(llpVester).balanceOf(msg.sender) == 0, "sender has vested tokens");

        _validateReceiver(_receiver);

        if (inStrictTransferMode) {
            uint256 balance = IRewardTracker(feeLPXTracker).stakedAmounts(msg.sender);
            uint256 allowance = IERC20(feeLPXTracker).allowance(msg.sender, _receiver);
            require(allowance >= balance, "insufficient allowance");
        }

        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(lpxVester).balanceOf(_sender) == 0, "sender has vested tokens");
        require(IERC20(llpVester).balanceOf(_sender) == 0, "sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedLPX = IRewardTracker(stakedLPXTracker).depositBalances(_sender, lpx);
        if (stakedLPX > 0) {
            _unstakeLPX(_sender, lpx, stakedLPX, false);
            _stakeLPX(_sender, receiver, lpx, stakedLPX);
        }

        uint256 stakedXLPX = IRewardTracker(stakedLPXTracker).depositBalances(_sender, xLPX);
        if (stakedXLPX > 0) {
            _unstakeLPX(_sender, xLPX, stakedXLPX, false);
            _stakeLPX(_sender, receiver, xLPX, stakedXLPX);
        }

        uint256 stakedDLUX = IRewardTracker(feeLPXTracker).depositBalances(_sender, dlux);
        if (stakedDLUX > 0) {
            IRewardTracker(feeLPXTracker).unstakeForAccount(_sender, dlux, stakedDLUX, _sender);
            IRewardTracker(feeLPXTracker).stakeForAccount(_sender, receiver, dlux, stakedDLUX);
        }

        uint256 xLPXBalance = IERC20(xLPX).balanceOf(_sender);
        if (xLPXBalance > 0) {
            IERC20(xLPX).transferFrom(_sender, receiver, xLPXBalance);
        }

        uint256 dluxBalance = IERC20(dlux).balanceOf(_sender);
        if (dluxBalance > 0) {
            IMintable(dlux).burn(_sender, dluxBalance);
            IMintable(dlux).mint(receiver, dluxBalance);
        }

        uint256 llpAmount = IRewardTracker(feeLLPTracker).depositBalances(_sender, llp);
        if (llpAmount > 0) {
            IRewardTracker(stakedLLPTracker).unstakeForAccount(_sender, feeLLPTracker, llpAmount, _sender);
            IRewardTracker(feeLLPTracker).unstakeForAccount(_sender, llp, llpAmount, _sender);

            IRewardTracker(feeLLPTracker).stakeForAccount(_sender, receiver, llp, llpAmount);
            IRewardTracker(stakedLLPTracker).stakeForAccount(receiver, receiver, feeLLPTracker, llpAmount);
        }

        IVester(lpxVester).transferStakeValues(_sender, receiver);
        IVester(llpVester).transferStakeValues(_sender, receiver);

        _syncVotingPower(_sender);
        _syncVotingPower(receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedLPXTracker).averageStakedAmounts(_receiver) == 0, "stakedLPXTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedLPXTracker).cumulativeRewards(_receiver) == 0, "stakedLPXTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusLPXTracker).averageStakedAmounts(_receiver) == 0, "bonusLPXTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusLPXTracker).cumulativeRewards(_receiver) == 0, "bonusLPXTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeLPXTracker).averageStakedAmounts(_receiver) == 0, "feeLPXTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeLPXTracker).cumulativeRewards(_receiver) == 0, "feeLPXTracker.cumulativeRewards > 0");

        require(IVester(lpxVester).transferredAverageStakedAmounts(_receiver) == 0, "lpxVester.transferredAverageStakedAmounts > 0");
        require(IVester(lpxVester).transferredCumulativeRewards(_receiver) == 0, "lpxVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedLLPTracker).averageStakedAmounts(_receiver) == 0, "stakedLLPTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedLLPTracker).cumulativeRewards(_receiver) == 0, "stakedLLPTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeLLPTracker).averageStakedAmounts(_receiver) == 0, "feeLLPTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeLLPTracker).cumulativeRewards(_receiver) == 0, "feeLLPTracker.cumulativeRewards > 0");

        require(IVester(llpVester).transferredAverageStakedAmounts(_receiver) == 0, "lpxVester.transferredAverageStakedAmounts > 0");
        require(IVester(llpVester).transferredCumulativeRewards(_receiver) == 0, "lpxVester.transferredCumulativeRewards > 0");

        require(IERC20(lpxVester).balanceOf(_receiver) == 0, "lpxVester.balance > 0");
        require(IERC20(llpVester).balanceOf(_receiver) == 0, "llpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundLPX(_account);
        _compoundLLP(_account);
        _syncVotingPower(_account);
    }

    function _compoundLPX(address _account) private {
        uint256 xLPXAmount = IRewardTracker(stakedLPXTracker).claimForAccount(_account, _account);
        if (xLPXAmount > 0) {
            _stakeLPX(_account, _account, xLPX, xLPXAmount);
        }

        _stakeDLUX(_account);
    }

    function _compoundLLP(address _account) private {
        uint256 xLPXAmount = IRewardTracker(stakedLLPTracker).claimForAccount(_account, _account);
        if (xLPXAmount > 0) {
            _stakeLPX(_account, _account, xLPX, xLPXAmount);
        }
    }

    function _stakeLPX(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "invalid _amount");

        IRewardTracker(stakedLPXTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusLPXTracker).stakeForAccount(_account, _account, stakedLPXTracker, _amount);
        IRewardTracker(feeLPXTracker).stakeForAccount(_account, _account, bonusLPXTracker, _amount);

        _syncVotingPower(_account);

        emit StakeLPX(_account, _token, _amount);
    }

    // note that _syncVotingPower is not called here, in functions which
    // call _stakeDLUX it should be ensured that _syncVotingPower is called after
    function _stakeDLUX(address _account) private {
        IRewardTracker(bonusLPXTracker).claimForAccount(_account, _account);

        // get the DLUX balance of the user, this would be the amount of
        // DLUX that has not been staked
        uint256 dluxAmount = IERC20(dlux).balanceOf(_account);
        if (dluxAmount == 0) { return; }

        // get the baseStakedAmount which would be the sum of staked LPX and staked xLPX tokens
        uint256 baseStakedAmount = IRewardTracker(stakedLPXTracker).stakedAmounts(_account);
        uint256 maxAllowedDLUXAmount = baseStakedAmount * maxBoostBasisPoints / BASIS_POINTS_DIVISOR;
        uint256 currentDLUXAmount = IRewardTracker(feeLPXTracker).depositBalances(_account, dlux);
        if (currentDLUXAmount == maxAllowedDLUXAmount) { return; }

        // if the currentDLUXAmount is more than the maxAllowedDLUXAmount
        // unstake the excess tokens
        if (currentDLUXAmount > maxAllowedDLUXAmount) {
            uint256 amountToUnstake = currentDLUXAmount - maxAllowedDLUXAmount;
            IRewardTracker(feeLPXTracker).unstakeForAccount(_account, dlux, amountToUnstake, _account);
            return;
        }

        uint256 maxStakeableDLUXAmount = maxAllowedDLUXAmount - currentDLUXAmount;
        if (dluxAmount > maxStakeableDLUXAmount) {
            dluxAmount = maxStakeableDLUXAmount;
        }

        IRewardTracker(feeLPXTracker).stakeForAccount(_account, _account, dlux, dluxAmount);
    }

    function _unstakeLPX(address _account, address _token, uint256 _amount, bool _shouldReduceDLUX) private {
        require(_amount > 0, "invalid _amount");

        uint256 balance = IRewardTracker(stakedLPXTracker).stakedAmounts(_account);

        IRewardTracker(feeLPXTracker).unstakeForAccount(_account, bonusLPXTracker, _amount, _account);
        IRewardTracker(bonusLPXTracker).unstakeForAccount(_account, stakedLPXTracker, _amount, _account);
        IRewardTracker(stakedLPXTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceDLUX) {
            IRewardTracker(bonusLPXTracker).claimForAccount(_account, _account);

            // unstake and burn staked DLUX tokens
            uint256 stakedDLUX = IRewardTracker(feeLPXTracker).depositBalances(_account, dlux);
            if (stakedDLUX > 0) {
                uint256 reductionAmount = stakedDLUX * _amount / balance;
                IRewardTracker(feeLPXTracker).unstakeForAccount(_account, dlux, reductionAmount, _account);
                IMintable(dlux).burn(_account, reductionAmount);
            }

            // burn DLUX tokens from user's balance
            uint256 dluxBalance = IERC20(dlux).balanceOf(_account);
            if (dluxBalance > 0) {
                uint256 amountToBurn = dluxBalance * _amount / balance;
                IMintable(dlux).burn(_account, amountToBurn);
            }
        }

        _syncVotingPower(_account);

        emit UnstakeLPX(_account, _token, _amount);
    }

    function _syncVotingPower(address _account) private {
        if (votingPowerType == VotingPowerType.None) {
            return;
        }

        if (votingPowerType == VotingPowerType.BaseStakedAmount) {
            uint256 baseStakedAmount = IRewardTracker(stakedLPXTracker).stakedAmounts(_account);
            _syncVotingPower(_account, baseStakedAmount);
            return;
        }

        if (votingPowerType == VotingPowerType.BaseAndBonusStakedAmount) {
            uint256 stakedAmount = IRewardTracker(feeLPXTracker).stakedAmounts(_account);
            _syncVotingPower(_account, stakedAmount);
            return;
        }

        revert("unsupported votingPowerType");
    }

    function _syncVotingPower(address _account, uint256 _amount) private {
        uint256 currentVotingPower = IERC20(govToken).balanceOf(_account);
        if (currentVotingPower == _amount) { return; }

        if (currentVotingPower > _amount) {
            uint256 amountToBurn = currentVotingPower - _amount;
            IMintable(govToken).burn(_account, amountToBurn);
            return;
        }

        uint256 amountToMint = _amount - currentVotingPower;
        IMintable(govToken).mint(_account, amountToMint);
    }
}
