// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IMigrator {
  // Take the current LP token address and return the new LP token address.
  // Migrator should have full access to the caller's LP token.
  function migrate(IERC20 token) external returns (IERC20);
}
