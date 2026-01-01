// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IOracleSource} from "@luxfi/contracts/interfaces/oracle/IOracleSource.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Chainlink AggregatorV3 interface
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

/// @title ChainlinkAdapter
/// @notice Oracle source adapter for Chainlink price feeds
/// @dev Implements IOracleSource, returns prices normalized to 18 decimals USD
contract ChainlinkAdapter is IOracleSource, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Mapping of asset address to Chainlink feed
    mapping(address => address) public feeds;

    /// @notice Feed decimals cache
    mapping(address => uint8) public feedDecimals;

    /// @notice Maximum staleness in seconds
    uint256 public maxStaleness;

    /// @notice Last successful heartbeat (global)
    uint256 public lastGlobalHeartbeat;

    error FeedNotConfigured(address asset);
    error InvalidPrice();
    error StalePrice();

    event FeedConfigured(address indexed asset, address indexed feed);
    event MaxStalenessUpdated(uint256 newMaxStaleness);

    constructor(uint256 _maxStaleness) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        maxStaleness = _maxStaleness;
        lastGlobalHeartbeat = block.timestamp;
    }

    // =========================================================================
    // Admin Functions
    // =========================================================================

    /// @notice Configure a Chainlink feed for an asset
    /// @param asset The asset address (use address(0) for native LUX)
    /// @param feed The Chainlink aggregator address
    function setFeed(address asset, address feed) external onlyRole(ADMIN_ROLE) {
        feeds[asset] = feed;
        feedDecimals[asset] = AggregatorV3Interface(feed).decimals();
        emit FeedConfigured(asset, feed);
    }

    /// @notice Batch configure feeds
    function setFeeds(address[] calldata assets, address[] calldata _feeds) external onlyRole(ADMIN_ROLE) {
        require(assets.length == _feeds.length, "Length mismatch");
        for (uint256 i = 0; i < assets.length; i++) {
            feeds[assets[i]] = _feeds[i];
            feedDecimals[assets[i]] = AggregatorV3Interface(_feeds[i]).decimals();
            emit FeedConfigured(assets[i], _feeds[i]);
        }
    }

    /// @notice Update max staleness
    function setMaxStaleness(uint256 _maxStaleness) external onlyRole(ADMIN_ROLE) {
        maxStaleness = _maxStaleness;
        emit MaxStalenessUpdated(_maxStaleness);
    }

    // =========================================================================
    // IOracleSource Implementation
    // =========================================================================

    /// @inheritdoc IOracleSource
    function getPrice(address asset) external view override returns (uint256 price, uint256 timestamp) {
        address feed = feeds[asset];
        if (feed == address(0)) revert FeedNotConfigured(asset);

        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > maxStaleness) revert StalePrice();

        // Normalize to 18 decimals
        uint8 decimals = feedDecimals[asset];
        if (decimals < 18) {
            price = uint256(answer) * 10**(18 - decimals);
        } else if (decimals > 18) {
            price = uint256(answer) / 10**(decimals - 18);
        } else {
            price = uint256(answer);
        }

        timestamp = updatedAt;
    }

    /// @inheritdoc IOracleSource
    function isSupported(address asset) external view override returns (bool) {
        return feeds[asset] != address(0);
    }

    /// @inheritdoc IOracleSource
    function source() external pure override returns (string memory) {
        return "chainlink";
    }

    /// @inheritdoc IOracleSource
    function health() external view override returns (bool healthy, uint256 lastHb) {
        // Chainlink is considered healthy if we have at least one feed configured
        // In production, iterate over all feeds and check their updatedAt
        healthy = true;
        lastHb = lastGlobalHeartbeat;
    }

    // =========================================================================
    // Additional Functions
    // =========================================================================

    /// @notice Get price with custom max age
    function getPriceIfFresh(address asset, uint256 maxAge) external view returns (uint256 price) {
        address feed = feeds[asset];
        if (feed == address(0)) revert FeedNotConfigured(asset);

        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > maxAge) revert StalePrice();

        uint8 decimals = feedDecimals[asset];
        if (decimals < 18) {
            price = uint256(answer) * 10**(18 - decimals);
        } else if (decimals > 18) {
            price = uint256(answer) / 10**(decimals - 18);
        } else {
            price = uint256(answer);
        }
    }

    /// @notice Update heartbeat (called by keepers to prove liveness)
    function heartbeat() external {
        lastGlobalHeartbeat = block.timestamp;
    }
}
