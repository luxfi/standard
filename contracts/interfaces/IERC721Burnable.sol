// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

interface IERC721Burnable is IERC721 {
    function burn(uint256 _amount) external;
}
