// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract Faucet is Ownable {
    uint256 public rate = 10000;

    IERC20 token;

    event Fund(
        address indexed _address,
        uint256 indexed _amount
    );

    constructor(address luxAddress) Ownable(msg.sender) {
        token = IERC20(luxAddress);
    }

    function setTokenAddress(address _new) public onlyOwner {
        token = IERC20(_new);
    }

    function setRate(uint256 _rate) public onlyOwner {
        rate = _rate;
    }

    function fund(address to) public returns (uint256) {
        // uint256 amount = rate.mul(10**18);
        require(rate <= token.balanceOf(address(this)));
        token.transfer(to, rate);
        emit Fund(msg.sender, rate);
        return rate;
    }

    function withdraw() public onlyOwner {
        token.transfer(owner(), token.balanceOf(address(this)));
    }

    function balance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
