// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    IVotingTokenLockupPlans
} from "../interfaces/hedgey/IVotingTokenLockupPlans.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockVotingTokenLockupPlans
 * @notice Mock implementation of IVotingTokenLockupPlans for testing
 */
contract MockVotingTokenLockupPlans is IVotingTokenLockupPlans {
    struct CreatePlanCall {
        address recipient;
        address token;
        uint256 amount;
        uint256 start;
        uint256 cliff;
        uint256 rate;
        uint256 period;
    }

    CreatePlanCall public lastCreatePlanCall;

    function createPlan(
        address recipient,
        address token,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 rate,
        uint256 period
    ) external override returns (uint256) {
        lastCreatePlanCall = CreatePlanCall({
            recipient: recipient,
            token: token,
            amount: amount,
            start: start,
            cliff: cliff,
            rate: rate,
            period: period
        });

        // Pull tokens from sender
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Return a mock plan ID
        return 1;
    }
}
