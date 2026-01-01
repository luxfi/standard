// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IOracleSource} from "../interfaces/IOracleSource.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Pyth price feed interface
interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory);
    function getPriceUnsafe(bytes32 id) external view returns (Price memory);
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
}

/// @title PythAdapter
/// @notice Oracle source adapter for Pyth Network price feeds
/// @dev Implements IOracleSource, returns prices normalized to 18 decimals USD
contract PythAdapter is IOracleSource, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Pyth oracle contract
    IPyth public immutable pyth;

    /// @notice Mapping of asset address to Pyth price feed ID
    mapping(address => bytes32) public priceIds;

    /// @notice Maximum staleness in seconds
    uint256 public maxStaleness;

    /// @notice Last successful heartbeat (global)
    uint256 public lastGlobalHeartbeat;

    error FeedNotConfigured(address asset);
    error InvalidPrice();
    error StalePrice();

    event FeedConfigured(address indexed asset, bytes32 indexed priceId);
    event MaxStalenessUpdated(uint256 newMaxStaleness);

    constructor(address _pyth, uint256 _maxStaleness) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        pyth = IPyth(_pyth);
        maxStaleness = _maxStaleness;
        lastGlobalHeartbeat = block.timestamp;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Configure a Pyth feed for an asset
    /// @param asset The asset address
    /// @param priceId The Pyth price feed ID
    function setFeed(address asset, bytes32 priceId) external onlyRole(ADMIN_ROLE) {
        priceIds[asset] = priceId;
        emit FeedConfigured(asset, priceId);
    }

    /// @notice Batch configure feeds
    function setFeeds(address[] calldata assets, bytes32[] calldata _priceIds) external onlyRole(ADMIN_ROLE) {
        require(assets.length == _priceIds.length, "Length mismatch");
        for (uint256 i = 0; i < assets.length; i++) {
            priceIds[assets[i]] = _priceIds[i];
            emit FeedConfigured(assets[i], _priceIds[i]);
        }
    }

    /// @notice Update max staleness
    function setMaxStaleness(uint256 _maxStaleness) external onlyRole(ADMIN_ROLE) {
        maxStaleness = _maxStaleness;
        emit MaxStalenessUpdated(_maxStaleness);
    }

    /// @notice Update Pyth price feeds (call before reading for fresh prices)
    /// @param updateData Price update data from Pyth API
    function updatePrices(bytes[] calldata updateData) external payable {
        uint256 fee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeeds{value: fee}(updateData);
        lastGlobalHeartbeat = block.timestamp;

        // Refund excess
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }

    // =========================================================================
    // IOracleSource Implementation
    // =========================================================================

    /// @inheritdoc IOracleSource
    function getPrice(address asset) external view override returns (uint256 price, uint256 timestamp) {
        bytes32 priceId = priceIds[asset];
        if (priceId == bytes32(0)) revert FeedNotConfigured(asset);

        IPyth.Price memory pythPrice = pyth.getPriceNoOlderThan(priceId, maxStaleness);

        if (pythPrice.price <= 0) revert InvalidPrice();

        price = _normalizePrice(pythPrice.price, pythPrice.expo);
        timestamp = pythPrice.publishTime;
    }

    /// @inheritdoc IOracleSource
    function isSupported(address asset) external view override returns (bool) {
        return priceIds[asset] != bytes32(0);
    }

    /// @inheritdoc IOracleSource
    function source() external pure override returns (string memory) {
        return "pyth";
    }

    /// @inheritdoc IOracleSource
    function health() external view override returns (bool healthy, uint256 lastHb) {
        healthy = true;
        lastHb = lastGlobalHeartbeat;
    }

    // =========================================================================
    // Additional Functions
    // =========================================================================

    /// @notice Get price with custom max age
    function getPriceIfFresh(address asset, uint256 maxAge) external view returns (uint256 price) {
        bytes32 priceId = priceIds[asset];
        if (priceId == bytes32(0)) revert FeedNotConfigured(asset);

        IPyth.Price memory pythPrice = pyth.getPriceNoOlderThan(priceId, maxAge);

        if (pythPrice.price <= 0) revert InvalidPrice();

        price = _normalizePrice(pythPrice.price, pythPrice.expo);
    }

    /// @notice Get price with confidence interval
    /// @param asset The asset address
    /// @return price The price in 18 decimals
    /// @return confidence The confidence interval in 18 decimals
    /// @return timestamp The publish time
    function getPriceWithConfidence(address asset)
        external view returns (uint256 price, uint256 confidence, uint256 timestamp)
    {
        bytes32 priceId = priceIds[asset];
        if (priceId == bytes32(0)) revert FeedNotConfigured(asset);

        IPyth.Price memory pythPrice = pyth.getPriceNoOlderThan(priceId, maxStaleness);

        price = _normalizePrice(pythPrice.price, pythPrice.expo);
        confidence = _normalizePrice(int64(uint64(pythPrice.conf)), pythPrice.expo);
        timestamp = pythPrice.publishTime;
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /// @notice Normalize Pyth price to 18 decimals
    function _normalizePrice(int64 rawPrice, int32 expo) internal pure returns (uint256) {
        if (rawPrice <= 0) return 0;

        // Target: 18 decimals
        int32 targetExpo = -18;

        if (expo > targetExpo) {
            // Need to divide
            uint32 diff = uint32(expo - targetExpo);
            return uint256(int256(rawPrice)) / (10 ** diff);
        } else if (expo < targetExpo) {
            // Need to multiply
            uint32 diff = uint32(targetExpo - expo);
            return uint256(int256(rawPrice)) * (10 ** diff);
        }
        return uint256(int256(rawPrice));
    }
}
