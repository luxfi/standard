// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { IMedia } from './IMedia.sol';
import { IMarket } from './IMarket.sol';

interface ILux {
  enum Type {
    VALIDATOR,
    ATM,
    WALLET,
    CASH
  }

  struct Meta {
    uint256 tokenId; // originating egg
    uint256 dropId; // originating drop
    bool burned; // token has been burned
  }

  struct Token {
    Type kind;
    string name;
    uint256 id; // unique ID
    uint256 timestamp; // time created
    IMedia.MediaData data;
    IMarket.BidShares bidShares;
    Meta meta;
  }
}
