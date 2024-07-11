// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BNB is ERC20 {
    constructor () ERC20("BNB", "BNB") {}

    function mint(address to, uint256 value) public {
        super._mint(to, value);
    }
}
