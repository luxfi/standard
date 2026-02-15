// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026 Lux Industries Inc.
pragma solidity ^0.8.31;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReserveDTF
/// @notice Basket/set token primitive for Reserve-style DTF categories:
///         Stable DTFs, Yield DTFs, and Index DTFs.
/// @dev Collateral is held directly in this contract. Mint/redeem is pro-rata.
contract ReserveDTF is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MAX_COMPONENTS = 32;

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    enum Category {
        STABLE,
        YIELD,
        INDEX
    }

    struct Component {
        address token;
        uint16 targetWeightBps;
        bool yieldBearing;
    }

    struct RebalanceAuction {
        bool active;
        uint64 startTime;
        uint64 endTime;
        uint16 startPremiumBps;
        uint16 endPremiumBps;
        bytes32 basketHash;
    }

    error ZeroAddress();
    error ZeroAmount();
    error InvalidBps();
    error InvalidConfig();
    error InvalidLength();
    error TooManyComponents();
    error ComponentExists();
    error UnknownComponent();
    error InvalidWeights();
    error SlippageExceeded();
    error WrongCategory();
    error AuctionActive();
    error NoActiveAuction();

    event ComponentAdded(address indexed token, uint16 weightBps, bool yieldBearing);
    event ComponentWeightUpdated(address indexed token, uint16 oldWeightBps, uint16 newWeightBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeesUpdated(uint256 mintFeeBps, uint256 managementFeeBps);
    event StableRiskUpdated(bytes32 pegReference, uint256 minCollateralRatioBps);
    event Minted(address indexed account, uint256 sharesOut, uint256 feeShares);
    event Redeemed(address indexed account, uint256 sharesIn);
    event YieldHarvested(address indexed caller, address indexed token, uint256 amount);
    event ManagementFeeAccrued(uint256 sharesMinted);
    event RebalanceStarted(uint64 startTime, uint64 endTime, uint16 startPremiumBps, uint16 endPremiumBps, bytes32 basketHash);
    event RebalanceFinished(bytes32 executedBasketHash);

    Category public immutable category;
    address public feeRecipient;

    // Stable DTF configuration
    bytes32 public pegReference;
    uint256 public minCollateralRatioBps;

    // Index fee configuration
    uint256 public mintFeeBps;
    uint256 public managementFeeBps;
    uint256 public lastFeeAccrual;

    uint256 public totalTargetWeightBps;

    Component[] private _components;
    mapping(address => bool) public isComponent;
    mapping(address => uint256) private _componentIndexPlusOne;

    RebalanceAuction public auction;

    constructor(
        string memory name_,
        string memory symbol_,
        Category category_,
        address admin_,
        address feeRecipient_,
        bytes32 pegReference_,
        uint256 minCollateralRatioBps_
    ) ERC20(name_, symbol_) {
        if (admin_ == address(0) || feeRecipient_ == address(0)) revert ZeroAddress();

        category = category_;
        feeRecipient = feeRecipient_;
        lastFeeAccrual = block.timestamp;

        if (category_ == Category.STABLE) {
            if (pegReference_ == bytes32(0) || minCollateralRatioBps_ < BPS) revert InvalidConfig();
            pegReference = pegReference_;
            minCollateralRatioBps = minCollateralRatioBps_;
        } else {
            if (pegReference_ != bytes32(0) || minCollateralRatioBps_ != 0) revert InvalidConfig();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GOVERNOR_ROLE, admin_);
        _grantRole(HARVESTER_ROLE, admin_);
        _grantRole(REBALANCER_ROLE, admin_);
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIG
    //////////////////////////////////////////////////////////////*/

    function setFeeRecipient(address newRecipient) external onlyRole(GOVERNOR_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        address old = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(old, newRecipient);
    }

    /// @notice Configure mint and management fees (in bps, max 10% each)
    function setFees(uint256 mintFeeBps_, uint256 managementFeeBps_) external onlyRole(GOVERNOR_ROLE) {
        if (mintFeeBps_ > 1_000 || managementFeeBps_ > 1_000) revert InvalidBps();
        mintFeeBps = mintFeeBps_;
        managementFeeBps = managementFeeBps_;
        lastFeeAccrual = block.timestamp;
        emit FeesUpdated(mintFeeBps_, managementFeeBps_);
    }

    function setStableRisk(bytes32 pegReference_, uint256 minCollateralRatioBps_) external onlyRole(GOVERNOR_ROLE) {
        if (category != Category.STABLE) revert WrongCategory();
        if (pegReference_ == bytes32(0) || minCollateralRatioBps_ < BPS) revert InvalidConfig();
        pegReference = pegReference_;
        minCollateralRatioBps = minCollateralRatioBps_;
        emit StableRiskUpdated(pegReference_, minCollateralRatioBps_);
    }

    function addComponent(address token, uint16 weightBps, bool yieldBearing) external onlyRole(GOVERNOR_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (_components.length >= MAX_COMPONENTS) revert TooManyComponents();
        if (isComponent[token]) revert ComponentExists();
        if (weightBps == 0) revert InvalidBps();
        if (category == Category.STABLE && yieldBearing) revert InvalidConfig();

        _components.push(Component({token: token, targetWeightBps: weightBps, yieldBearing: yieldBearing}));
        _componentIndexPlusOne[token] = _components.length;
        isComponent[token] = true;
        totalTargetWeightBps += weightBps;

        emit ComponentAdded(token, weightBps, yieldBearing);
    }

    function setComponentWeight(address token, uint16 newWeightBps) external onlyRole(GOVERNOR_ROLE) {
        if (newWeightBps == 0) revert InvalidBps();
        uint256 indexPlusOne = _componentIndexPlusOne[token];
        if (indexPlusOne == 0) revert UnknownComponent();

        uint256 idx = indexPlusOne - 1;
        uint16 old = _components[idx].targetWeightBps;
        _components[idx].targetWeightBps = newWeightBps;

        totalTargetWeightBps = totalTargetWeightBps - old + newWeightBps;
        emit ComponentWeightUpdated(token, old, newWeightBps);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT / REDEEM
    //////////////////////////////////////////////////////////////*/

    function previewMint(uint256 sharesOut)
        external
        view
        returns (uint256[] memory requiredAmounts, uint256 feeShares, uint256 totalShares)
    {
        return _previewMint(sharesOut);
    }

    function mint(uint256 sharesOut, uint256[] calldata maxAmountsIn)
        external
        nonReentrant
        returns (uint256 feeShares, uint256 totalShares)
    {
        if (category == Category.INDEX) _accrueManagementFee();

        (uint256[] memory requiredAmounts, uint256 fee, uint256 total) = _previewMint(sharesOut);
        if (maxAmountsIn.length != requiredAmounts.length) revert InvalidLength();

        for (uint256 i = 0; i < requiredAmounts.length; i++) {
            if (requiredAmounts[i] > maxAmountsIn[i]) revert SlippageExceeded();
            IERC20(_components[i].token).safeTransferFrom(msg.sender, address(this), requiredAmounts[i]);
        }

        _mint(msg.sender, sharesOut);
        if (fee > 0) _mint(feeRecipient, fee);

        emit Minted(msg.sender, sharesOut, fee);
        return (fee, total);
    }

    function previewRedeem(uint256 sharesIn) external view returns (uint256[] memory amountsOut) {
        return _previewRedeem(sharesIn);
    }

    function redeem(uint256 sharesIn, uint256[] calldata minAmountsOut)
        external
        nonReentrant
        returns (uint256[] memory amountsOut)
    {
        if (category == Category.INDEX) _accrueManagementFee();

        amountsOut = _previewRedeem(sharesIn);
        if (minAmountsOut.length != amountsOut.length) revert InvalidLength();

        _burn(msg.sender, sharesIn);

        for (uint256 i = 0; i < amountsOut.length; i++) {
            if (amountsOut[i] < minAmountsOut[i]) revert SlippageExceeded();
            IERC20(_components[i].token).safeTransfer(msg.sender, amountsOut[i]);
        }

        emit Redeemed(msg.sender, sharesIn);
    }

    /*//////////////////////////////////////////////////////////////
                                YIELD
    //////////////////////////////////////////////////////////////*/

    /// @notice Pulls harvested yield into basket collateral.
    /// @dev For YIELD category only; value accrues pro-rata to all holders.
    function harvestYield(address token, uint256 amount) external onlyRole(HARVESTER_ROLE) {
        if (category != Category.YIELD) revert WrongCategory();
        if (!isComponent[token]) revert UnknownComponent();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldHarvested(msg.sender, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INDEX FEES / REBALANCE
    //////////////////////////////////////////////////////////////*/

    function accrueManagementFee() external returns (uint256) {
        if (category != Category.INDEX) revert WrongCategory();
        return _accrueManagementFee();
    }

    function startRebalanceAuction(
        uint64 duration,
        uint16 startPremiumBps,
        uint16 endPremiumBps,
        bytes32 basketHash
    ) external onlyRole(REBALANCER_ROLE) {
        if (category != Category.INDEX) revert WrongCategory();
        if (auction.active) revert AuctionActive();
        if (duration == 0 || basketHash == bytes32(0)) revert InvalidConfig();
        if (startPremiumBps > BPS || endPremiumBps > BPS) revert InvalidBps();

        uint64 start = uint64(block.timestamp);
        uint64 end = start + duration;
        auction = RebalanceAuction({
            active: true,
            startTime: start,
            endTime: end,
            startPremiumBps: startPremiumBps,
            endPremiumBps: endPremiumBps,
            basketHash: basketHash
        });

        emit RebalanceStarted(start, end, startPremiumBps, endPremiumBps, basketHash);
    }

    function currentAuctionPremiumBps() public view returns (uint256) {
        if (!auction.active) return 0;
        if (block.timestamp >= auction.endTime) return auction.endPremiumBps;

        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 duration = auction.endTime - auction.startTime;

        if (auction.startPremiumBps >= auction.endPremiumBps) {
            uint256 delta = (uint256(auction.startPremiumBps - auction.endPremiumBps) * elapsed) / duration;
            return uint256(auction.startPremiumBps) - delta;
        }

        uint256 increase = (uint256(auction.endPremiumBps - auction.startPremiumBps) * elapsed) / duration;
        return uint256(auction.startPremiumBps) + increase;
    }

    function finishRebalanceAuction(bytes32 executedBasketHash) external onlyRole(REBALANCER_ROLE) {
        if (category != Category.INDEX) revert WrongCategory();
        if (!auction.active) revert NoActiveAuction();
        if (executedBasketHash == bytes32(0)) revert InvalidConfig();

        auction.active = false;
        auction.basketHash = executedBasketHash;

        emit RebalanceFinished(executedBasketHash);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    function componentCount() external view returns (uint256) {
        return _components.length;
    }

    function getComponent(uint256 index) external view returns (Component memory) {
        return _components[index];
    }

    function getComponents() external view returns (Component[] memory) {
        return _components;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _previewMint(uint256 sharesOut)
        internal
        view
        returns (uint256[] memory requiredAmounts, uint256 feeShares, uint256 totalShares)
    {
        if (sharesOut == 0) revert ZeroAmount();
        if (_components.length == 0) revert InvalidConfig();
        if (totalTargetWeightBps != BPS) revert InvalidWeights();

        feeShares = (sharesOut * mintFeeBps) / BPS;
        totalShares = sharesOut + feeShares;

        uint256 supply = totalSupply();
        requiredAmounts = new uint256[](_components.length);

        if (supply == 0) {
            for (uint256 i = 0; i < _components.length; i++) {
                requiredAmounts[i] = _mulDivUp(totalShares, _components[i].targetWeightBps, BPS);
            }
            return (requiredAmounts, feeShares, totalShares);
        }

        for (uint256 i = 0; i < _components.length; i++) {
            uint256 bal = IERC20(_components[i].token).balanceOf(address(this));
            requiredAmounts[i] = _mulDivUp(bal, totalShares, supply);
        }
    }

    function _previewRedeem(uint256 sharesIn) internal view returns (uint256[] memory amountsOut) {
        if (sharesIn == 0) revert ZeroAmount();
        uint256 supply = totalSupply();
        if (supply == 0 || sharesIn > supply) revert InvalidConfig();

        amountsOut = new uint256[](_components.length);
        for (uint256 i = 0; i < _components.length; i++) {
            uint256 bal = IERC20(_components[i].token).balanceOf(address(this));
            amountsOut[i] = (bal * sharesIn) / supply;
        }
    }

    function _accrueManagementFee() internal returns (uint256 feeShares) {
        uint256 elapsed = block.timestamp - lastFeeAccrual;
        if (elapsed == 0) return 0;
        lastFeeAccrual = block.timestamp;

        if (managementFeeBps == 0) return 0;

        uint256 supply = totalSupply();
        if (supply == 0) return 0;

        feeShares = (supply * managementFeeBps * elapsed) / (BPS * YEAR);
        if (feeShares > 0) {
            _mint(feeRecipient, feeShares);
            emit ManagementFeeAccrued(feeShares);
        }
    }

    function _mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + d - 1) / d;
    }
}
