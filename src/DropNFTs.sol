// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IDrop } from "./interfaces/IDrop.sol";
import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { IDAO } from "./interfaces/IDAO.sol";

contract DropNFTs is Ownable {
    using SafeMath for uint256;

    using Counters for Counters.Counter;

    Counters.Counter public whitelistedCount;

    uint256 luxDAODropId;

    uint256 maxNFTForSublime;

    // Address of DLUX contract
    address public dluxAddress;

    address public dropAddress;

    mapping(address => uint256) private _whitelistedAllowToMint;
    mapping(uint => address) private whitelisted;

    constructor() {
        luxDAODropId = 1;
        maxNFTForSublime = 20;
    }

    function configureDropAddress(address drop) public onlyOwner {
        dropAddress = drop;
    }

    function configureDAOAddress(address dlux) public onlyOwner {
        dluxAddress = dlux;
    }

    function addressAllowedToMint(address _address) public view returns (uint) {
        return _whitelistedAllowToMint[_address];
    }


    function changeLuxdluxDropId(uint256 id) public onlyOwner {
        luxDAODropId = id;
    }


    function changeMaxNFTForSublime(uint256 max) public onlyOwner {
        maxNFTForSublime = max;
    }


    modifier airdropModifier (address[] memory addresses, uint256[] memory numAllowedToMint) {
        require(addresses.length > 0 && addresses.length == numAllowedToMint.length, "addresses and numAllowedToMint must be equal in length");
        uint256 i;
        uint totalNumberToMint;
        for (i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "An address is equal to 0x0"); // ensure no zero address
        }

        for (i = 0; i < numAllowedToMint.length; i++) {
            totalNumberToMint += numAllowedToMint[i];
        }
        require(totalNumberToMint != 0, "Amount to mint should not equal to zero");
        _;
    }

   function AirdropNFTs(address[] memory addresses, uint256[] memory numAllowedToMint) airdropModifier(addresses, numAllowedToMint) public onlyOwner {

        for (uint256 i = 0; i < addresses.length; i++) {
            _whitelistedAllowToMint[addresses[i]] = numAllowedToMint[i];
            whitelistedCount.increment();
            whitelisted[whitelistedCount.current()] = addresses[i];
        }

        IDAO dlux = IDAO(dluxAddress);
        IDrop drop = IDrop(dropAddress);

        for (uint256 i = 0; i < addresses.length; i++){
            address buyerAddress = addresses[i];
                require(_whitelistedAllowToMint[buyerAddress] != 0, "Can not mint 0 token");
                if(_whitelistedAllowToMint[buyerAddress] >= maxNFTForSublime){
                    drop.changeRandomLimit(4);
                }
                for (uint256 j = 0; j < _whitelistedAllowToMint[buyerAddress]; j++){
                    require(buyerAddress != address(0), "An address is equal to 0x0");
                    uint256 randomNFT = drop.unsafeRandom();
                    uint256 Id;
                    IDrop.NFT memory nft;

                    if(randomNFT > 0) {
                        nft = drop.getNFT(randomNFT);
                        Id = randomNFT;
                    } else {
                        nft = drop.getNFT(1);
                        Id = 1;
                    }
                    require(nft.minted <= nft.supply, "STOCK_EXCEEDED");
                    dlux.dropNFTs(Id, luxDAODropId, buyerAddress);
                }
                drop.changeRandomLimit(3);

        }

    }
}
