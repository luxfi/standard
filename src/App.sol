// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import { Counters } from '@openzeppelin/contracts/utils/Counters.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { Initializable } from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { AddressUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import { Decimal } from './Decimal.sol';
import { IDrop } from './interfaces/IDrop.sol';
import { IMedia } from './interfaces/IMedia.sol';
import { IMarket } from './interfaces/IMarket.sol';
import { ILux } from './interfaces/ILux.sol';

import './console.sol';

contract App is OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
  using SafeMath for uint256;
  using Counters for Counters.Counter;
  using AddressUpgradeable for address payable;

  Counters.Counter private dropIds;

  // Declare an Event
  event AddDrop(uint256 dropId, address indexed dropAddress, string title);
  event Mint(uint256 indexed tokenId, ILux.Token token);
  event UpdatedTokenName(uint256 indexed tokenId, string name);

  // Mapping of Address to Drop ID
  mapping(uint256 => address) public drops;

  // Mapping of ID to Address
  mapping(address => uint256) public dropAddresses;

  // Mapping of ID to NFT
  mapping(uint256 => ILux.Token) public tokens;

  // External contracts
  IMedia public media;
  IMarket public market;

  // Ensure only owner can upgrade contract
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  // Initialize upgradeable contract
  function initialize() public initializer {
    __Ownable_init_unchained();
  }

  // Configure App
  function configure(address _media, address _market) public onlyOwner {
    media = IMedia(_media);
    market = IMarket(_market);
  }

  // Add new drop
  function addDrop(address dropAddress) public onlyOwner returns (uint256) {
    require(dropAddresses[dropAddress] == 0, 'App: Drop already added');
    IDrop drop = IDrop(dropAddress);
    dropIds.increment();
    uint256 dropId = dropIds.current();
    drops[dropId] = dropAddress;
    dropAddresses[dropAddress] = dropId;
    emit AddDrop(dropId, dropAddress, drop.title());
    return dropId;
  }

  function mintMany(
    uint256 dropId,
    string memory name,
    uint256 quantity
  ) public onlyOwner {
    for (uint256 i = 0; i < quantity; i++) {
      mint(dropId, name);
    }
  }

  // Issue a new token to owner
  function mint(uint256 dropId, string memory name) public onlyOwner returns (ILux.Token memory) {
    IDrop drop = IDrop(drops[dropId]);

    // Get NFT for drop
    ILux.Token memory token = drop.newNFT(name);
    
    IMarket.Ask memory defaultAsk = drop.tokenTypeAsk(name);

    token = media.mintToken(msg.sender, token);

    console.log('mint', msg.sender, token.name, token.id);

    tokens[token.id] = token;

    // Set default ask
    if (defaultAsk.amount > 0) {
      media.setAskFromApp(token.id, defaultAsk);
    }

    emit Mint(token.id, token);

    return token;
  }

  function setTokenName(uint256 tokenId, string memory name) public {
    require(media.ownerOf(tokenId) == msg.sender, 'App: msg sender must be owner of token');
    tokens[tokenId].name = name;
    emit UpdatedTokenName(tokenId, name);
    console.log('Updated token name:', name);
  }

  // Set Bid with ETH
  /**
   * @notice Sets the bid on a particular media for a bidder. The token being used to bid
   * is transferred from the spender to this contract to be held until removed or accepted.
   * If another bid already exists for the bidder, it is refunded.
   */
  function setBid(uint256 tokenId, IMarket.Bid memory bid) public payable nonReentrant {
    media.setBidFromApp(tokenId, bid, msg.sender);
  }

  function setLazyBid(uint256 dropId, string memory name, IMarket.Bid memory bid) public payable nonReentrant {
    IDrop drop = IDrop(drops[dropId]);
    IDrop.TokenType memory tokenType = drop.getTokenType(name);
    require(tokenType.supply > 0, 'App: token type does not exist');
    require(bid.currency == address(0), 'App: currency must be payable');
    media.setLazyBidFromApp(dropId, tokenType, bid, msg.sender);
  }

  function setLazyBidERC20(uint256 dropId, string memory name, IMarket.Bid memory bid) public nonReentrant {
    IDrop drop = IDrop(drops[dropId]);
    IDrop.TokenType memory tokenType = drop.getTokenType(name);
    require(tokenType.supply > 0, 'App: token type does not exist');
    media.setLazyBidFromApp(dropId, tokenType, bid, msg.sender);
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
  function acceptBid(uint256 tokenId, IMarket.Bid memory bid) public nonReentrant {
    
    IMarket.BidShares memory bidShares = market.bidSharesForToken(tokenId);
    
    address mediaOwner = media.ownerOf(tokenId);
    address prevOwner = media.previousTokenOwner(tokenId);

    media.acceptBidFromApp(tokenId, bid, msg.sender);

    if (bid.currency == address(0) && bid.amount > 0 && !bid.offline) {      
      // Transfer bid share to mediaOwner of media
      payable(mediaOwner).sendValue(market.splitShare(bidShares.owner, bid.amount));
      // Transfer bid share to creator of media
      payable(owner()).sendValue(market.splitShare(bidShares.creator, bid.amount));
      // Transfer bid share to previous owner of media (if applicable)
      payable(prevOwner).sendValue(market.splitShare(bidShares.prevOwner, bid.amount));
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
  function acceptLazyBid(uint256 dropId, string memory name, IMarket.Bid memory bid) public nonReentrant {
    IDrop drop = IDrop(drops[dropId]);

    IDrop.TokenType memory tokenType = drop.getTokenType(name);

    require(tokenType.supply > 0, 'App: token type does not exist');

    ILux.Token memory token = drop.newNFT(name);

    media.acceptLazyBidFromApp(dropId, tokenType, token, bid);    
    
    if (bid.currency == address(0) && bid.amount > 0 && !bid.offline) {
      // Transfer the amount to the contract owner address
      payable(owner()).sendValue(bid.amount);
    }
  }

  /**
   * @notice Removes the bid on a particular media for a bidder. The bid amount
   * is transferred from this contract to the bidder, if they have a bid placed.
   */
  function removeBid(uint256 tokenId) public nonReentrant {
    IMarket.Bid memory bid = market.bidForTokenBidder(tokenId, msg.sender); // Get the bid before it is removed
    
    media.removeBidFromApp(tokenId, msg.sender);
    
    // Refund bidder if it was a payable bid and not an offline bid.
    if (bid.currency == address(0) && bid.amount > 0 && !bid.offline) {
      payable(bid.bidder).sendValue(bid.amount);
    }
  }

  /**
   * @notice Removes the bid on a particular media for a bidder. The bid amount
   * is transferred from this contract to the bidder, if they have a bid placed.
   */
  function removeLazyBid(uint256 dropId, string memory name) public nonReentrant {
    IMarket.Bid memory bid = market.lazyBidForTokenBidder(dropId, name, msg.sender); // Get the bid before it is removed
    
    media.removeLazyBidFromApp(dropId, name, msg.sender);
    
    // Refund bidder if it was a payable bid and not an offline bid.
    if (bid.currency == address(0) && bid.amount > 0 && !bid.offline) {
      payable(bid.bidder).sendValue(bid.amount);
    }
  }

  // Enable owner to withdraw lux if necessary
  function withdraw(address payable receiver, uint256 amount) public onlyOwner {
    receiver.sendValue(amount);
  }

  // Payable fallback functions
  receive() external payable {}

  fallback() external payable {}
}
