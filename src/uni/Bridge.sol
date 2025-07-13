// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Bridge is Ownable {
    address public dao;
    uint256 public fee;
    
    constructor(address _dao, uint256 _fee) {
        dao = _dao;
        fee = _fee;
    }
    
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }
    
    function setDao(address _dao) external onlyOwner {
        dao = _dao;
    }
}