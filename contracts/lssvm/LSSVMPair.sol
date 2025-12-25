// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ICurve.sol";

/// @title LSSVMPair - NFT AMM Pair
/// @notice Single-sided liquidity pool for NFT trading
/// @dev Based on Sudoswap LSSVM whitepaper
///      Supports ETH and ERC20 quote tokens
contract LSSVMPair is IERC721Receiver, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Pool types
    enum PoolType {
        TOKEN,  // Pool only trades token for NFT (buy-only)
        NFT,    // Pool only trades NFT for token (sell-only)
        TRADE   // Pool does both (two-sided)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event SwapNFTInPool(uint256[] nftIds, uint256 inputAmount);
    event SwapNFTOutPool(uint256[] nftIds, uint256 outputAmount);
    event SpotPriceUpdate(uint128 newSpotPrice);
    event DeltaUpdate(uint128 newDelta);
    event FeeUpdate(uint96 newFee);
    event TokenDeposit(uint256 amount);
    event TokenWithdrawal(uint256 amount);
    event NFTDeposit(uint256[] nftIds);
    event NFTWithdrawal(uint256[] nftIds);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error Unauthorized();
    error InvalidPoolType();
    error InvalidSpotPrice();
    error InvalidDelta();
    error InvalidFee();
    error InsufficientLiquidity();
    error SlippageExceeded();

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    address public factory;
    address public owner;
    IERC721 public nft;
    ICurve public bondingCurve;
    PoolType public poolType;

    // Quote token (address(0) = native LUX)
    address public token;

    // Pricing parameters
    uint128 public spotPrice;
    uint128 public delta;

    // Fee (in basis points, e.g., 100 = 1%)
    uint96 public fee;

    // Asset fee recipient (for TRADE pools)
    address public assetRecipient;

    // NFT IDs held by this pool
    uint256[] private _heldNftIds;
    mapping(uint256 => uint256) private _nftIdToIndex;

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR & INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address _owner,
        address _nft,
        address _bondingCurve,
        address _token,
        PoolType _poolType,
        uint128 _spotPrice,
        uint128 _delta,
        uint96 _fee,
        address _assetRecipient
    ) external onlyFactory {
        owner = _owner;
        nft = IERC721(_nft);
        bondingCurve = ICurve(_bondingCurve);
        token = _token;
        poolType = _poolType;
        spotPrice = _spotPrice;
        delta = _delta;
        fee = _fee;
        assetRecipient = _assetRecipient == address(0) ? _owner : _assetRecipient;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRADING
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Buy NFTs from the pool
    /// @param nftIds IDs of NFTs to buy
    /// @param maxInput Maximum amount willing to pay
    /// @param recipient Address to receive NFTs
    /// @return inputAmount Amount paid for NFTs
    function swapTokenForNFTs(
        uint256[] calldata nftIds,
        uint256 maxInput,
        address recipient
    ) external payable nonReentrant returns (uint256 inputAmount) {
        if (poolType == PoolType.NFT) revert InvalidPoolType();
        if (nftIds.length == 0) return 0;

        // Get buy price
        (uint128 newSpotPrice, , uint256 totalCost, uint256 tradeFee, uint256 protocolFee) =
            bondingCurve.getBuyInfo(spotPrice, delta, nftIds.length, fee, _getProtocolFee());

        inputAmount = totalCost;

        if (inputAmount > maxInput) revert SlippageExceeded();

        // Update spot price
        spotPrice = newSpotPrice;
        emit SpotPriceUpdate(newSpotPrice);

        // Transfer payment
        _pullTokens(msg.sender, inputAmount);

        // Transfer protocol fee
        if (protocolFee > 0) {
            _sendTokens(_getProtocolFeeRecipient(), protocolFee);
        }

        // Transfer trade fee to asset recipient (for TRADE pools)
        if (tradeFee > 0 && poolType == PoolType.TRADE) {
            _sendTokens(assetRecipient, tradeFee);
        }

        // Transfer NFTs to recipient
        for (uint256 i = 0; i < nftIds.length; i++) {
            _removeNftFromPool(nftIds[i]);
            nft.safeTransferFrom(address(this), recipient, nftIds[i]);
        }

        emit SwapNFTOutPool(nftIds, inputAmount);
    }

    /// @notice Sell NFTs to the pool
    /// @param nftIds IDs of NFTs to sell
    /// @param minOutput Minimum amount expected to receive
    /// @param recipient Address to receive tokens
    /// @return outputAmount Amount received for NFTs
    function swapNFTsForToken(
        uint256[] calldata nftIds,
        uint256 minOutput,
        address recipient
    ) external nonReentrant returns (uint256 outputAmount) {
        if (poolType == PoolType.TOKEN) revert InvalidPoolType();
        if (nftIds.length == 0) return 0;

        // Get sell price
        (uint128 newSpotPrice, , uint256 totalOutput, uint256 tradeFee, uint256 protocolFee) =
            bondingCurve.getSellInfo(spotPrice, delta, nftIds.length, fee, _getProtocolFee());

        outputAmount = totalOutput;

        if (outputAmount < minOutput) revert SlippageExceeded();

        // Check pool has enough liquidity
        if (_getTokenBalance() < outputAmount + protocolFee) revert InsufficientLiquidity();

        // Update spot price
        spotPrice = newSpotPrice;
        emit SpotPriceUpdate(newSpotPrice);

        // Transfer NFTs from seller (safeTransferFrom triggers onERC721Received for tracking)
        for (uint256 i = 0; i < nftIds.length; i++) {
            nft.safeTransferFrom(msg.sender, address(this), nftIds[i]);
        }

        // Transfer payment to recipient
        _sendTokens(recipient, outputAmount);

        // Transfer protocol fee
        if (protocolFee > 0) {
            _sendTokens(_getProtocolFeeRecipient(), protocolFee);
        }

        // Trade fee stays in pool for TOKEN pools, goes to assetRecipient for TRADE pools
        if (tradeFee > 0 && poolType == PoolType.TRADE) {
            _sendTokens(assetRecipient, tradeFee);
        }

        emit SwapNFTInPool(nftIds, outputAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LIQUIDITY
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deposit tokens to the pool
    function depositTokens(uint256 amount) external payable onlyOwner {
        if (token == address(0)) {
            require(msg.value == amount, "LSSVMPair: INVALID_VALUE");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit TokenDeposit(amount);
    }

    /// @notice Withdraw tokens from the pool
    function withdrawTokens(uint256 amount) external onlyOwner {
        _sendTokens(msg.sender, amount);
        emit TokenWithdrawal(amount);
    }

    /// @notice Deposit NFTs to the pool
    /// @dev Uses safeTransferFrom which triggers onERC721Received for automatic tracking
    function depositNFTs(uint256[] calldata nftIds) external onlyOwner {
        for (uint256 i = 0; i < nftIds.length; i++) {
            // safeTransferFrom triggers onERC721Received which calls _addNftToPool
            nft.safeTransferFrom(msg.sender, address(this), nftIds[i]);
        }
        emit NFTDeposit(nftIds);
    }

    /// @notice Withdraw NFTs from the pool
    function withdrawNFTs(uint256[] calldata nftIds) external onlyOwner {
        for (uint256 i = 0; i < nftIds.length; i++) {
            _removeNftFromPool(nftIds[i]);
            nft.safeTransferFrom(address(this), msg.sender, nftIds[i]);
        }
        emit NFTWithdrawal(nftIds);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    function setSpotPrice(uint128 _spotPrice) external onlyOwner {
        if (!bondingCurve.validateSpotPrice(_spotPrice)) revert InvalidSpotPrice();
        spotPrice = _spotPrice;
        emit SpotPriceUpdate(_spotPrice);
    }

    function setDelta(uint128 _delta) external onlyOwner {
        if (!bondingCurve.validateDelta(_delta)) revert InvalidDelta();
        delta = _delta;
        emit DeltaUpdate(_delta);
    }

    function setFee(uint96 _fee) external onlyOwner {
        if (_fee > 9000) revert InvalidFee(); // Max 90% fee
        fee = _fee;
        emit FeeUpdate(_fee);
    }

    function setAssetRecipient(address _assetRecipient) external onlyOwner {
        assetRecipient = _assetRecipient;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function getAllHeldIds() external view returns (uint256[] memory) {
        return _heldNftIds;
    }

    function getTokenBalance() external view returns (uint256) {
        return _getTokenBalance();
    }

    function getBuyNFTQuote(uint256 numItems)
        external
        view
        returns (
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 inputAmount,
            uint256 tradeFee,
            uint256 protocolFee
        )
    {
        return bondingCurve.getBuyInfo(spotPrice, delta, numItems, fee, _getProtocolFee());
    }

    function getSellNFTQuote(uint256 numItems)
        external
        view
        returns (
            uint128 newSpotPrice,
            uint128 newDelta,
            uint256 outputAmount,
            uint256 tradeFee,
            uint256 protocolFee
        )
    {
        return bondingCurve.getSellInfo(spotPrice, delta, numItems, fee, _getProtocolFee());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _getTokenBalance() internal view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }

    function _pullTokens(address from, uint256 amount) internal {
        if (token == address(0)) {
            require(msg.value >= amount, "LSSVMPair: INSUFFICIENT_VALUE");
            // Refund excess
            if (msg.value > amount) {
                (bool success,) = from.call{value: msg.value - amount}("");
                require(success, "LSSVMPair: REFUND_FAILED");
            }
        } else {
            IERC20(token).safeTransferFrom(from, address(this), amount);
        }
    }

    function _sendTokens(address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool success,) = to.call{value: amount}("");
            require(success, "LSSVMPair: TRANSFER_FAILED");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _addNftToPool(uint256 nftId) internal {
        _nftIdToIndex[nftId] = _heldNftIds.length;
        _heldNftIds.push(nftId);
    }

    function _removeNftFromPool(uint256 nftId) internal {
        uint256 index = _nftIdToIndex[nftId];
        uint256 lastIndex = _heldNftIds.length - 1;

        if (index != lastIndex) {
            uint256 lastId = _heldNftIds[lastIndex];
            _heldNftIds[index] = lastId;
            _nftIdToIndex[lastId] = index;
        }

        _heldNftIds.pop();
        delete _nftIdToIndex[nftId];
    }

    function _getProtocolFee() internal view returns (uint256) {
        // Get protocol fee from factory
        return ILSSVMPairFactory(factory).protocolFeeMultiplier();
    }

    function _getProtocolFeeRecipient() internal view returns (address) {
        return ILSSVMPairFactory(factory).protocolFeeRecipient();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC721 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        // Only track NFTs from our designated collection
        if (msg.sender == address(nft)) {
            _addNftToPool(tokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    // Allow receiving LUX
    receive() external payable {}
}

interface ILSSVMPairFactory {
    function protocolFeeMultiplier() external view returns (uint256);
    function protocolFeeRecipient() external view returns (address);
}
