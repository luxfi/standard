// SPDX-License-Identifier: GPL-3.0
// Forked from https://github.com/ourzora/core @ 450cd154bfbb70f62e94050cc3f1560d58e0506a

pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import { Decimal } from '../Decimal.sol';
import { IDrop } from './IDrop.sol';
import { ILux } from './ILux.sol';

/**
 * @title Interface for Zoo Protocol's Market
 */
interface IMarket {
  struct Bid {
    // Amount of the currency being bid
    uint256 amount;
    // Address to the ERC20 token being used to bid
    address currency;
    // Address of the bidder
    address bidder;
    // Address of the recipient
    address recipient;
    // % of the next sale to award the current owner
    Decimal.D256 sellOnShare;
    // Flag bid as offline for OTC sale
    bool offline;
  }

  struct Ask {
    // Amount of the currency being asked
    uint256 amount;
    // Address to the ERC20 token being asked
    address currency;
    // Flag ask as offline for OTC sale
    bool offline;
  }

  struct BidShares {
    // % of sale value that goes to the _previous_ owner of the nft
    Decimal.D256 prevOwner;
    // % of sale value that goes to the original creator of the nft
    Decimal.D256 creator;
    // % of sale value that goes to the seller (current owner) of the nft
    Decimal.D256 owner;
  }

  event BidCreated(uint256 indexed tokenId, Bid bid);
  event BidRemoved(uint256 indexed tokenId, Bid bid);
  event BidFinalized(uint256 indexed tokenId, Bid bid);
  event AskCreated(uint256 indexed tokenId, Ask ask);
  event AskRemoved(uint256 indexed tokenId, Ask ask);
  event BidShareUpdated(uint256 indexed tokenId, BidShares bidShares);
  event LazyBidFinalized(uint256 dropId, string name, uint256 indexed tokenId, Bid bid);
  event LazyBidCreated(uint256 dropId, string name, Bid bid);
  event LazyBidRemoved(uint256 dropId, string name, Bid bid);

  function bidForTokenBidder(uint256 tokenId, address bidder) external view returns (Bid memory);

  function lazyBidForTokenBidder(uint256 dropId, string memory name, address bidder) external view returns (Bid memory);

  function currentAskForToken(uint256 tokenId) external view returns (Ask memory);

  function bidSharesForToken(uint256 tokenId) external view returns (BidShares memory);

  function isValidBid(uint256 tokenId, uint256 bidAmount) external view returns (bool);

  function isValidBidShares(BidShares calldata bidShares) external pure returns (bool);

  function splitShare(Decimal.D256 calldata sharePercentage, uint256 amount) external pure returns (uint256);

  function configure(address mediaContractAddress) external;

  function setBidShares(uint256 tokenId, BidShares calldata bidShares) external;

  function setAsk(uint256 tokenId, Ask calldata ask) external;

  function removeAsk(uint256 tokenId) external;

  function setBid(
    uint256 tokenId,
    Bid calldata bid,
    address spender
  ) external;

  function setLazyBidFromApp(
    uint256 dropId,
    IDrop.TokenType memory tokenType,
    Bid memory bid,
    address spender
  ) external;

  function removeBid(uint256 tokenId, address bidder) external;

  function removeLazyBidFromApp(uint256 dropId, string memory name, address sender) external;

  function acceptBid(uint256 tokenId, Bid calldata expectedBid) external;

  function acceptLazyBidFromApp(uint256 dropId, IDrop.TokenType memory tokenType, ILux.Token memory token, Bid calldata expectedBid) external;

  function isOfflineBidder(address bidder) external returns (bool);

  function setOfflineBidder(address bidder, bool authorized) external;
}
