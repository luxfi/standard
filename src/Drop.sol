// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Decimal } from './Decimal.sol';
import { IMarket } from './interfaces/IMarket.sol';
import { IMedia } from './interfaces/IMedia.sol';
import { ILux } from './interfaces/ILux.sol';
import { IDrop } from './interfaces/IDrop.sol';

import './console.sol';

contract Drop is IDrop, Ownable {
  using SafeMath for uint256;

  // Title of drop
  string public override title;

  // Address of ZooKeeper contract
  address public appAddress;

  // mapping of TokenType name to TokenType
  mapping(string => TokenType) public tokenTypes;
  
  string[] public tokenNames;

  event TokenTypeAdded(TokenType tokenType);
  event TokenTypeAskUpdated(string name, IMarket.Ask ask);
  event TokenTypeBidSharesUpdated(string name, IMarket.BidShares bidShares);

  // Ensure only ZK can call method
  modifier onlyApp() {
    require(appAddress == msg.sender, 'Drop: Only App can call this method');
    _;
  }

  constructor(string memory _title) {
    title = _title;
  }

  function totalMinted(string memory name) public view override returns (uint256) {
    return getTokenType(name).minted;
  }

  // Configure current App
  function configure(address _appAddress) public onlyOwner {
    appAddress = _appAddress;
  }

  // Add or configure a given kind of tokenType
  function setTokenType(
    ILux.Type kind,
    string memory name,
    IMarket.Ask memory ask,
    uint256 supply,
    string memory tokenURI,
    string memory metadataURI
  ) public onlyOwner returns (TokenType memory) {
    TokenType memory existingTokenType = tokenTypes[name];
    require(existingTokenType.supply == 0, 'Drop: TokenType name already exists');
    TokenType memory tokenType;
    tokenType.kind = kind;
    tokenType.name = name;
    tokenType.ask = ask;
    tokenType.supply = supply;
    tokenType.data = getMediaData(tokenURI, metadataURI);
    tokenType.bidShares = getBidShares();
    tokenType.timestamp = block.timestamp;
    tokenTypes[name] = tokenType;
    tokenNames.push(name);
    console.log('Drop: Added token type:', tokenType.name);
    emit TokenTypeAdded(tokenType);
    emit TokenTypeAskUpdated(name, ask);
    return tokenType;
  }

  /**
   * @notice Validates that the provided bid shares sum to 100
   */
  function isValidBidShares(IMarket.BidShares memory bidShares) public pure returns (bool) {
    return bidShares.creator.value.add(bidShares.owner.value).add(bidShares.prevOwner.value) == uint256(100).mul(Decimal.BASE);
  }

  function setBidShares(string memory name, IMarket.BidShares memory bidShares) public onlyOwner {
    require(isValidBidShares(bidShares), 'Drop: Invalid bid shares, must sum to 100');
    tokenTypes[name].bidShares = bidShares;
    emit TokenTypeBidSharesUpdated(name, bidShares);
  }

  function setTokenTypeAsk(string memory name, IMarket.Ask memory ask) public onlyOwner {
    tokenTypes[name].ask = ask;
    emit TokenTypeAskUpdated(name, ask);
  }

  function getTokenTypes() public view returns(TokenType[] memory){
    TokenType[] memory _tokenTypes = new TokenType[](tokenNames.length);
    uint256 i = 0;
    for (i; i < tokenNames.length; i++) {
      _tokenTypes[i] = tokenTypes[tokenNames[i]];
    }
    return _tokenTypes;
  }

  // Return price for current EggDrop
  function tokenTypeAsk(string memory name) public view override returns (IMarket.Ask memory) {
    return getTokenType(name).ask;
  }

  function tokenSupply(string memory name) public view override returns (uint256) {
    return getTokenType(name).supply;
  }

  // Return a new TokenType Token
  function newNFT(string memory name) external override onlyApp returns (ILux.Token memory) {
    TokenType memory tokenType = getTokenType(name);
    require(tokenSupply(name) == 0 || tokenType.minted < tokenSupply(name), 'Out of tokens');

    tokenType.minted++;
    tokenTypes[tokenType.name] = tokenType;

    // Convert tokenType into a token
    return
      ILux.Token({
        kind: tokenType.kind,
        name: tokenType.name,
        id: 0,
        timestamp: block.timestamp,
        data: tokenType.data,
        bidShares: tokenType.bidShares,
        meta: ILux.Meta(0, 0, false)
      });
  }

  // Get TokenType by name
  function getTokenType(string memory name) public view override returns (TokenType memory) {
    return tokenTypes[name];
  }

  // Helper to construct IMarket.BidShares struct
  function getBidShares() private pure returns (IMarket.BidShares memory) {
    return
      IMarket.BidShares({
        creator: Decimal.D256(uint256(10).mul(Decimal.BASE)),
        owner: Decimal.D256(uint256(80).mul(Decimal.BASE)),
        prevOwner: Decimal.D256(uint256(10).mul(Decimal.BASE))
      });
  }

  // Helper to construct IMedia.MediaData struct
  function getMediaData(string memory tokenURI, string memory metadataURI) private pure returns (IMedia.MediaData memory) {
    return IMedia.MediaData({ tokenURI: tokenURI, metadataURI: metadataURI, contentHash: bytes32(0), metadataHash: bytes32(0) });
  }
}
