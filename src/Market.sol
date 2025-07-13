// SPDX-License-Identifier: GPL-3.0
// Forked from https://github.com/ourzora/core @ 450cd154bfbb70f62e94050cc3f1560d58e0506a

pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

import { Decimal } from './Decimal.sol';
import { Media } from './Media.sol';
import { IDrop } from './interfaces/IDrop.sol';
import { IMarket } from './interfaces/IMarket.sol';
import { ILux } from './interfaces/ILux.sol';

import './console.sol';

/**
 * @title A Market for pieces of media
 * @notice This contract contains all of the market logic for Media
 */
contract Market is IMarket, Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* *******
   * Globals
   * *******
   */
  // Address of the media contract that can call this market
  address public mediaContract;

  // Deployment Address
  address private _owner;

  // Mapping from token to mapping from bidder to bid
  mapping(uint256 => mapping(address => Bid)) private _tokenBidders;
  
  // Mapping from token type name to mapping from bidder to bid
  mapping(string => mapping(address => Bid)) private _lazyTokenBidders;

  // Mapping from token to the bid shares for the token
  mapping(uint256 => BidShares) private _bidShares;

  // Mapping from token to the current ask for the token
  mapping(uint256 => Ask) private _tokenAsks;

  // Mapping of bidders that are authorized to place offline bids
  mapping(address => bool) private _offlineBidders;

  /* *********
   * Modifiers
   * *********
   */

  /**
   * @notice require that the msg.sender is the configured media contract
   */
  modifier onlyMediaCaller() {
    require(mediaContract == msg.sender, 'Market: Only media contract');
    _;
  }

  /* ****************
   * View Functions
   * ****************
   */
  function bidForTokenBidder(uint256 tokenId, address bidder) external view override returns (Bid memory) {
    return _tokenBidders[tokenId][bidder];
  }

  function lazyBidForTokenBidder(uint256 dropId, string memory name, address bidder) external view override returns (Bid memory) {
    string memory dropTokenTypeName = getDropTokenTypeName(dropId, name);
    return _lazyTokenBidders[dropTokenTypeName][bidder];
  }

  function currentAskForToken(uint256 tokenId) external view override returns (Ask memory) {
    return _tokenAsks[tokenId];
  }

  function bidSharesForToken(uint256 tokenId) public view override returns (BidShares memory) {
    return _bidShares[tokenId];
  }

  function isOfflineBidder(address bidder) public view override returns (bool) {
    return _offlineBidders[bidder];
  }

  function setOfflineBidder(address bidder, bool authorized) external override onlyOwner {
    _offlineBidders[bidder] = authorized;
  }

  /**
   * @notice Validates that the bid is valid by ensuring that the bid amount can be split perfectly into all the bid shares.
   *  We do this by comparing the sum of the individual share values with the amount and ensuring they are equal. Because
   *  the splitShare function uses integer division, any inconsistencies with the original and split sums would be due to
   *  a bid splitting that does not perfectly divide the bid amount.
   */
  function isValidBid(uint256 tokenId, uint256 bidAmount) public view override returns (bool) {
    BidShares memory bidShares = bidSharesForToken(tokenId);
    require(isValidBidShares(bidShares), 'Market: Invalid bid shares for token');
    return bidAmount != 0 && (bidAmount == splitShare(bidShares.creator, bidAmount).add(splitShare(bidShares.prevOwner, bidAmount)).add(splitShare(bidShares.owner, bidAmount)));
  }

  function isValidLazyBid(IDrop.TokenType memory tokenType, uint256 bidAmount) public pure returns (bool) {
    BidShares memory bidShares = tokenType.bidShares;
    require(isValidBidShares(bidShares), 'Market: Invalid lazy bid shares for token');
    return bidAmount != 0 && (bidAmount == splitShare(bidShares.creator, bidAmount).add(splitShare(bidShares.prevOwner, bidAmount)).add(splitShare(bidShares.owner, bidAmount)));
  }

  /**
   * @notice Validates that the provided bid shares sum to 100
   */
  function isValidBidShares(BidShares memory bidShares) public pure override returns (bool) {
    return bidShares.creator.value.add(bidShares.owner.value).add(bidShares.prevOwner.value) == uint256(100).mul(Decimal.BASE);
  }

  /**
   * @notice return a % of the specified amount. This function is used to split a bid into shares
   * for a media's shareholders.
   */
  function splitShare(Decimal.D256 memory sharePercentage, uint256 amount) public pure override returns (uint256) {
    return Decimal.mul(amount, sharePercentage).div(100);
  }

  /**
   * @notice Sets the media contract address. This address is the only permitted address that
   * can call the mutable functions. This method can only be called once.
   */
  function configure(address mediaContractAddress) external override onlyOwner {
    require(mediaContractAddress != address(0), 'Market: cannot set media contract as zero address');

    mediaContract = mediaContractAddress;
  }

  /**
   * @notice Sets bid shares for a particular tokenId. These bid shares must
   * sum to 100.
   */
  function setBidShares(uint256 tokenId, BidShares memory bidShares) public override onlyMediaCaller {
    require(isValidBidShares(bidShares), 'Market: Invalid bid shares, must sum to 100');
    _bidShares[tokenId] = bidShares;
    emit BidShareUpdated(tokenId, bidShares);
  }

  /**
   * @notice Sets the ask on a particular media. If the ask cannot be evenly split into the media's
   * bid shares, this reverts.
   */
  function setAsk(uint256 tokenId, Ask memory ask) public override onlyMediaCaller {
    require(isValidBid(tokenId, ask.amount), 'Market: Ask invalid for share splitting');

    _tokenAsks[tokenId] = ask;
    emit AskCreated(tokenId, ask);
  }

  /**
   * @notice removes an ask for a token and emits an AskRemoved event
   */
  function removeAsk(uint256 tokenId) external override onlyMediaCaller {
    emit AskRemoved(tokenId, _tokenAsks[tokenId]);
    delete _tokenAsks[tokenId];
  }

  /**
   * @notice Sets the bid on a particular media for a bidder. The token being used to bid
   * is transferred from the spender to this contract to be held until removed or accepted.
   * If another bid already exists for the bidder, it is refunded.
   */
  function setBid(
    uint256 tokenId,
    Bid memory bid,
    address spender
  ) public override onlyMediaCaller {
    BidShares memory bidShares = _bidShares[tokenId];
    require(bidShares.creator.value.add(bid.sellOnShare.value) <= uint256(100).mul(Decimal.BASE), 'Market: Sell on fee invalid for share splitting');
    require(bid.bidder != address(0), 'Market: bidder cannot be 0 address');
    require(!bid.offline || (bid.offline && isOfflineBidder(bid.bidder)), 'Market: Only whitelisted offline bidder');
    require(bid.amount != 0, 'Market: cannot bid amount of 0');
    // require(bid.currency != address(0), 'Market: bid currency cannot be 0 address');
    require(bid.recipient != address(0), 'Market: bid recipient cannot be 0 address');

    Bid storage existingBid = _tokenBidders[tokenId][bid.bidder];

    // If there is an existing bid, refund it before continuing
    if (existingBid.amount > 0) {
      removeBid(tokenId, bid.bidder);
    }

    uint256 bidAmount = bid.amount;

    if (bid.currency != address(0) && !bid.offline) {
      IERC20 token = IERC20(bid.currency);
      // We must check the balance that was actually transferred to the market,
      // as some tokens impose a transfer fee and would not actually transfer the
      // full amount to the market, resulting in locked funds for refunds & bid acceptance
      uint256 beforeBalance = token.balanceOf(address(this));
      token.safeTransferFrom(spender, address(this), bid.amount);
      uint256 afterBalance = token.balanceOf(address(this));
      bidAmount = afterBalance.sub(beforeBalance);
    }

    _tokenBidders[tokenId][bid.bidder] = Bid(bidAmount, bid.currency, bid.bidder, bid.recipient, bid.sellOnShare, bid.offline);

    emit BidCreated(tokenId, bid);

    // DO NOT automatically accept bids
    // if (_tokenAsks[tokenId].currency != address(0) && bid.currency == _tokenAsks[tokenId].currency && bid.amount >= _tokenAsks[tokenId].amount) {
    //   // Finalize exchange
    //   _finalizeNFTTransfer(tokenId, bid.bidder);
    // }
  }
  
  /**
   * @notice Sets the bid on a particular media for a bidder. The token being used to bid
   * is transferred from the spender to this contract to be held until removed or accepted.
   * If another bid already exists for the bidder, it is refunded.
   */
  function setLazyBidFromApp(
    uint256 dropId,
    IDrop.TokenType memory tokenType,
    Bid memory bid,
    address spender
  ) external override onlyMediaCaller {
    require(tokenType.bidShares.creator.value.add(bid.sellOnShare.value) <= uint256(100).mul(Decimal.BASE), 'Market: Sell on fee invalid for share splitting');
    require(bid.bidder != address(0), 'Market: bidder cannot be 0 address');
    require(!bid.offline || (bid.offline && isOfflineBidder(bid.bidder)), 'Market: Only whitelisted offline bidder');
    require(bid.amount != 0, 'Market: cannot bid amount of 0');
    // require(bid.currency != address(0), 'Market: bid currency cannot be 0 address');
    require(bid.recipient != address(0), 'Market: bid recipient cannot be 0 address');

    uint256 bidAmount = bid.amount;

    if (bid.currency != address(0) && !bid.offline) {
      IERC20 token = IERC20(bid.currency);
      // We must check the balance that was actually transferred to the market,
      // as some tokens impose a transfer fee and would not actually transfer the
      // full amount to the market, resulting in locked funds for refunds & bid acceptance
      uint256 beforeBalance = token.balanceOf(address(this));
      token.safeTransferFrom(spender, address(this), bid.amount);
      uint256 afterBalance = token.balanceOf(address(this));
      bidAmount = afterBalance.sub(beforeBalance);
    }

    string memory dropTokenTypeName = getDropTokenTypeName(dropId, tokenType.name);

    _lazyTokenBidders[dropTokenTypeName][bid.bidder] = Bid(bidAmount, bid.currency, bid.bidder, bid.recipient, bid.sellOnShare, bid.offline);

    emit LazyBidCreated(dropId, tokenType.name, bid); 
  }

  function getDropTokenTypeName(uint256 tokenId, string memory name) internal pure returns(string memory) {
    return string(abi.encodePacked(tokenId, '-', name));
  }

  /**
   * @notice Removes the bid on a particular media for a bidder. The bid amount
   * is transferred from this contract to the bidder, if they have a bid placed.
   */
  function removeBid(uint256 tokenId, address bidder) public override onlyMediaCaller {
    Bid storage bid = _tokenBidders[tokenId][bidder];
    address bidCurrency = bid.currency;
    uint256 bidAmount = bid.amount;
    bool bidOffline = bid.offline;

    require(bid.amount > 0, 'Market: cannot remove bid amount of 0');

    emit BidRemoved(tokenId, bid);
    delete _tokenBidders[tokenId][bidder];

    console.log('Market.removeBid', tokenId, bidCurrency, bidOffline);

    if (bidCurrency != address(0) && !bidOffline) {
      IERC20 token = IERC20(bidCurrency);
      token.safeTransfer(bidder, bidAmount);
    }
  }

  /**
   * @notice Removes the bid on a particular media for a bidder. The bid amount
   * is transferred from this contract to the bidder, if they have a bid placed.
   */
  function removeLazyBidFromApp(uint256 dropId, string memory name, address bidder) public override onlyMediaCaller {
    string memory dropTokenTypeName = getDropTokenTypeName(dropId, name);
    Bid storage bid = _lazyTokenBidders[dropTokenTypeName][bidder];
    address bidCurrency = bid.currency;
    uint256 bidAmount = bid.amount;
    bool bidOffline = bid.offline;

    require(bid.amount > 0, 'Market: cannot remove bid amount of 0');

    emit LazyBidRemoved(dropId, name, bid);
    delete _lazyTokenBidders[dropTokenTypeName][bidder];

    console.log('Market.removeLazyBidFromApp', dropTokenTypeName, bidCurrency, bidOffline);

    if (bidCurrency != address(0) && !bidOffline) {
      IERC20 token = IERC20(bidCurrency);
      token.safeTransfer(bidder, bidAmount);
    }
  }


  /**
   * @notice Accepts a bid from a particular bidder. Can only be called by the media contract.
   * See {_finalizeNFTTransfer}
   * Provided bid must match a bid in storage. This is to prevent a race condition
   * where a bid may change while the acceptBid call is in transit.
   * A bid cannot be accepted if it cannot be split equally into its shareholders.
   * This should only revert in rare instances (example, a low bid with a zero-decimal token),
   * but is necessary to ensure fairness to all shareholders.
   */
  function acceptBid(uint256 tokenId, Bid calldata expectedBid) external override onlyMediaCaller {
    Bid memory bid = _tokenBidders[tokenId][expectedBid.bidder];
    require(bid.amount > 0, 'Market: cannot accept bid of 0');
    require(
      bid.amount == expectedBid.amount && bid.currency == expectedBid.currency && bid.sellOnShare.value == expectedBid.sellOnShare.value && bid.recipient == expectedBid.recipient,
      'Market: Unexpected bid found.'
    );
    require(isValidBid(tokenId, bid.amount), 'Market: Bid invalid for share splitting');

    _finalizeNFTTransfer(tokenId, bid.bidder);
  }

  function acceptLazyBidFromApp(uint256 dropId, IDrop.TokenType memory tokenType, ILux.Token memory token, Bid calldata expectedBid) external override onlyMediaCaller {
    string memory dropTokenTypeName = getDropTokenTypeName(dropId, tokenType.name);
    Bid memory bid = _lazyTokenBidders[dropTokenTypeName][expectedBid.bidder];
    require(bid.amount > 0, 'Market: cannot accept bid of 0');
    require(
      bid.amount == expectedBid.amount && bid.currency == expectedBid.currency && bid.sellOnShare.value == expectedBid.sellOnShare.value && bid.recipient == expectedBid.recipient,
      'Market: Unexpected bid found.'
    );
    require(isValidLazyBid(tokenType, bid.amount), 'Market: Bid invalid for share splitting');

    _finalizeLazyMint(dropId, tokenType, token, bid.bidder);    
  }

  /**
   * @notice Given a token ID and a bidder, this method transfers the value of
   * the bid to the shareholders. It also transfers the ownership of the media
   * to the bid recipient. Finally, it removes the accepted bid and the current ask.
   */
  function _finalizeNFTTransfer(uint256 tokenId, address bidder) private {
    Bid memory bid = _tokenBidders[tokenId][bidder];
    BidShares storage bidShares = _bidShares[tokenId];

    if (bid.currency != address(0) && !bid.offline) {
      IERC20 token = IERC20(bid.currency);

      // Transfer bid share to owner of media
      token.safeTransfer(IERC721(mediaContract).ownerOf(tokenId), splitShare(bidShares.owner, bid.amount));
      // Transfer bid share to creator of media
      token.safeTransfer(owner(), splitShare(bidShares.creator, bid.amount));
      // Transfer bid share to previous owner of media (if applicable)
      token.safeTransfer(Media(mediaContract).previousTokenOwners(tokenId), splitShare(bidShares.prevOwner, bid.amount));
    }

    // Transfer media to bid recipient
    Media(mediaContract).auctionTransfer(tokenId, bid.recipient);

    // Calculate the bid share for the new owner,
    // equal to 100 - creatorShare - sellOnShare
    bidShares.owner = Decimal.D256(uint256(100).mul(Decimal.BASE).sub(_bidShares[tokenId].creator.value).sub(bid.sellOnShare.value));
    // Set the previous owner share to the accepted bid's sell-on fee
    bidShares.prevOwner = bid.sellOnShare;

    // Remove the accepted bid
    delete _tokenBidders[tokenId][bidder];

    emit BidShareUpdated(tokenId, bidShares);
    emit BidFinalized(tokenId, bid);
  }

  /**
   * @notice Given a token ID and a bidder, this method transfers the value of
   * the bid to the shareholders. It also transfers the ownership of the media
   * to the bid recipient. Finally, it removes the accepted bid and the current ask.
   */
  function _finalizeLazyMint(uint256 dropId, IDrop.TokenType memory tokenType, ILux.Token memory token, address bidder) private {

    string memory dropTokenTypeName = getDropTokenTypeName(dropId, tokenType.name);

    Bid memory bid = _lazyTokenBidders[dropTokenTypeName][bidder];

    BidShares memory bidShares = tokenType.bidShares;

    if (bid.currency != address(0) && !bid.offline) {
      IERC20 erc20Token = IERC20(bid.currency);

      erc20Token.safeTransfer(owner(), bid.amount); // Transfer 100%
    }

    // Transfer media to bid recipient
    Media(mediaContract).mintToken(bid.recipient, token);

    // Calculate the bid share for the new owner,
    // equal to 100 - creatorShare - sellOnShare
    bidShares.owner = Decimal.D256(uint256(100).mul(Decimal.BASE).sub(bidShares.creator.value).sub(bid.sellOnShare.value));
    // Set the previous owner share to the accepted bid's sell-on fee
    bidShares.prevOwner = bid.sellOnShare;

    // Remove the accepted bid
    delete _lazyTokenBidders[dropTokenTypeName][bidder];

    emit BidShareUpdated(token.id, bidShares);
    emit LazyBidFinalized(dropId, tokenType.name, token.id, bid);
  }

}
