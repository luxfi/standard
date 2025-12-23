// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IDrop } from "./interfaces/IDrop.sol";
import { IMedia } from "./interfaces/IMedia.sol";
import { ILux } from "./interfaces/ILux.sol";
import { IERC721Burnable } from "./interfaces/IERC721Burnable.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { IDAO } from "./interfaces/IDAO.sol";

interface ICustomDrop{
    function animalStageYields(string memory name) external returns (ILux.StageYields memory);
}

contract DLUX is Ownable, ILux, IDAO {
  using SafeMath for uint256;
  using Counters for Counters.Counter;

  Counters.Counter public dropIDs;
  Counters.Counter private whitelistedCount;

  struct Feeding{
    uint256 count;
    uint40 lastTimeFed;
  }
    bool public allowHatching;
    bool public allowFeeding;
    bool public allowBreeding;

  mapping(uint256 => address) public drops;

  mapping(address => uint256) public dropAddresses;

  mapping(uint256 => ILux.Token) public tokens;

  mapping(uint256 => uint256) public NFTDrop;

  mapping(uint256 => Feeding) public feededTimes;

  uint256 public namePrice;
  uint256 public BNBPrice;
  address public BNB;

  IMedia public media;
  IERC20 public lux;
  IUniswapV2Pair public pair;
  address public bridge;
  bool public unlocked;

  modifier onlyBridge() {
    require(msg.sender == bridge);
    _;
  }

  function configure(
    address _media,
    address _lux,
    address _pair,
    address _bridge,
    bool _unlocked
  ) public onlyOwner {
    media = IMedia(_media);
    lux = IERC20(_lux);
    pair = IUniswapV2Pair(_pair);
    bridge = _bridge;
    unlocked = _unlocked;
  }

  function addDrop(address dropAddress) public onlyOwner returns (uint256) {
    require(dropAddresses[dropAddress] == 0, "Drop already added");
    IDrop drop = IDrop(dropAddress);
    dropIDs.increment();
    uint256 dropID = dropIDs.current();
    drops[dropID] = dropAddress;
    dropAddresses[dropAddress] = dropID;
    emit AddDrop(dropAddress, drop.title(), drop.totalSupply());
    return dropID;
  }

  function setNamePrice(uint256 price) public onlyOwner {
    namePrice = price.mul(10**18);
  }


  function setBNBPrice(uint256 price) public onlyOwner {
    BNBPrice = price;
  }

  function changeAllowance(bool _allowHatching, bool _allowFeeding, bool _allowBreeding) public onlyOwner {
      allowHatching = _allowHatching;
      allowFeeding = _allowFeeding;
      allowBreeding = _allowBreeding;
  }

  function setBNB(address _bnb) public onlyOwner {
    BNB = _bnb;
  }

  function mint(address owner, ILux.Token memory token) private returns (ILux.Token memory) {
    token = media.mintToken(owner, token);
    tokens[token.id] = token;
    NFTDrop[token.id] = token.dropNFT;
    emit Mint(owner, token.id);
    return token;
  }

  function burn(address owner, uint256 tokenID) private {
  
    media.burnToken(owner, tokenID);
    tokens[tokenID].meta.burned = true;
    emit Burn(owner, tokenID);
  }

  function swap(
    address owner,
    uint256 tokenID,
    uint256 chainId
  ) external onlyBridge {

    burn(owner, tokenID);
    tokens[tokenID].meta.swapped = true;
    emit Swap(owner, tokenID, chainId);
  }

  function remint(
    address owner,
    ILux.Token calldata token
  ) external onlyBridge {
    mint(owner, token);
  }

  function updateTokenUris(uint256 tokenId, uint256 dropId) public {
    IDrop drop = IDrop(drops[dropId]);
    media.updateTokenURI(tokens[tokenId].dropNFT, drop.getNFT(tokens[tokenId].dropNFT).data.tokenURI);
    media.updateTokenMetadataURI(tokens[tokenId].dropNFT, drop.getNFT(tokens[tokenId].dropNFT).data.metadataURI);
  }

  function mintNFT(uint256 nftId, uint256 dropID, address owner) internal returns (ILux.Token memory) {
    IDrop drop = IDrop(drops[dropID]);
    ILux.Token memory nft = drop.newNFT(nftId);

    nft = mint(owner, nft);
    NFTDrop[nft.id] = nftId;

    emit BuyNFT(owner, nft.id);
    return nft;
  }

   function buyNFTsWithBNB(uint256 nftId, uint256 dropID, uint256 quantity) public {

    // Ensure enough BNB was sent
    require(IERC20(BNB).balanceOf(msg.sender) >= (BNBPrice * quantity), "Not enough BNB");

    for (uint8 i = 0; i < quantity; i++) {
      mintNFT(nftId, dropID, msg.sender);
    }

    IERC20(BNB).transferFrom(msg.sender, address(this), BNBPrice);
  }

   function buyNFTsBNB(uint256 nftId, uint256 dropID, uint256 quantity) public payable {

    // Ensure enough BNB was sent
    IDrop drop = IDrop(drops[dropID]);
    uint256 bnbPrice = (drop.nftPrice(nftId) + (18000 * (10 ** 18))) / luxPriceBNB(); // 420k LUX in BNB
    require(msg.value >= bnbPrice * quantity, "Not enough BNB");

    for (uint8 i = 0; i < quantity; i++) {
      mintNFT(nftId, dropID, msg.sender);
    }
  }


  function buyNFT(uint256 nftId,uint256 dropID, address buyer) private returns (ILux.Token memory) {

    IDrop drop = IDrop(drops[dropID]);
    uint256 price = drop.nftPrice(nftId);

    lux.transferFrom(buyer, address(this), price);

    return mintNFT(nftId, dropID, buyer);
  }

  function buyNFTs(uint256 nftId, uint256 dropID, uint256 quantity) public {
    IDrop drop = IDrop(drops[dropID]);
    uint256 price = drop.nftPrice(nftId);
    require(lux.balanceOf(msg.sender) >= price * quantity, "Not enough LUX");
    for (uint8 i = 0; i < quantity; i++) {
      buyNFT(nftId, dropID, msg.sender);
    }
  }

  function dropNFTs(uint256 nftId, uint256 dropID,address buyer) override public {
    IDrop drop = IDrop(drops[dropID]);
    require(msg.sender == drop.NFTDropAddress(), "wrong nft dropper");
    mintNFT(nftId, dropID, buyer);
  }

  function hatchNFT(uint256 dropID, uint256 nftID) public returns (ILux.Token memory) {
    require(allowHatching, "Not allowed to Hatch");
    IDrop drop = IDrop(drops[dropID]);
    uint256 price = drop.nftPrice(NFTDrop[nftID]);
    require(lux.balanceOf(msg.sender) >= price, "Not enough LUX");
    require(unlocked, "Game is not unlocked yet");
    require(media.tokenExists(nftID), "NFT is burned or does not exist");
    require(media.ownerOf(nftID) == msg.sender, "Not owner of NFT");

    ILux.Token memory animal = getAnimal(dropID, nftID);
    animal.meta.nftID = nftID;
    animal.meta.dropID = dropID;
    animal.dropNFT = NFTDrop[nftID];

    animal = mint(msg.sender, animal);

    lux.transferFrom(msg.sender, address(this), price);

    burn(msg.sender, nftID);

    emit Hatch(msg.sender, nftID, animal.id);
    return animal;
  }


  function feedAnimal (uint256 animal, uint256 dropID) public {
    require(allowFeeding, "Not allowed to Feed");
    require(tokens[animal].kind != ILux.Type.BASE_NFT || tokens[animal].kind != ILux.Type.HYBRID_NFT, "token not animal");
    IDrop drop = IDrop(drops[dropID]);
    uint256 price = drop.nftPrice(tokens[animal].dropNFT);
    require(lux.balanceOf(msg.sender) >= price, "Not enough LUX");
    ILux.Token storage token = tokens[animal];

    if(tokens[animal].stage == ILux.AdultHood.BABY){
      token.stage = ILux.AdultHood.TEEN;
    }
    else if(tokens[animal].stage == ILux.AdultHood.TEEN){
      token.stage = ILux.AdultHood.ADULT;
    }
    feededTimes[tokens[animal].id].count += 1;
    feededTimes[tokens[animal].id].lastTimeFed = uint40(block.timestamp);
    IMedia.MediaData memory newData = drop.getAdultHoodURIs(token.name, token.stage);
    token.data = newData;
    media.updateTokenURI(token.id, newData.tokenURI);
    media.updateTokenMetadataURI(token.id, newData.metadataURI);
    lux.transferFrom(msg.sender, address(this), price);
    tokens[animal] = token;
  }

  modifier canBreed(uint256 parentA, uint256 parentB) {

    require(media.tokenExists(parentA) && media.tokenExists(parentB), "Non-existent token");
    require((media.ownerOf(parentA) == msg.sender && media.ownerOf(parentB) == msg.sender), "Not owner of Animals");
    require(keccak256(abi.encode(parentA)) != keccak256(abi.encode(parentB)), "Not able to breed with self");
    require(breedReady(parentA) && breedReady(parentB), "Wait for cooldown to finish.");
    require(tokens[parentA].breed.count <= 6 || tokens[parentA].breed.count <= 6, "reached max breed");
    require(isAnimalAdult(parentA) && isAnimalAdult(parentB), "Only Adult animals can breed.");
    require(keccak256(abi.encodePacked(tokens[parentA].name)) == keccak256(abi.encodePacked(tokens[parentB].name)), "Only same breed can be bred");
    _;
  }

  function breedAnimals(
    uint256 dropID,
    uint256 tokenA,
    uint256 tokenB
  ) public canBreed(tokenA, tokenB) returns (ILux.Token memory) {
    require(allowBreeding, "Not allowed to Breed");
    IDrop drop = IDrop(drops[dropID]);

    if(tokens[tokenA].dropNFT == drop.silverNFT() || tokens[tokenB].dropNFT == drop.silverNFT()){
      drop.changeRandomLimit(4);
    }

    ILux.Token memory nft = IDrop(drops[dropID]).newHybridNFT(ILux.Parents({ animalA: tokens[tokenA].name, animalB: tokens[tokenB].name, tokenA: tokenA, tokenB: tokenB }));

    uint256 price;

    if(drop.nftPrice(tokens[tokenA].dropNFT) > drop.nftPrice(tokens[tokenB].dropNFT)){
      price = drop.nftPrice(tokens[tokenA].dropNFT);
    }
    else{
      price = drop.nftPrice(tokens[tokenB].dropNFT);
    }

    require(lux.balanceOf(msg.sender) >= price, "Not enough LUX");

    lux.transferFrom(msg.sender, address(this), price);

    updateBreedDelays(tokenA, tokenB);

    nft = mint(msg.sender, nft);
    emit BreedAnimal(msg.sender, tokenA, tokenB, nft.id);
    drop.changeRandomLimit(3);
    return nft;
  }

  function freeAnimal(uint256 dropID, uint256 tokenID) public returns (uint256 yields) {

    ILux.Token storage token = tokens[tokenID];

    burn(msg.sender, tokenID);

    uint256 blockAge = block.timestamp - token.birthValues.timestamp;
    uint256 daysOld = blockAge.div(86000);

    if(token.stage == ILux.AdultHood.BABY){
      yields = daysOld.mul(ICustomDrop(drops[dropID]).animalStageYields(token.name).baby.yields.mul(10**18));
    }
    else if(token.stage == ILux.AdultHood.TEEN){
      daysOld.mul(ICustomDrop(drops[dropID]).animalStageYields(token.name).teen.yields.mul(10**18));
    } else{
      daysOld.mul(ICustomDrop(drops[dropID]).animalStageYields(token.name).adult.yields.mul(10**18));
    }

    lux.transfer(msg.sender, yields);

    emit Free(msg.sender, tokenID, yields);

    return yields;
  }

  function buyName(uint256 tokenID, string memory customName) public {
    require(lux.balanceOf(msg.sender) >= namePrice, "ZK: Not enough LUX to purchase Name");

    lux.transferFrom(msg.sender, address(this), namePrice);

    ILux.Token storage token = tokens[tokenID];
    token.customName = customName;
    tokens[tokenID] = token;
  }

   function isAnimalAdult(uint256 tokenID) private view returns (bool) {
    return tokens[tokenID].stage == ILux.AdultHood.ADULT;
  }

  function getAnimal(uint256 dropID, uint256 nftID) private view returns (ILux.Token memory) {

    ILux.Token storage nft = tokens[nftID];
    IDrop drop = IDrop(drops[dropID]);

    if (nft.kind == ILux.Type.BASE_NFT) {
      return drop.getRandomAnimal(drop.unsafeRandom(), nft.dropNFT);
    } else {
      return drop.getBredAnimal(tokens[nft.birthValues.parents.tokenA].name, nft.birthValues.parents);
    }
  }

  function updateBreedDelays(uint256 parentA, uint256 parentB) private {

    tokens[parentA].breed.count++;
    tokens[parentB].breed.count++;
    tokens[parentA].breed.timestamp = block.timestamp;
    tokens[parentB].breed.timestamp = block.timestamp;
  }

  function breedNext(uint256 tokenID) public view returns (uint256) {
    ILux.Token storage token = tokens[tokenID];
    return token.breed.timestamp + (token.breed.count * 1 days);
  }

  function breedReady(uint256 tokenID) public view returns (bool) {
    if (tokens[tokenID].breed.count == 0) {
      return true;
    }
    if (block.timestamp > breedNext(tokenID)) {
      return true;
    }

    return false;
  }


  function luxPriceBNB() public view returns (uint256) {
    (uint luxAmount, uint bnbAmount,) = pair.getReserves();
    return luxAmount / bnbAmount;
  }

  function supplyBNB() public view returns (uint256) {
    return lux.balanceOf(address(this));
  }

  function supplyLUX() public view returns (uint256) {
    return lux.balanceOf(address(this));
  }

  function withdrawBNB(address payable receiver, uint256 amount) public onlyOwner {
    require(receiver.send(amount));
  }

  function withdrawLUX(address receiver, uint256 amount) public onlyOwner {
    require(lux.transfer(receiver, amount));
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x, "Math overflow");
  }

  // Payable fallback functions
}
