// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { ILux } from './ILux.sol';
import { IMarket } from './IMarket.sol';
import { IMedia } from './IMedia.sol';


interface IDrop {

  struct TokenType {
    ILux.Type kind;
    string name;
    IMarket.Ask ask;
    uint256 supply;
    uint256 timestamp; // time created
    uint256 minted; // amount minted
    IMedia.MediaData data;
    IMarket.BidShares bidShares;
  }

  function title() external view returns (string memory);

  function tokenTypeAsk(string memory name) external view returns (IMarket.Ask memory);

  function totalMinted(string memory name) external view returns (uint256);

  function tokenSupply(string memory name) external view returns (uint256);

  function newNFT(string memory name) external returns (ILux.Token memory);

  function getTokenType(string memory name) external view returns (TokenType memory);
}
