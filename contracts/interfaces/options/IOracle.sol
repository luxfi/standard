// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IOracle
 * @author Lux Industries
 * @notice Interface for price oracles used by the options protocol
 */
interface IOracle {
    /**
     * @notice Get the current price of an asset
     * @param asset The asset address
     * @return price The price in quote token decimals
     * @return timestamp The timestamp of the price
     */
    function getPrice(address asset) external view returns (uint256 price, uint256 timestamp);
}
