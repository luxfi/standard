// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.31;

/**
 * @title IStore
 * @notice Interface that allows financial contracts to pay oracle fees for their use of the system.
 */
interface IStore {
    /**
     * @notice Pays Oracle fees in ETH to the store.
     * @dev To be used by contracts whose margin currency is ETH.
     */
    function payOracleFees() external payable;

    /**
     * @notice Pays oracle fees in the margin currency, erc20Address, to the store.
     * @dev To be used if the margin currency is an ERC20 token rather than ETH.
     * @param erc20Address address of the ERC20 token used to pay the fee.
     * @param amount number of tokens to transfer (raw value, 18 decimals). An approval for at least this amount must exist.
     */
    function payOracleFeesErc20(address erc20Address, uint256 amount) external;

    /**
     * @notice Computes the regular oracle fees that a contract should pay for a period.
     * @param startTime defines the beginning time from which the fee is paid.
     * @param endTime end time until which the fee is paid.
     * @param pfc "profit from corruption", the maximum amount of margin currency that a
     * token sponsor could extract from the contract through corrupting the price feed (raw value, 18 decimals).
     * @return regularFee amount owed for the duration from start to end time for the given pfc (raw value, 18 decimals).
     * @return latePenalty penalty for paying the fee after the deadline (raw value, 18 decimals).
     */
    function computeRegularFee(
        uint256 startTime,
        uint256 endTime,
        uint256 pfc
    ) external view returns (uint256 regularFee, uint256 latePenalty);

    /**
     * @notice Computes the final oracle fees that a contract should pay at settlement.
     * @param currency token used to pay the final fee.
     * @return finalFee amount due (raw value, 18 decimals).
     */
    function computeFinalFee(address currency) external view returns (uint256);
}
