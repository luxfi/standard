// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract WETH is ERC20 {
  constructor(uint256 mintAmount, address[] memory accounts) ERC20('WETH', 'WETH') {
    for (uint256 i = 0; i < accounts.length; i++) {
      _mint(accounts[i], mintAmount);
    }
  }
}
