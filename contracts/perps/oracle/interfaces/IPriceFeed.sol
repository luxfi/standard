// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

interface IPriceFeed {
    function description() external view returns (string memory);
    function aggregator() external view returns (address);
    function latestAnswer() external view returns (int256);
    function latestRound() external view returns (uint80);
    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80);
    /// @notice Get the latest round data with staleness info (Chainlink AggregatorV3Interface compatible)
    /// @return roundId The round ID
    /// @return answer The price answer
    /// @return startedAt When the round started
    /// @return updatedAt When the round was last updated
    /// @return answeredInRound The round in which the answer was computed
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
