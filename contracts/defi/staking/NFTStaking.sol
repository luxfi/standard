// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../interfaces/I721Stake.sol";
import "@solmate/auth/Owned.sol";

contract LuxNFTStaker is Owned, I721Stake {
    using SafeMath for uint256;
	using SafeMath for uint40;
    bool stakeLive;
    uint256 public totalStakers;

    uint40 public minumTime;
    uint40 public mediumTime;
    uint40 public maximumTime;
    uint40 public timestampSeconds;

    struct Percentage {
        bool valid;
        uint256 amount;
    }

    mapping(uint256 => Percentage) public percentage;

    IERC20 public RewardCoin;

    mapping(address => Staker) public stakers;
    mapping (address => bool) public frozenStaker;
    mapping(address => mapping (uint => bool)) public frozenNft;

    function updateMinumTime(uint40 _new) public onlyOwner{
        minumTime = _new;
    }

    function updateMediumTime(uint40 _new) public onlyOwner{
        mediumTime = _new;
    }

    function updateTimeStampSeconds(uint40 _new) public onlyOwner{
        timestampSeconds = _new;
    }

    function updatemMaximumTime(uint40 _new) public onlyOwner{
        maximumTime = _new;
    }

    function updatePercentage(uint256 percentageLevel, uint256 amount) public onlyOwner{
        require(percentage[percentageLevel].valid, "percentage not active");
        percentage[percentageLevel].amount = amount;
    }

    function freezeStaker(address target, bool freeze) onlyOwner public {
        frozenStaker[target] = freeze;
    }

     function toggleStakeStatus() onlyOwner public {
        stakeLive = !stakeLive;
    }

    function freezeNft(address NftContract, uint256 _tokenId,  bool freeze) onlyOwner override public {
        frozenNft[NftContract][_tokenId] = freeze;
    }

    function isFrozenStaker(address _addr) public view  override returns (bool) {
        return frozenStaker[_addr];
    }

    function isFrozenNft(address NftContract, uint256 _tokenId) public override view returns (bool) {
        return frozenNft[NftContract][_tokenId];
    }


    constructor(address _rewardCoin) Owned(msg.sender) {
        require(isContract(_rewardCoin), "Reward coin not contract");
        RewardCoin = IERC20(_rewardCoin);
        minumTime = 30;
        mediumTime = 90;
        maximumTime = 180;
        timestampSeconds = 86400;
        percentage[1].valid = true;
        percentage[1].amount = 100;
        percentage[2].valid = true;
        percentage[2].amount = 200;
        percentage[3].valid = true;
        percentage[3].amount = 300;
    }

    modifier stakingModifier (address NftContract, uint256 _tokenId){
        require(!isFrozenStaker(msg.sender), "Caller Not allowed to stake");
        require(!isFrozenNft(NftContract, _tokenId), "NFT Not allowed to be staked");
        require(IERC721(NftContract).balanceOf(msg.sender) > 0, "Caller does't own the token");
        _;
    }

    function stake(address NftContract, uint256 _tokenId) stakingModifier(NftContract, _tokenId) override external {
        require(stakeLive, "Staking is not live");
        _stake(NftContract, _tokenId);
        emit NewStake(msg.sender, NftContract, _tokenId);
    }

    function _stake(address NftContract, uint256 _tokenId) internal {
        Staker storage staker = stakers[msg.sender];

        staker.tokens[NftContract][_tokenId].staked = true;

        staker.tokens[NftContract][_tokenId].period.push(StakingTime({
            time: uint40(block.timestamp)
        }));

        IERC721(NftContract).safeTransferFrom(msg.sender, address(this), _tokenId);

        emit NewStake(msg.sender, NftContract, _tokenId);
    }

    function unstake(address NftContract, uint256 _tokenId)  stakingModifier(NftContract, _tokenId) override public {
       _unstake(NftContract, _tokenId);
       emit unStaked(msg.sender, NftContract, _tokenId);
    } 

    function rewardAmount(address _addr, address NftContract, uint256 _tokenId) view external override returns(uint256[] memory) {
        Staker storage staker = stakers[_addr];

        uint256[] memory rewardValues = new uint256[](2);

        uint256 value = 0;
        uint256 totalDaysStaked = 0;
        
        for(uint256 i = 0; i < staker.tokens[NftContract][_tokenId].period.length; i++) {
            StakingTime storage StakingTimeInstance = staker.tokens[NftContract][_tokenId].period[i];
            uint daysStaked = (uint40(block.timestamp) - StakingTimeInstance.time) / timestampSeconds;
            if((daysStaked >= minumTime && daysStaked < mediumTime)){
                value += percentage[1].amount;
            }
            else if(daysStaked >= mediumTime && daysStaked < maximumTime){
                value += percentage[2].amount;
            }
            else if(daysStaked >= maximumTime){
                value += percentage[3].amount;
            }
            else{
                value += 0;
            }
            
            totalDaysStaked += daysStaked;

        }

        rewardValues[0] = value;
        rewardValues[1] = totalDaysStaked;

        return (rewardValues);
    }

    function _unstake(address NftContract, uint256 _tokenId) public {
       uint256[] memory rewardValues = this.rewardAmount(msg.sender, NftContract, _tokenId);
       require(rewardValues[1] > minumTime, "Not yet allowed to withdraw");
       IERC721(NftContract).safeTransferFrom(address(this), msg.sender, _tokenId);
       RewardCoin.transferFrom(owner, msg.sender, rewardValues[0]);
    }


    function updateRewardCoin(address _newRewardCoin) public override onlyOwner {
        RewardCoin = IERC20(_newRewardCoin);
    }    

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

     function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

}