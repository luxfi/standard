// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";

contract DAO is Ownable {
    address public treasury;
    
    constructor() {
        treasury = msg.sender;
    }
    
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}