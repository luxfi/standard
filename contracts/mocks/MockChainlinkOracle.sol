// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOracle} from "../markets/interfaces/IOracle.sol";

/// @title MockChainlinkOracle
/// @notice Mock oracle for local testing and Anvil deployments
/// @dev Returns configurable prices for testing market operations
contract MockChainlinkOracle is IOracle {
    /// @notice Current price (scaled to 1e36)
    uint256 public currentPrice;

    /// @notice Price decimals
    uint8 public immutable priceDecimals;

    /// @notice Owner who can update price
    address public owner;

    /// @notice Price history for testing
    uint256[] public priceHistory;

    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    error Unauthorized();

    constructor(uint256 _initialPrice, uint8 _decimals) {
        currentPrice = _initialPrice;
        priceDecimals = _decimals;
        owner = msg.sender;
        priceHistory.push(_initialPrice);
    }

    /// @notice Get current price (IOracle interface)
    function price() external view override returns (uint256) {
        return currentPrice;
    }

    /// @notice Update the mock price
    function setPrice(uint256 _newPrice) external {
        if (msg.sender != owner) revert Unauthorized();
        uint256 oldPrice = currentPrice;
        currentPrice = _newPrice;
        priceHistory.push(_newPrice);
        emit PriceUpdated(oldPrice, _newPrice);
    }

    /// @notice Simulate price movement by percentage
    /// @param basisPoints Positive for increase, negative for decrease (10000 = 100%)
    function movePrice(int256 basisPoints) external {
        if (msg.sender != owner) revert Unauthorized();
        uint256 oldPrice = currentPrice;
        if (basisPoints >= 0) {
            currentPrice = currentPrice * (10000 + uint256(basisPoints)) / 10000;
        } else {
            currentPrice = currentPrice * (10000 - uint256(-basisPoints)) / 10000;
        }
        priceHistory.push(currentPrice);
        emit PriceUpdated(oldPrice, currentPrice);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        owner = newOwner;
    }

    /// @notice Get price history length
    function priceHistoryLength() external view returns (uint256) {
        return priceHistory.length;
    }
}

/// @title MockChainlinkAggregator
/// @notice Mock Chainlink AggregatorV3Interface for testing
contract MockChainlinkAggregator {
    int256 public latestAnswer;
    uint8 public immutable decimals_;
    uint256 public latestTimestamp;
    uint80 public latestRound;
    string public description;

    address public owner;

    constructor(int256 _initialPrice, uint8 _decimals, string memory _description) {
        latestAnswer = _initialPrice;
        decimals_ = _decimals;
        latestTimestamp = block.timestamp;
        latestRound = 1;
        description = _description;
        owner = msg.sender;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (latestRound, latestAnswer, latestTimestamp, latestTimestamp, latestRound);
    }

    function setPrice(int256 _price) external {
        require(msg.sender == owner, "Not owner");
        latestAnswer = _price;
        latestTimestamp = block.timestamp;
        latestRound++;
    }

    function getRoundData(uint80) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (latestRound, latestAnswer, latestTimestamp, latestTimestamp, latestRound);
    }
}

/// @title OracleFactory
/// @notice Factory for deploying mock oracles with common price feeds
contract MockOracleFactory {
    /// @notice Deploy a set of common price oracles
    /// @return ethUsd ETH/USD oracle
    /// @return btcUsd BTC/USD oracle
    /// @return luxUsd LUX/USD oracle
    /// @return usdcUsd USDC/USD oracle (should be ~1e8)
    function deployCommonOracles() external returns (
        address ethUsd,
        address btcUsd,
        address luxUsd,
        address usdcUsd
    ) {
        // Deploy with realistic prices (8 decimals like Chainlink)
        ethUsd = address(new MockChainlinkAggregator(2000e8, 8, "ETH / USD"));
        btcUsd = address(new MockChainlinkAggregator(40000e8, 8, "BTC / USD"));
        luxUsd = address(new MockChainlinkAggregator(10e8, 8, "LUX / USD"));   // $10
        usdcUsd = address(new MockChainlinkAggregator(1e8, 8, "USDC / USD"));

        return (ethUsd, btcUsd, luxUsd, usdcUsd);
    }
}
