// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./YieldToken.sol";

contract YieldFarm is YieldToken, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public stakingToken;

    constructor(string memory _name, string memory _symbol, address _stakingToken) public YieldToken(_name, _symbol, 0) {
        stakingToken = _stakingToken;
    }

    function stake(uint256 _amount) external nonReentrant {
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant {
        _burn(msg.sender, _amount);
        IERC20(stakingToken).safeTransfer(msg.sender, _amount);
    }
}
