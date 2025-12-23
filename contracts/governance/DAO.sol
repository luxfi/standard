//SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

contract DAO is UUPSUpgradeable, OwnableUpgradeable {
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

  function initialize() public initializer {
    __Ownable_init_unchained();
  }
}
