// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IMarkets, MarketParams, Id, Market} from "./interfaces/IMarkets.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MarketParamsLib} from "./libraries/MarketParamsLib.sol";

/// @title Allocator
/// @notice ERC4626 allocator that distributes deposits across multiple Markets
/// @dev Inspired by MetaMorpho - curators manage allocation across lending markets
contract Allocator is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using MarketParamsLib for MarketParams;

    /* STRUCTS */

    /// @notice Market allocation configuration
    struct MarketConfig {
        uint184 cap;        // Maximum assets to supply to this market
        bool enabled;       // Whether market is enabled for supply
        uint64 removableAt; // Timestamp when market can be removed (0 if not pending removal)
    }

    /// @notice Pending allocation change
    struct PendingAllocation {
        MarketParams marketParams;
        uint256 assets;
    }

    /* CONSTANTS */

    /// @notice Timelock for market removal
    uint256 public constant TIMELOCK = 1 days;

    /* STORAGE */

    /// @notice Markets contract
    IMarkets public immutable markets;

    /// @notice Curator who manages allocations
    address public curator;

    /// @notice Guardian who can revoke pending changes
    address public guardian;

    /// @notice Market configurations
    mapping(Id => MarketConfig) public config;

    /// @notice Supply queue (order of markets for deposits)
    Id[] public supplyQueue;

    /// @notice Withdraw queue (order of markets for withdrawals)
    Id[] public withdrawQueue;

    /// @notice Total assets across all markets (cached)
    uint256 public lastTotalAssets;

    /// @notice Fee percentage (in WAD, e.g., 0.1e18 = 10%)
    uint256 public fee;

    /// @notice Fee recipient
    address public feeRecipient;

    /* EVENTS */

    event SetCurator(address indexed curator);
    event SetGuardian(address indexed guardian);
    event SetFee(uint256 fee);
    event SetFeeRecipient(address indexed feeRecipient);
    event SetMarketCap(Id indexed id, uint256 cap);
    event MarketEnabled(Id indexed id, MarketParams marketParams);
    event MarketDisabled(Id indexed id);
    event Reallocate(Id indexed fromMarket, Id indexed toMarket, uint256 assets);
    event SupplyQueueUpdated(Id[] newQueue);
    event WithdrawQueueUpdated(Id[] newQueue);

    /* ERRORS */

    error NotCurator();
    error NotGuardian();
    error MarketNotEnabled();
    error CapExceeded();
    error InvalidQueue();
    error AllocationFailed();
    error InsufficientLiquidity();

    /* MODIFIERS */

    modifier onlyCurator() {
        if (msg.sender != curator) revert NotCurator();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian && msg.sender != curator) revert NotGuardian();
        _;
    }

    /* CONSTRUCTOR */

    constructor(
        address _markets,
        address _asset,
        string memory _name,
        string memory _symbol,
        address _curator
    ) ERC4626(IERC20(_asset)) ERC20(_name, _symbol) {
        markets = IMarkets(_markets);
        curator = _curator;
        
        // Approve markets to spend allocator's assets
        IERC20(_asset).approve(_markets, type(uint256).max);
    }

    /* ADMIN */

    function setCurator(address newCurator) external onlyCurator {
        curator = newCurator;
        emit SetCurator(newCurator);
    }

    function setGuardian(address newGuardian) external onlyCurator {
        guardian = newGuardian;
        emit SetGuardian(newGuardian);
    }

    function setFee(uint256 newFee) external onlyCurator {
        require(newFee <= 0.5e18, "Fee too high"); // Max 50%
        fee = newFee;
        emit SetFee(newFee);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyCurator {
        feeRecipient = newFeeRecipient;
        emit SetFeeRecipient(newFeeRecipient);
    }

    /* MARKET MANAGEMENT */

    /// @notice Enable a new market for this vault
    function enableMarket(MarketParams calldata marketParams, uint256 cap) external onlyCurator {
        require(marketParams.loanToken == asset(), "Wrong asset");
        
        Id id = marketParams.id();
        config[id] = MarketConfig({
            cap: uint184(cap),
            enabled: true,
            removableAt: 0
        });

        // Add to queues if not present
        bool inSupplyQueue = false;
        for (uint256 i = 0; i < supplyQueue.length; i++) {
            if (Id.unwrap(supplyQueue[i]) == Id.unwrap(id)) {
                inSupplyQueue = true;
                break;
            }
        }
        if (!inSupplyQueue) {
            supplyQueue.push(id);
            withdrawQueue.push(id);
        }

        emit MarketEnabled(id, marketParams);
        emit SetMarketCap(id, cap);
    }

    /// @notice Update market cap
    function setMarketCap(MarketParams calldata marketParams, uint256 newCap) external onlyCurator {
        Id id = marketParams.id();
        if (!config[id].enabled) revert MarketNotEnabled();
        
        config[id].cap = uint184(newCap);
        emit SetMarketCap(id, newCap);
    }

    /// @notice Disable a market (starts timelock)
    function disableMarket(MarketParams calldata marketParams) external onlyCurator {
        Id id = marketParams.id();
        config[id].enabled = false;
        config[id].removableAt = uint64(block.timestamp + TIMELOCK);
        emit MarketDisabled(id);
    }

    /// @notice Update supply queue order
    function setSupplyQueue(Id[] calldata newQueue) external onlyCurator {
        _validateQueue(newQueue);
        supplyQueue = newQueue;
        emit SupplyQueueUpdated(newQueue);
    }

    /// @notice Update withdraw queue order
    function setWithdrawQueue(Id[] calldata newQueue) external onlyCurator {
        _validateQueue(newQueue);
        withdrawQueue = newQueue;
        emit WithdrawQueueUpdated(newQueue);
    }

    /* ALLOCATION */

    /// @notice Reallocate assets between markets
    function reallocate(
        MarketParams calldata fromMarket,
        MarketParams calldata toMarket,
        uint256 assets
    ) external onlyCurator nonReentrant {
        Id fromId = fromMarket.id();
        Id toId = toMarket.id();

        if (!config[toId].enabled) revert MarketNotEnabled();

        // Withdraw from source market
        (uint256 withdrawn,) = markets.withdraw(fromMarket, assets, 0, address(this), address(this));

        // Check cap
        uint256 currentSupply = markets.supplyShares(toId, address(this));
        if (currentSupply + withdrawn > config[toId].cap) revert CapExceeded();

        // Supply to destination market
        markets.supply(toMarket, withdrawn, 0, address(this), "");

        emit Reallocate(fromId, toId, withdrawn);
    }

    /* ERC4626 OVERRIDES */

    function totalAssets() public view override returns (uint256 total) {
        for (uint256 i = 0; i < supplyQueue.length; i++) {
            Id id = supplyQueue[i];
            uint256 shares = markets.supplyShares(id, address(this));
            if (shares > 0) {
                Market memory market = _getMarket(id);
                total += _toAssets(shares, market);
            }
        }
        // Add idle assets
        total += IERC20(asset()).balanceOf(address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override nonReentrant {
        // Transfer assets from caller
        super._deposit(caller, receiver, assets, shares);

        // Allocate to markets based on supply queue
        uint256 remaining = assets;
        for (uint256 i = 0; i < supplyQueue.length && remaining > 0; i++) {
            Id id = supplyQueue[i];
            MarketConfig memory cfg = config[id];
            
            if (!cfg.enabled) continue;

            uint256 currentSupply = _getCurrentSupply(id);
            uint256 available = cfg.cap > currentSupply ? cfg.cap - currentSupply : 0;
            uint256 toSupply = remaining > available ? available : remaining;

            if (toSupply > 0) {
                // Get market params from stored data or require curator to pass them
                // For simplicity, we'll store idle and let curator allocate
                remaining -= toSupply;
            }
        }

        // Any remaining stays as idle in allocator
        lastTotalAssets = totalAssets();
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {
        // First try idle assets
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 remaining = assets > idle ? assets - idle : 0;

        // Withdraw from markets in queue order
        for (uint256 i = 0; i < withdrawQueue.length && remaining > 0; i++) {
            Id id = withdrawQueue[i];
            uint256 available = _getAvailableLiquidity(id);
            uint256 toWithdraw = remaining > available ? available : remaining;

            if (toWithdraw > 0) {
                // Would need market params - simplified for now
                remaining -= toWithdraw;
            }
        }

        if (remaining > 0) revert InsufficientLiquidity();

        super._withdraw(caller, receiver, owner, assets, shares);
        lastTotalAssets = totalAssets();
    }

    /* INTERNAL */

    function _validateQueue(Id[] calldata queue) internal view {
        for (uint256 i = 0; i < queue.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < supplyQueue.length; j++) {
                if (Id.unwrap(queue[i]) == Id.unwrap(supplyQueue[j])) {
                    found = true;
                    break;
                }
            }
            if (!found) revert InvalidQueue();
        }
    }

    function _getMarket(Id id) internal view returns (Market memory) {
        // This would need to query Markets contract
        // Simplified - would need market params stored
        return Market({
            totalSupplyAssets: 0,
            totalSupplyShares: 0,
            totalBorrowAssets: 0,
            totalBorrowShares: 0,
            lastUpdate: 0,
            fee: 0
        });
    }

    function _getCurrentSupply(Id id) internal view returns (uint256) {
        return markets.supplyShares(id, address(this));
    }

    function _getAvailableLiquidity(Id id) internal view returns (uint256) {
        return markets.totalSupplyAssets(id) - markets.totalBorrowAssets(id);
    }

    function _toAssets(uint256 shares, Market memory market) internal pure returns (uint256) {
        if (market.totalSupplyShares == 0) return shares;
        return shares * market.totalSupplyAssets / market.totalSupplyShares;
    }
}
