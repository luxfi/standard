// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "../IYieldStrategy.sol";

/**
 * @title BitcoinNativeYield
 * @notice Aggregated Bitcoin-native yield strategies
 * @dev Routes BTC to native Bitcoin yield sources:
 *
 *      1. Babylon Staking (BTC staking for PoS security)
 *         - Lock BTC in Babylon covenant → earn staking rewards
 *         - BTC remains on Bitcoin L1 (self-custodied via timelock)
 *         - ~3-8% APY from securing Cosmos/PoS chains
 *
 *      2. Lombard Finance (LBTC liquid staking)
 *         - Deposit BTC → receive LBTC (liquid staking token)
 *         - LBTC earns Babylon + Lombard rewards
 *         - ~4-6% APY
 *
 *      3. SolvBTC (BTC yield aggregator)
 *         - Deposit BTC → SolvBTC yield tokens
 *         - Aggregates: CeDeFi, restaking, delta-neutral
 *         - ~5-12% APY
 *
 *      4. CoreDAO Bitcoin Staking (Non-custodial)
 *         - Time-lock BTC on Bitcoin L1
 *         - Earn CORE rewards via Satoshi Plus
 *         - ~3-5% APY
 *
 *      5. BounceBit BTC Restaking
 *         - Deposit BTC → stBBTC → restake for CeDeFi yield
 *         - Dual-token staking model
 *         - ~6-10% APY
 *
 *      6. Corn (BTCN)
 *         - Super yield on Bitcoin via tokenized BTC
 *         - ~8-15% APY
 *
 *      7. Mezo Bitcoin Economic Layer
 *         - BTC deposits earn from Bitcoin economic activity
 *         - ~4-8% APY
 *
 *      Teleport integration:
 *      - User teleports BTC from Bitcoin L1 → FROST vault locks BTC
 *      - BTC deployed to Babylon/Lombard/Solv via MPC-controlled accounts
 *      - User receives yLBTC on Lux (yield-bearing bridged BTC)
 *      - yLBTC earns aggregated BTC yield from all strategies
 *      - yLBTC usable in LPX Perps, Markets, AMMs on Lux
 *      - MPC reports yield back via Warp → yLBTC share price increases
 */

// Babylon interfaces (BTC staking)
interface IBabylonStaking {
    function createStakingTx(
        bytes calldata stakerPk,
        bytes calldata finalityPk,
        uint16 stakingTime,
        uint64 stakingAmount
    ) external returns (bytes32 txHash);

    function getStakerDelegation(bytes calldata stakerPk) external view returns (
        uint64 totalSatoshis,
        uint64 activeSatoshis,
        uint64 pendingRewards
    );
}

// Lombard LBTC interface
interface ILombard {
    function deposit(uint256 amount) external returns (uint256 lbtcAmount);
    function withdraw(uint256 lbtcAmount) external returns (uint256 btcAmount);
    function exchangeRate() external view returns (uint256); // LBTC per BTC (scaled 1e18)
    function totalBtcDeposited() external view returns (uint256);
}

// SolvBTC interface
interface ISolvBTC {
    function deposit(uint256 amount, address receiver) external returns (uint256 shares);
    function withdraw(uint256 shares, address receiver) external returns (uint256 amount);
    function totalAssets() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

// CoreDAO staking interface
interface ICoreStaking {
    function delegateStake(bytes calldata btcTxHash, uint256 amount) external returns (bool);
    function claimReward() external returns (uint256);
    function stakedAmount(address staker) external view returns (uint256);
}

contract BitcoinNativeYield is IYieldStrategy {

    // Strategy allocations (basis points, total = 10000)
    struct StrategyAllocation {
        uint256 babylonBps;    // Babylon staking
        uint256 lombardBps;    // Lombard LBTC
        uint256 solvBps;       // SolvBTC
        uint256 coreBps;       // CoreDAO
        uint256 reserveBps;    // Liquid reserve (unallocated)
    }

    address public immutable wbtc; // WBTC or wrapped BTC
    address public admin;
    bool public active;
    StrategyAllocation public allocation;

    // Strategy contracts (set by admin, chain-specific)
    address public babylonStaking;
    address public lombard;
    address public solvBTC;
    address public coreStaking;

    uint256 private _totalDeposited;
    uint256 private _lastHarvestTimestamp;

    constructor(address _wbtc) {
        wbtc = _wbtc;
        admin = msg.sender;
        active = true;
        // Default: diversified across all BTC yield sources
        allocation = StrategyAllocation({
            babylonBps: 3000,  // 30% Babylon
            lombardBps: 2500,  // 25% Lombard
            solvBps: 2000,     // 20% SolvBTC
            coreBps: 1500,     // 15% CoreDAO
            reserveBps: 1000   // 10% liquid reserve
        });
        _lastHarvestTimestamp = block.timestamp;
    }

    function deposit(uint256 amount) external payable override returns (uint256 shares) {
        require(active, "Inactive");
        IERC20(wbtc).transferFrom(msg.sender, address(this), amount);

        // Route to strategies based on allocation
        if (babylonStaking != address(0) && allocation.babylonBps > 0) {
            uint256 babylonAmount = amount * allocation.babylonBps / 10000;
            IERC20(wbtc).approve(babylonStaking, babylonAmount);
            // Babylon deposit handled by MPC (needs Bitcoin L1 tx)
        }

        if (lombard != address(0) && allocation.lombardBps > 0) {
            uint256 lombardAmount = amount * allocation.lombardBps / 10000;
            IERC20(wbtc).approve(lombard, lombardAmount);
            ILombard(lombard).deposit(lombardAmount);
        }

        if (solvBTC != address(0) && allocation.solvBps > 0) {
            uint256 solvAmount = amount * allocation.solvBps / 10000;
            IERC20(wbtc).approve(solvBTC, solvAmount);
            ISolvBTC(solvBTC).deposit(solvAmount, address(this));
        }

        _totalDeposited += amount;
        return amount; // 1:1 shares initially
    }

    function withdraw(uint256 shares) external override returns (uint256 assets) {
        // Withdraw proportionally from each strategy
        // In production: withdrawal queue with MPC coordination
        return shares;
    }

    function totalAssets() external view override returns (uint256) {
        uint256 total = IERC20(wbtc).balanceOf(address(this)); // liquid reserve

        if (lombard != address(0)) {
            uint256 lbtcBal = IERC20(lombard).balanceOf(address(this));
            total += lbtcBal * ILombard(lombard).exchangeRate() / 1e18;
        }

        if (solvBTC != address(0)) {
            uint256 solvShares = IERC20(solvBTC).balanceOf(address(this));
            total += ISolvBTC(solvBTC).convertToAssets(solvShares);
        }

        // Babylon + Core amounts reported by MPC watcher
        return total;
    }

    function currentAPY() external pure override returns (uint256) {
        // Blended: 30% @ 5% + 25% @ 4.5% + 20% @ 8% + 15% @ 4% + 10% @ 0%
        // = 1.5 + 1.125 + 1.6 + 0.6 = 4.825% ≈ 483 bps
        return 483;
    }

    function asset() external view override returns (address) { return wbtc; }

    function harvest() external override returns (uint256 harvested) {
        // Claim rewards from each protocol
        if (coreStaking != address(0)) {
            harvested += ICoreStaking(coreStaking).claimReward();
        }
        // Lombard + SolvBTC auto-compound (share price increases)
        // Babylon rewards claimed by MPC watcher
        _lastHarvestTimestamp = block.timestamp;
        return harvested;
    }

    function isActive() external view override returns (bool) { return active; }
    function name() external pure override returns (string memory) { return "Bitcoin Native Yield (Babylon+Lombard+Solv+Core)"; }
    function totalDeposited() external view override returns (uint256) { return _totalDeposited; }

    // Admin
    function setAllocation(StrategyAllocation calldata _alloc) external {
        require(msg.sender == admin, "Not admin");
        require(
            _alloc.babylonBps + _alloc.lombardBps + _alloc.solvBps +
            _alloc.coreBps + _alloc.reserveBps == 10000,
            "Must total 100%"
        );
        allocation = _alloc;
    }

    function setStrategyAddresses(
        address _babylon,
        address _lombard,
        address _solv,
        address _core
    ) external {
        require(msg.sender == admin, "Not admin");
        babylonStaking = _babylon;
        lombard = _lombard;
        solvBTC = _solv;
        coreStaking = _core;
    }
}

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
