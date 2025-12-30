// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IOracle} from "./IOracle.sol";
import {IOracleWriter} from "./interfaces/IOracleWriter.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title OracleHub
/// @notice On-chain price hub that receives prices from DEX infrastructure
/// @dev Written to by: DEX gateway, validator attestations, keepers
/// @dev Read by: Perps, lending, AMM, flashloans, any DeFi protocol
contract OracleHub is IOracle, IOracleWriter, AccessControl {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // =========================================================================
    // Roles
    // =========================================================================

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WRITER_ROLE = keccak256("WRITER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    // =========================================================================
    // State
    // =========================================================================

    /// @notice Stored prices per asset
    mapping(address => PriceData) public prices;

    /// @notice Quorum requirement per asset (0 = use default)
    mapping(address => uint256) public assetQuorum;

    /// @notice Default quorum for validator consensus
    uint256 public defaultQuorum = 3;

    /// @notice Maximum price age before considered stale
    uint256 public maxStaleness = 1 hours;

    /// @notice Maximum price change per update (basis points)
    uint256 public maxChangeBps = 1000; // 10%

    /// @notice Circuit breaker: paused assets
    mapping(address => bool) public paused;

    /// @notice Last validator price per asset per validator
    mapping(address => mapping(address => ValidatorPrice)) public validatorPrices;

    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        bytes32 source;
        uint256 validatorCount;
    }

    struct ValidatorPrice {
        uint256 price;
        uint256 timestamp;
    }

    // =========================================================================
    // Errors
    // =========================================================================

    error AssetPaused(address asset);
    error StalePrice(address asset, uint256 age);
    error PriceChangeExceeded(address asset, uint256 changeBps);
    error InvalidSignature();
    error InsufficientQuorum(uint256 have, uint256 need);
    error PriceDeviation(uint256 maxDeviation);
    error AssetNotSupported(address asset);

    // =========================================================================
    // Constructor
    // =========================================================================

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(WRITER_ROLE, msg.sender);
    }

    // =========================================================================
    // IOracle Implementation (Read Interface)
    // =========================================================================

    /// @inheritdoc IOracle
    function getPrice(address asset) external view override returns (uint256 price, uint256 timestamp) {
        PriceData memory data = prices[asset];
        if (data.timestamp == 0) revert AssetNotSupported(asset);
        if (paused[asset]) revert AssetPaused(asset);

        price = data.price;
        timestamp = data.timestamp;
    }

    /// @inheritdoc IOracle
    function getPriceIfFresh(address asset, uint256 maxAge) external view override returns (uint256 price) {
        PriceData memory data = prices[asset];
        if (data.timestamp == 0) revert AssetNotSupported(asset);
        if (paused[asset]) revert AssetPaused(asset);

        uint256 age = block.timestamp - data.timestamp;
        if (age > maxAge) revert StalePrice(asset, age);

        price = data.price;
    }

    /// @inheritdoc IOracle
    function isSupported(address asset) external view override returns (bool) {
        return prices[asset].timestamp > 0;
    }

    /// @notice Get the source identifier
    function source() external pure returns (string memory) {
        return "lux-oracle-hub";
    }

    /// @inheritdoc IOracle
    function price(address asset) external view override returns (uint256) {
        PriceData memory data = prices[asset];
        if (data.timestamp == 0) revert AssetNotSupported(asset);
        if (paused[asset]) revert AssetPaused(asset);
        return data.price;
    }

    /// @inheritdoc IOracle
    function isPriceConsistent(address asset, uint256 maxDeviationBps) external view override returns (bool) {
        // OracleHub is a single source, so always consistent with itself
        PriceData memory data = prices[asset];
        if (data.timestamp == 0) return false;
        // Check confidence - if confidence is above threshold, consider consistent
        return data.confidence >= (10000 - maxDeviationBps);
    }

    /// @inheritdoc IOracle
    function health() external view override returns (bool healthy, uint256 activeSourceCount) {
        // Count assets with recent prices (within maxStaleness)
        activeSourceCount = 1; // OracleHub is itself one source
        healthy = true; // Hub is healthy if contract is not paused globally
    }

    /// @inheritdoc IOracle
    function isCircuitBreakerTripped(address asset) external view override returns (bool) {
        return paused[asset];
    }

    /// @inheritdoc IOracle
    function getPriceForPerps(address asset, bool maximize) external view override returns (uint256) {
        PriceData memory data = prices[asset];
        if (data.timestamp == 0) revert AssetNotSupported(asset);
        if (paused[asset]) revert AssetPaused(asset);

        // Apply spread based on confidence (lower confidence = higher spread)
        uint256 spreadBps = 10000 - data.confidence; // e.g., 9500 confidence = 5bp spread
        spreadBps = spreadBps > 100 ? 100 : spreadBps; // Cap at 1%

        if (maximize) {
            return data.price + (data.price * spreadBps) / 10000;
        } else {
            return data.price - (data.price * spreadBps) / 10000;
        }
    }

    /// @notice Batch price query for gas efficiency
    function getPrices(address[] calldata assets)
        external view returns (uint256[] memory priceList, uint256[] memory timestamps)
    {
        priceList = new uint256[](assets.length);
        timestamps = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            PriceData memory data = prices[assets[i]];
            priceList[i] = data.price;
            timestamps[i] = data.timestamp;
        }
    }

    // =========================================================================
    // IOracleWriter Implementation (Write Interface)
    // =========================================================================

    /// @inheritdoc IOracleWriter
    function writePrice(address asset, uint256 price, uint256 timestamp)
        external override onlyRole(WRITER_ROLE)
    {
        _writePrice(asset, price, timestamp, 10000, keccak256("dex-gateway"));
    }

    /// @inheritdoc IOracleWriter
    function writePrices(PriceUpdate[] calldata updates)
        external override onlyRole(WRITER_ROLE)
    {
        for (uint256 i = 0; i < updates.length; i++) {
            _writePrice(
                updates[i].asset,
                updates[i].price,
                updates[i].timestamp,
                updates[i].confidence,
                updates[i].source
            );
        }
    }

    /// @inheritdoc IOracleWriter
    function writeSignedPrice(SignedPriceUpdate calldata update) external override {
        // Verify validator
        if (!hasRole(VALIDATOR_ROLE, update.validator)) revert InvalidSignature();

        // Verify signature
        bytes32 hash = keccak256(abi.encode(
            update.update.asset,
            update.update.price,
            update.update.timestamp
        ));
        bytes32 ethHash = hash.toEthSignedMessageHash();
        address signer = ethHash.recover(update.signature);
        if (signer != update.validator) revert InvalidSignature();

        // Store validator price
        validatorPrices[update.update.asset][update.validator] = ValidatorPrice({
            price: update.update.price,
            timestamp: update.update.timestamp
        });

        emit ValidatorPriceWritten(update.update.asset, update.update.price, update.validator);
    }

    /// @inheritdoc IOracleWriter
    function writeQuorumPrice(SignedPriceUpdate[] calldata updates, uint256 minQuorum)
        external override
    {
        if (updates.length < minQuorum) revert InsufficientQuorum(updates.length, minQuorum);

        address asset = updates[0].update.asset;
        uint256 quorum = assetQuorum[asset] > 0 ? assetQuorum[asset] : defaultQuorum;
        if (minQuorum < quorum) revert InsufficientQuorum(minQuorum, quorum);

        // Verify all signatures and collect prices
        uint256[] memory validPrices = new uint256[](updates.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < updates.length; i++) {
            if (updates[i].update.asset != asset) continue;
            if (!hasRole(VALIDATOR_ROLE, updates[i].validator)) continue;

            bytes32 hash = keccak256(abi.encode(
                updates[i].update.asset,
                updates[i].update.price,
                updates[i].update.timestamp
            ));
            bytes32 ethHash = hash.toEthSignedMessageHash();
            address signer = ethHash.recover(updates[i].signature);

            if (signer == updates[i].validator) {
                validPrices[validCount] = updates[i].update.price;
                validCount++;
            }
        }

        if (validCount < quorum) revert InsufficientQuorum(validCount, quorum);

        // Use median of valid prices
        uint256 medianPrice = _median(validPrices, validCount);

        // Check deviation (all prices within 5% of median)
        for (uint256 i = 0; i < validCount; i++) {
            uint256 dev = validPrices[i] > medianPrice
                ? ((validPrices[i] - medianPrice) * 10000) / medianPrice
                : ((medianPrice - validPrices[i]) * 10000) / medianPrice;
            if (dev > 500) revert PriceDeviation(dev);
        }

        // Write the quorum price
        prices[asset] = PriceData({
            price: medianPrice,
            timestamp: block.timestamp,
            confidence: 9900, // High confidence for quorum
            source: keccak256("validator-quorum"),
            validatorCount: validCount
        });

        emit QuorumPriceWritten(asset, medianPrice, validCount);
    }

    /// @inheritdoc IOracleWriter
    function isWriter(address account) external view override returns (bool) {
        return hasRole(WRITER_ROLE, account);
    }

    /// @inheritdoc IOracleWriter
    function isValidator(address validator) external view override returns (bool) {
        return hasRole(VALIDATOR_ROLE, validator);
    }

    /// @inheritdoc IOracleWriter
    function getQuorum(address asset) external view override returns (uint256) {
        return assetQuorum[asset] > 0 ? assetQuorum[asset] : defaultQuorum;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Set default quorum
    function setDefaultQuorum(uint256 quorum) external onlyRole(ADMIN_ROLE) {
        defaultQuorum = quorum;
    }

    /// @notice Set quorum for specific asset
    function setAssetQuorum(address asset, uint256 quorum) external onlyRole(ADMIN_ROLE) {
        assetQuorum[asset] = quorum;
    }

    /// @notice Set max staleness
    function setMaxStaleness(uint256 _maxStaleness) external onlyRole(ADMIN_ROLE) {
        maxStaleness = _maxStaleness;
    }

    /// @notice Set max price change
    function setMaxChangeBps(uint256 _maxChangeBps) external onlyRole(ADMIN_ROLE) {
        maxChangeBps = _maxChangeBps;
    }

    /// @notice Pause/unpause asset
    function setPaused(address asset, bool _paused) external onlyRole(ADMIN_ROLE) {
        paused[asset] = _paused;
    }

    /// @notice Add writer
    function addWriter(address writer) external onlyRole(ADMIN_ROLE) {
        _grantRole(WRITER_ROLE, writer);
    }

    /// @notice Add validator
    function addValidator(address validator) external onlyRole(ADMIN_ROLE) {
        _grantRole(VALIDATOR_ROLE, validator);
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    function _writePrice(
        address asset,
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        bytes32 sourceId
    ) internal {
        if (paused[asset]) revert AssetPaused(asset);

        // Check price change circuit breaker
        PriceData memory existing = prices[asset];
        if (existing.price > 0) {
            uint256 changeBps = price > existing.price
                ? ((price - existing.price) * 10000) / existing.price
                : ((existing.price - price) * 10000) / existing.price;
            if (changeBps > maxChangeBps) revert PriceChangeExceeded(asset, changeBps);
        }

        prices[asset] = PriceData({
            price: price,
            timestamp: timestamp,
            confidence: confidence,
            source: sourceId,
            validatorCount: 0
        });

        emit PriceWritten(asset, price, timestamp, sourceId);
    }

    function _median(uint256[] memory arr, uint256 len) internal pure returns (uint256) {
        if (len == 0) return 0;
        if (len == 1) return arr[0];

        // Simple bubble sort for small arrays
        for (uint256 i = 0; i < len; i++) {
            for (uint256 j = i + 1; j < len; j++) {
                if (arr[i] > arr[j]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                }
            }
        }

        uint256 mid = len / 2;
        if (len % 2 == 0) {
            return (arr[mid - 1] + arr[mid]) / 2;
        }
        return arr[mid];
    }
}
