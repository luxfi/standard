// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ConfidentialLRC721Mintable} from "../../../token/LRC721/extensions/ConfidentialLRC721Mintable.sol";

/**
 * @title TestConfidentialLRC721
 * @notice Test contract for ConfidentialLRC721Mintable
 */
contract TestConfidentialLRC721 is ConfidentialLRC721Mintable {
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        string memory baseURI_
    ) ConfidentialLRC721Mintable(name_, symbol_, owner_, baseURI_) {
        //
    }
}
