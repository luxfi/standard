// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "../IYieldStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Liquid Restaking Token (LRT) Strategies
/// @notice Yield strategies for LRT protocols that restake ETH via EigenLayer
/// @dev LRTs provide:
///      - Base ETH staking yield (~3.5-4.5%)
///      - EigenLayer AVS rewards (~2-5%)
///      - Protocol-specific points/rewards
///
/// Supported Protocols:
/// - Ether.fi (eETH/weETH) - Largest LRT by TVL
/// - Kelp (rsETH) - Multi-LST restaking
/// - Swell (swETH/rswETH) - Native restaking
/// - Puffer (pufETH) - Anti-slashing technology
/// - Renzo (ezETH) - Cross-chain restaking

// ═══════════════════════════════════════════════════════════════════════════════
// ETHER.FI INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Ether.fi Liquidity Pool for minting eETH
interface IEtherFiLiquidityPool {
    function deposit() external payable returns (uint256);
    function deposit(address _referral) external payable returns (uint256);
    function requestWithdraw(address recipient, uint256 amount) external returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function getTotalEtherClaimOf(address _user) external view returns (uint256);
}

/// @notice eETH token interface
interface IeETH is IERC20 {
    function shares(address _user) external view returns (uint256);
    function totalShares() external view returns (uint256);
}

/// @notice weETH (wrapped eETH) interface
interface IweETH is IERC20 {
    function wrap(uint256 _eETHAmount) external returns (uint256);
    function unwrap(uint256 _weETHAmount) external returns (uint256);
    function getWeETHByeETH(uint256 _eETHAmount) external view returns (uint256);
    function getEETHByWeETH(uint256 _weETHAmount) external view returns (uint256);
    function eETH() external view returns (address);
}

/// @notice Ether.fi membership NFT for loyalty points
interface IEtherFiMembershipManager {
    function claimPoints(uint256 tokenId) external;
    function pendingPoints(uint256 tokenId) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// KELP INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Kelp LRT Deposit Pool
interface IKelpLRTDepositPool {
    function depositAsset(
        address asset,
        uint256 depositAmount,
        uint256 minRSETHAmountExpected,
        string calldata referralId
    ) external;

    function depositETH(
        uint256 minRSETHAmountExpected,
        string calldata referralId
    ) external payable;

    function getAssetCurrentLimit(address asset) external view returns (uint256);
    function getTotalAssetDeposits(address asset) external view returns (uint256);
}

/// @notice Kelp rsETH token
interface IrsETH is IERC20 {
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
}

/// @notice Kelp LRT Oracle for pricing
interface IKelpLRTOracle {
    function rsETHPrice() external view returns (uint256);
    function getAssetPrice(address asset) external view returns (uint256);
}

/// @notice Kelp LRT Withdrawal Manager
interface IKelpWithdrawalManager {
    function initiateWithdrawal(address asset, uint256 amount) external returns (uint256);
    function completeWithdrawal(uint256 withdrawalId) external;
    function getWithdrawalDelay() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWELL INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Swell swETH staking contract
interface ISwellStaking {
    function deposit() external payable returns (uint256);
    function depositWithReferral(address referral) external payable returns (uint256);
    function getRate() external view returns (uint256);
    function totalETHDeposited() external view returns (uint256);
}

/// @notice swETH token interface
interface IswETH is IERC20 {
    function ethToSwETHRate() external view returns (uint256);
    function swETHToETHRate() external view returns (uint256);
}

/// @notice Swell rswETH (restaked swETH) interface
interface IrswETH is IERC20 {
    function deposit(uint256 amount, address receiver) external returns (uint256);
    function withdraw(uint256 amount, address receiver, address owner) external returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function totalAssets() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUFFER INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Puffer Vault for pufETH minting
interface IPufferVault is IERC20 {
    function depositETH(address receiver) external payable returns (uint256);
    function depositStETH(uint256 stETHAmount, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// RENZO INTERFACES
// ═══════════════════════════════════════════════════════════════════════════════

/// @notice Renzo RestakeManager for deposits
interface IRenzoRestakeManager {
    function depositETH() external payable returns (uint256);
    function depositETH(uint256 _referralId) external payable returns (uint256);
    function deposit(address _collateralToken, uint256 _amount) external returns (uint256);
    function deposit(address _collateralToken, uint256 _amount, uint256 _referralId) external returns (uint256);

    function calculateTVLs() external view returns (
        uint256[][] memory operatorDelegatorTVLs,
        uint256[] memory operatorDelegatorTokenTVLs,
        uint256 totalTVL
    );
}

/// @notice ezETH token interface
interface IezETH is IERC20 {
    function totalSupply() external view returns (uint256);
}

/// @notice Renzo Oracle for pricing
interface IRenzoOracle {
    function lookupTokenValue(address token, uint256 balance) external view returns (uint256);
    function lookupTokenAmountFromValue(address token, uint256 value) external view returns (uint256);
}

/// @notice Renzo Withdraw Queue
interface IRenzoWithdrawQueue {
    function withdraw(uint256 _amount, address _assetOut) external returns (uint256);
    function claim(uint256 _withdrawRequestId) external;
    function cooldownPeriod() external view returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ETHER.FI eETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Ether.fi eETH Strategy
/// @notice Stakes ETH via Ether.fi to receive eETH (rebasing LRT)
/// @dev eETH is rebasing - balance increases over time
///      Earns ETH staking yield + EigenLayer AVS rewards + Ether.fi points
contract EtherFiEETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Ether.fi Mainnet Addresses
    address public constant LIQUIDITY_POOL = 0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address public constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant MEMBERSHIP_MANAGER = 0x3d320286E014C3e1ce99Af6d6B00f0C1D63E3000;

    /// @notice Vault that controls this strategy
    address public vault;

    /// @notice eETH shares held
    uint256 public eethShares;

    /// @notice Total deposited ETH
    uint256 public totalDeposited;

    /// @notice Membership NFT token ID (if any)
    uint256 public membershipTokenId;

    /// @notice Accumulated points
    uint256 public accumulatedPoints;

    /// @notice Referral address
    address public referral;

    /// @notice Pause flag
    bool public isPaused;

    event Deposited(address indexed user, uint256 ethAmount, uint256 tokensReceived);
    event Withdrawn(address indexed user, uint256 tokensRedeemed, uint256 ethReceived);
    event PointsClaimed(uint256 amount);

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert StrategyPaused();
        _;
    }

    constructor(address _vault, address _referral) Ownable(msg.sender) {
        vault = _vault;
        referral = _referral;
    }

    function deposit(uint256 amount, bytes calldata /* data */) external payable onlyVault whenNotPaused returns (uint256 shares) {
        if (msg.value != amount) revert InvalidAmount();

        uint256 eethBefore = IERC20(EETH).balanceOf(address(this));

        if (referral != address(0)) {
            IEtherFiLiquidityPool(LIQUIDITY_POOL).deposit{value: amount}(referral);
        } else {
            IEtherFiLiquidityPool(LIQUIDITY_POOL).deposit{value: amount}();
        }

        shares = IERC20(EETH).balanceOf(address(this)) - eethBefore;
        eethShares += shares;
        totalDeposited += amount;

        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > eethShares) revert InsufficientBalance();
        if (recipient == address(0)) recipient = vault;

        // Calculate ETH value
        amount = (shares * totalDeposited) / eethShares;

        // Request withdrawal (goes through queue)
        IERC20(EETH).approve(LIQUIDITY_POOL, shares);
        IEtherFiLiquidityPool(LIQUIDITY_POOL).requestWithdraw(recipient, shares);

        eethShares -= shares;
        totalDeposited -= amount;

        emit Withdrawn(vault, shares, amount);
    }

    function harvest() external returns (uint256 harvested) {
        // eETH is rebasing - yield is embedded in balance increase
        uint256 currentValue = IEtherFiLiquidityPool(LIQUIDITY_POOL).getTotalEtherClaimOf(address(this));

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
        }

        // Claim Ether.fi loyalty points if we have membership NFT
        if (membershipTokenId != 0) {
            uint256 points = IEtherFiMembershipManager(MEMBERSHIP_MANAGER).pendingPoints(membershipTokenId);
            if (points > 0) {
                IEtherFiMembershipManager(MEMBERSHIP_MANAGER).claimPoints(membershipTokenId);
                accumulatedPoints += points;
                emit PointsClaimed(points);
            }
        }
    }

    function totalAssets() external view returns (uint256) {
        return IEtherFiLiquidityPool(LIQUIDITY_POOL).getTotalEtherClaimOf(address(this));
    }

    function currentAPY() external pure returns (uint256) {
        // ~4% base + ~3% AVS + points value
        return 700; // ~7% APY in basis points
    }

    function asset() external pure returns (address) {
        return address(0); // Native ETH
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Ether.fi eETH Strategy";
    }

    /// @notice Set membership NFT for points claiming
    function setMembershipToken(uint256 _tokenId) external onlyOwner {
        membershipTokenId = _tokenId;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setReferral(address _referral) external onlyOwner {
        referral = _referral;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 eethBalance = IERC20(EETH).balanceOf(address(this));
        if (eethBalance > 0) {
            IERC20(EETH).safeTransfer(owner(), eethBalance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// ETHER.FI weETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Ether.fi weETH Strategy
/// @notice Stakes ETH via Ether.fi and wraps to weETH (non-rebasing)
/// @dev weETH is non-rebasing - value increases over time (better for DeFi)
contract EtherFiWeETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant LIQUIDITY_POOL = 0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address public constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

    address public vault;
    uint256 public weethBalance;
    uint256 public totalDeposited;
    bool public isPaused;

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        IERC20(EETH).approve(WEETH, type(uint256).max);
    }

    function deposit(uint256 amount, bytes calldata /* data */) external payable onlyVault returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (msg.value != amount) revert InvalidAmount();

        // Deposit ETH -> eETH
        uint256 eethBefore = IERC20(EETH).balanceOf(address(this));
        IEtherFiLiquidityPool(LIQUIDITY_POOL).deposit{value: amount}();
        uint256 eethReceived = IERC20(EETH).balanceOf(address(this)) - eethBefore;

        // Wrap eETH -> weETH
        uint256 weethBefore = IERC20(WEETH).balanceOf(address(this));
        IweETH(WEETH).wrap(eethReceived);
        shares = IERC20(WEETH).balanceOf(address(this)) - weethBefore;

        weethBalance += shares;
        totalDeposited += amount;
    }

    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > weethBalance) revert InsufficientBalance();
        if (recipient == address(0)) recipient = vault;

        amount = (shares * totalDeposited) / weethBalance;

        // Unwrap weETH -> eETH
        uint256 eethReceived = IweETH(WEETH).unwrap(shares);

        // Request withdrawal
        IERC20(EETH).approve(LIQUIDITY_POOL, eethReceived);
        IEtherFiLiquidityPool(LIQUIDITY_POOL).requestWithdraw(recipient, eethReceived);

        weethBalance -= shares;
        totalDeposited -= amount;
    }

    function harvest() external returns (uint256 harvested) {
        uint256 currentValue = IweETH(WEETH).getEETHByWeETH(weethBalance);
        uint256 ethValue = IEtherFiLiquidityPool(LIQUIDITY_POOL).getTotalPooledEther() *
            currentValue / IeETH(EETH).totalShares();

        if (ethValue > totalDeposited) {
            harvested = ethValue - totalDeposited;
        }
    }

    function totalAssets() external view returns (uint256) {
        uint256 eethValue = IweETH(WEETH).getEETHByWeETH(weethBalance);
        return IEtherFiLiquidityPool(LIQUIDITY_POOL).getTotalPooledEther() *
            eethValue / IeETH(EETH).totalShares();
    }

    function currentAPY() external pure returns (uint256) {
        return 700; // ~7% APY
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Ether.fi weETH Strategy";
    }



    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(WEETH).balanceOf(address(this));
        if (balance > 0) {
            IERC20(WEETH).safeTransfer(owner(), balance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// KELP rsETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Kelp rsETH Strategy
/// @notice Deposits ETH/LSTs into Kelp to receive rsETH
/// @dev rsETH is a multi-collateral LRT accepting stETH, ETHx, sfrxETH
///      Earns base staking yield + EigenLayer + Kelp Miles
contract KelpRsETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Kelp Mainnet Addresses
    address public constant DEPOSIT_POOL = 0x036676389e48133B63a802f8635AD39E752D375D;
    address public constant RSETH = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
    address public constant LRT_ORACLE = 0x349A73444b1a310BAe67ef67973022020d70020d;
    address public constant WITHDRAWAL_MANAGER = 0x62De59c08eB5dAE4b7E6F7a8cAd3006d6965ec16;

    address public vault;
    uint256 public rsethBalance;
    uint256 public totalDeposited;
    uint256 public kelpMiles;
    bool public isPaused;

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
    }

    function deposit(uint256 amount, bytes calldata /* data */) external payable onlyVault returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (msg.value != amount) revert InvalidAmount();

        uint256 rsethBefore = IERC20(RSETH).balanceOf(address(this));
        IKelpLRTDepositPool(DEPOSIT_POOL).depositETH{value: amount}(0, "lux_bridge");
        shares = IERC20(RSETH).balanceOf(address(this)) - rsethBefore;

        rsethBalance += shares;
        totalDeposited += amount;
    }

    /// @notice Deposit stETH or other LSTs
    function depositLST(address lst, uint256 amount, uint256 minRsETH) external returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();

        IERC20(lst).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(lst).approve(DEPOSIT_POOL, amount);

        uint256 rsethBefore = IERC20(RSETH).balanceOf(address(this));
        IKelpLRTDepositPool(DEPOSIT_POOL).depositAsset(lst, amount, minRsETH, "lux_bridge");
        shares = IERC20(RSETH).balanceOf(address(this)) - rsethBefore;

        rsethBalance += shares;
        uint256 ethValue = IKelpLRTOracle(LRT_ORACLE).getAssetPrice(lst) * amount / 1e18;
        totalDeposited += ethValue;
    }

    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > rsethBalance) revert InsufficientBalance();
        if (recipient == address(0)) recipient = vault;

        amount = IrsETH(RSETH).convertToAssets(shares);

        IERC20(RSETH).approve(WITHDRAWAL_MANAGER, shares);
        IKelpWithdrawalManager(WITHDRAWAL_MANAGER).initiateWithdrawal(recipient, shares);

        rsethBalance -= shares;
        totalDeposited -= amount;
    }

    function harvest() external returns (uint256 harvested) {
        uint256 rsethPrice = IKelpLRTOracle(LRT_ORACLE).rsETHPrice();
        uint256 currentValue = (rsethBalance * rsethPrice) / 1e18;

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
        }
    }

    function totalAssets() external view returns (uint256) {
        uint256 rsethPrice = IKelpLRTOracle(LRT_ORACLE).rsETHPrice();
        return (rsethBalance * rsethPrice) / 1e18;
    }

    function currentAPY() external pure returns (uint256) {
        return 650; // ~6.5% APY
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Kelp rsETH Strategy";
    }



    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(RSETH).balanceOf(address(this));
        if (balance > 0) {
            IERC20(RSETH).safeTransfer(owner(), balance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWELL swETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Swell swETH Strategy
/// @notice Stakes ETH via Swell to receive swETH (liquid staking)
/// @dev swETH can be further restaked to rswETH for additional yield
contract SwellSwETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant SWELL_STAKING = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address public constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;

    address public vault;
    uint256 public swethBalance;
    uint256 public totalDeposited;
    address public referral;
    bool public isPaused;

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault, address _referral) Ownable(msg.sender) {
        vault = _vault;
        referral = _referral;
    }

    function deposit(uint256 amount, bytes calldata /* data */) external payable onlyVault returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (msg.value != amount) revert InvalidAmount();

        uint256 swethBefore = IERC20(SWETH).balanceOf(address(this));

        if (referral != address(0)) {
            ISwellStaking(SWELL_STAKING).depositWithReferral{value: amount}(referral);
        } else {
            ISwellStaking(SWELL_STAKING).deposit{value: amount}();
        }

        shares = IERC20(SWETH).balanceOf(address(this)) - swethBefore;
        swethBalance += shares;
        totalDeposited += amount;
    }

    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > swethBalance) revert InsufficientBalance();
        if (recipient == address(0)) recipient = vault;

        uint256 rate = IswETH(SWETH).swETHToETHRate();
        amount = (shares * rate) / 1e18;

        // Transfer swETH (vault can swap on DEX or wait for withdrawal queue)
        IERC20(SWETH).safeTransfer(vault, shares);

        swethBalance -= shares;
        totalDeposited -= amount;
    }

    function harvest() external returns (uint256 harvested) {
        uint256 rate = IswETH(SWETH).swETHToETHRate();
        uint256 currentValue = (swethBalance * rate) / 1e18;

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
        }
    }

    function totalAssets() external view returns (uint256) {
        uint256 rate = IswETH(SWETH).swETHToETHRate();
        return (swethBalance * rate) / 1e18;
    }

    function currentAPY() external pure returns (uint256) {
        return 450; // ~4.5% APY
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Swell swETH Strategy";
    }


    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setReferral(address _referral) external onlyOwner {
        referral = _referral;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(SWETH).balanceOf(address(this));
        if (balance > 0) {
            IERC20(SWETH).safeTransfer(owner(), balance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWELL rswETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Swell rswETH Strategy
/// @notice Stakes swETH via Swell's restaking vault for rswETH
/// @dev rswETH = swETH + EigenLayer restaking yield
contract SwellRswETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    address public constant RSWETH = 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0;
    address public constant SWELL_STAKING = 0xf951E335afb289353dc249e82926178EaC7DEd78;

    address public vault;
    uint256 public rswethBalance;
    uint256 public totalDeposited;
    bool public isPaused;

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        IERC20(SWETH).approve(RSWETH, type(uint256).max);
    }

    function deposit(uint256 amount, bytes calldata /* data */) external payable onlyVault returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (msg.value != amount) revert InvalidAmount();

        // First stake ETH -> swETH
        uint256 swethBefore = IERC20(SWETH).balanceOf(address(this));
        ISwellStaking(SWELL_STAKING).deposit{value: amount}();
        uint256 swethReceived = IERC20(SWETH).balanceOf(address(this)) - swethBefore;

        // Then restake swETH -> rswETH
        uint256 rswethBefore = IERC20(RSWETH).balanceOf(address(this));
        IrswETH(RSWETH).deposit(swethReceived, address(this));
        shares = IERC20(RSWETH).balanceOf(address(this)) - rswethBefore;

        rswethBalance += shares;
        totalDeposited += amount;
    }

    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > rswethBalance) revert InsufficientBalance();
        if (recipient == address(0)) recipient = vault;

        // Withdraw rswETH -> swETH
        uint256 swethReceived = IrswETH(RSWETH).withdraw(shares, recipient, address(this));

        uint256 swethRate = IswETH(SWETH).swETHToETHRate();
        amount = (swethReceived * swethRate) / 1e18;

        rswethBalance -= shares;
        totalDeposited -= amount;
    }

    function harvest() external returns (uint256 harvested) {
        uint256 currentValue = IrswETH(RSWETH).convertToAssets(rswethBalance);
        uint256 swethRate = IswETH(SWETH).swETHToETHRate();
        uint256 ethValue = (currentValue * swethRate) / 1e18;

        if (ethValue > totalDeposited) {
            harvested = ethValue - totalDeposited;
        }
    }

    function totalAssets() external view returns (uint256) {
        uint256 swethValue = IrswETH(RSWETH).convertToAssets(rswethBalance);
        uint256 swethRate = IswETH(SWETH).swETHToETHRate();
        return (swethValue * swethRate) / 1e18;
    }

    function currentAPY() external pure returns (uint256) {
        return 750; // ~7.5% APY
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Swell rswETH Strategy";
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(RSWETH).balanceOf(address(this));
        if (balance > 0) {
            IERC20(RSWETH).safeTransfer(owner(), balance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUFFER pufETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Puffer pufETH Strategy
/// @notice Stakes ETH via Puffer to receive pufETH
/// @dev Puffer uses anti-slashing technology for validator protection
///      Earns staking yield + AVS rewards + Puffer Points
contract PufferPufETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant PUFFER_VAULT = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address public vault;
    uint256 public pufethBalance;
    uint256 public totalDeposited;
    uint256 public pufferPoints;
    bool public isPaused;

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
        IERC20(STETH).approve(PUFFER_VAULT, type(uint256).max);
    }

    function deposit(uint256 amount, bytes calldata /* data */) external payable onlyVault returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (msg.value != amount) revert InvalidAmount();

        shares = IPufferVault(PUFFER_VAULT).depositETH{value: amount}(address(this));

        pufethBalance += shares;
        totalDeposited += amount;
    }

    /// @notice Deposit stETH to receive pufETH
    function depositStETH(uint256 amount) external returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();

        IERC20(STETH).safeTransferFrom(msg.sender, address(this), amount);
        shares = IPufferVault(PUFFER_VAULT).depositStETH(amount, address(this));

        pufethBalance += shares;
        totalDeposited += amount;
    }

    function withdraw(uint256 shares, address recipient, bytes calldata /* data */) external onlyVault returns (uint256 amount) {
        if (shares > pufethBalance) revert InsufficientBalance();
        if (recipient == address(0)) recipient = vault;

        amount = IPufferVault(PUFFER_VAULT).convertToAssets(shares);

        uint256 maxWithdraw = IPufferVault(PUFFER_VAULT).maxWithdraw(address(this));
        if (amount > maxWithdraw) revert InsufficientBalance();

        IPufferVault(PUFFER_VAULT).withdraw(amount, recipient, address(this));

        pufethBalance -= shares;
        totalDeposited -= amount;
    }

    function harvest() external returns (uint256 harvested) {
        uint256 currentValue = IPufferVault(PUFFER_VAULT).convertToAssets(pufethBalance);

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
        }
    }

    function totalAssets() external view returns (uint256) {
        return IPufferVault(PUFFER_VAULT).convertToAssets(pufethBalance);
    }

    function currentAPY() external pure returns (uint256) {
        return 650; // ~6.5% APY
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Puffer pufETH Strategy";
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(PUFFER_VAULT).balanceOf(address(this));
        if (balance > 0) {
            IERC20(PUFFER_VAULT).safeTransfer(owner(), balance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// RENZO ezETH STRATEGY
// ═══════════════════════════════════════════════════════════════════════════════

/// @title Renzo ezETH Strategy
/// @notice Stakes ETH via Renzo to receive ezETH
/// @dev Renzo supports cross-chain restaking via LayerZero
///      Earns staking yield + AVS rewards + Renzo Points
contract RenzoEzETHStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant RESTAKE_MANAGER = 0x74a09653A083691711cF8215a6ab074BB4e99ef5;
    address public constant EZETH = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
    address public constant RENZO_ORACLE = 0x5a12796f7e7EBbbc8a402667d266d2e65A814042;
    address public constant WITHDRAW_QUEUE = 0x2F7e9498f94C5fbAA4aA05Fc4b1AD4d8d39e6BC0;

    address public vault;
    uint256 public ezethBalance;
    uint256 public totalDeposited;
    uint256 public renzoPoints;
    uint256 public referralId;
    bool public isPaused;

    error StrategyPaused();
    error OnlyVault();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address _vault) Ownable(msg.sender) {
        vault = _vault;
    }

    function deposit(uint256 amount) external payable onlyVault returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();
        if (msg.value != amount) revert InvalidAmount();

        uint256 ezethBefore = IERC20(EZETH).balanceOf(address(this));

        if (referralId != 0) {
            IRenzoRestakeManager(RESTAKE_MANAGER).depositETH{value: amount}(referralId);
        } else {
            IRenzoRestakeManager(RESTAKE_MANAGER).depositETH{value: amount}();
        }

        shares = IERC20(EZETH).balanceOf(address(this)) - ezethBefore;
        ezethBalance += shares;
        totalDeposited += amount;
    }

    /// @notice Deposit supported collateral tokens (stETH, wBETH)
    function depositCollateral(address token, uint256 amount) external returns (uint256 shares) {
        if (isPaused) revert StrategyPaused();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(RESTAKE_MANAGER, amount);

        uint256 ezethBefore = IERC20(EZETH).balanceOf(address(this));

        if (referralId != 0) {
            IRenzoRestakeManager(RESTAKE_MANAGER).deposit(token, amount, referralId);
        } else {
            IRenzoRestakeManager(RESTAKE_MANAGER).deposit(token, amount);
        }

        shares = IERC20(EZETH).balanceOf(address(this)) - ezethBefore;
        ezethBalance += shares;

        uint256 ethValue = IRenzoOracle(RENZO_ORACLE).lookupTokenValue(token, amount);
        totalDeposited += ethValue;
    }

    function withdraw(uint256 shares) external onlyVault returns (uint256 amount) {
        if (shares > ezethBalance) revert InsufficientBalance();

        // Calculate ETH value
        (,, uint256 totalTVL) = IRenzoRestakeManager(RESTAKE_MANAGER).calculateTVLs();
        uint256 ezethSupply = IezETH(EZETH).totalSupply();
        amount = (shares * totalTVL) / ezethSupply;

        // Initiate withdrawal (Renzo queue-based, recipient not applicable here)
        IERC20(EZETH).approve(WITHDRAW_QUEUE, shares);
        IRenzoWithdrawQueue(WITHDRAW_QUEUE).withdraw(shares, address(0));

        ezethBalance -= shares;
        totalDeposited -= amount;
    }

    function harvest() external returns (uint256 harvested) {
        (,, uint256 totalTVL) = IRenzoRestakeManager(RESTAKE_MANAGER).calculateTVLs();
        uint256 ezethSupply = IezETH(EZETH).totalSupply();
        uint256 currentValue = (ezethBalance * totalTVL) / ezethSupply;

        if (currentValue > totalDeposited) {
            harvested = currentValue - totalDeposited;
        }
    }

    function totalAssets() external view returns (uint256) {
        (,, uint256 totalTVL) = IRenzoRestakeManager(RESTAKE_MANAGER).calculateTVLs();
        uint256 ezethSupply = IezETH(EZETH).totalSupply();
        return (ezethBalance * totalTVL) / ezethSupply;
    }

    function currentAPY() external pure returns (uint256) {
        return 700; // ~7% APY
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function isActive() external view returns (bool) {
        return !isPaused;
    }

    function name() external pure returns (string memory) {
        return "Renzo ezETH Strategy";
    }


    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setReferralId(uint256 _referralId) external onlyOwner {
        referralId = _referralId;
    }

    function setPaused(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(EZETH).balanceOf(address(this));
        if (balance > 0) {
            IERC20(EZETH).safeTransfer(owner(), balance);
        }
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════════
// LRT STRATEGY AGGREGATOR
// ═══════════════════════════════════════════════════════════════════════════════

/// @title LRT Strategy Aggregator
/// @notice Routes deposits to optimal LRT strategy based on APY and points
/// @dev Can rebalance between protocols based on performance
contract LRTStrategyAggregator is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct StrategyInfo {
        address strategy;
        uint256 allocation; // Basis points (10000 = 100%)
        bool active;
        string protocolName;
    }

    StrategyInfo[] public strategies;
    uint256 public totalDeposited;
    uint256 public maxSingleAllocation = 5000; // 50%
    uint256 public minDeposit = 0.01 ether;

    event StrategyAdded(address indexed strategy, string protocolName);
    event StrategyRemoved(address indexed strategy);
    event Deposited(address indexed user, uint256 amount);

    error InvalidAllocation();
    error BelowMinimum();

    constructor(address _owner) Ownable(_owner) {}

    function addStrategy(address _strategy, uint256 _allocation, string calldata _protocolName) external onlyOwner {
        if (_allocation > maxSingleAllocation) revert InvalidAllocation();

        strategies.push(StrategyInfo({
            strategy: _strategy,
            allocation: _allocation,
            active: true,
            protocolName: _protocolName
        }));

        emit StrategyAdded(_strategy, _protocolName);
    }

    function removeStrategy(uint256 index) external onlyOwner {
        address strategy = strategies[index].strategy;
        strategies[index] = strategies[strategies.length - 1];
        strategies.pop();
        emit StrategyRemoved(strategy);
    }

    function updateAllocation(uint256 index, uint256 _allocation) external onlyOwner {
        if (_allocation > maxSingleAllocation) revert InvalidAllocation();
        strategies[index].allocation = _allocation;
    }

    function deposit() external payable nonReentrant returns (uint256[] memory shares) {
        if (msg.value < minDeposit) revert BelowMinimum();

        uint256 totalValue = msg.value; // Cache msg.value before loop
        shares = new uint256[](strategies.length);
        uint256 remaining = totalValue;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (!strategies[i].active) continue;

            uint256 amount = (totalValue * strategies[i].allocation) / 10000;
            if (amount > remaining) amount = remaining;

            if (amount > 0) {
                shares[i] = IYieldStrategy(strategies[i].strategy).deposit{value: amount}(amount);
                remaining -= amount;
            }
        }

        totalDeposited += totalValue;
        emit Deposited(msg.sender, totalValue);
    }

    function totalAssets() external view returns (uint256 total) {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                total += IYieldStrategy(strategies[i].strategy).totalAssets();
            }
        }
    }

    function averageAPY() external view returns (uint256 weightedAPY) {
        uint256 totalAllocation;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                weightedAPY += IYieldStrategy(strategies[i].strategy).currentAPY() * strategies[i].allocation;
                totalAllocation += strategies[i].allocation;
            }
        }
        if (totalAllocation > 0) {
            weightedAPY = weightedAPY / totalAllocation;
        }
    }

    function getAllStrategies() external view returns (StrategyInfo[] memory) {
        return strategies;
    }

    function harvestAll() external returns (uint256 totalYield) {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                totalYield += IYieldStrategy(strategies[i].strategy).harvest();
            }
        }
    }

    function setMaxSingleAllocation(uint256 _max) external onlyOwner {
        if (_max > 10000) revert InvalidAllocation();
        maxSingleAllocation = _max;
    }

    function setMinDeposit(uint256 _min) external onlyOwner {
        minDeposit = _min;
    }

    receive() external payable {}
}
