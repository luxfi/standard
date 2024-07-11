// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

interface I721Stake {

    struct StakingTime {
        uint40 time;
    }

    struct Token {
        bool staked;
        StakingTime[] period;
    }

    struct Staker {
        uint256 dividend_amount;
        uint40 last_payout;
        mapping(address => mapping(uint256 => Token)) tokens;
    }
    
    event NewStake(address indexed addr, address NFTContract, uint256 tokenId);
    event unStaked(address indexed addr, address NFTContract, uint256 tokenId);

    function freezeNft(address NftContract, uint256 _tokenId,  bool freeze) external;
    function isFrozenStaker(address _addr) external view returns (bool);
    function isFrozenNft(address NftContract, uint256 _tokenId) external view returns (bool);
    function stake(address NftContract, uint256 _tokenId) external;
    function unstake(address NftContract, uint256 _tokenId) external;
    function rewardAmount(address _addr, address NftContract, uint256 _tokenId) view external returns(uint256[] memory);
    function updateRewardCoin(address _newRewardCoin) external; 
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data) external returns (bytes4);
}