//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import "@openzeppelin/contracts/access/Ownable.sol";

contract WETH is ERC20, Ownable {
  constructor() ERC20('WETH', 'WETH') {}

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
}