//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@luxfi/standard/lib/token/ERC20/ERC20.sol';
import "@luxfi/standard/lib/access/Ownable.sol";

contract WETH is ERC20, Ownable {
  constructor() ERC20('WETH', 'WETH') Ownable(msg.sender) {}

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
}