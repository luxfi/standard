// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

/**
 * NOTE: This file is a clone of the OpenZeppelin ERC721.sol contract. It was forked from https://github.com/OpenZeppelin/openzeppelin-contracts
 * at commit 1ada3b633e5bfd9d4ffe0207d64773a11f5a7c40
 *
 * The code was modified to inherit from our customized ERC721 contract.
*/

import "./ERC721.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title ERC721 Burnable Token
 * @dev ERC721 Token that can be irreversibly burned (destroyed).
 */
abstract contract ERC721Burnable is Context, ERC721 {
    /**
     * @dev Burns `tokenID`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenID` or be an approved operator.
     */
    function burn(uint256 tokenID) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenID), "ERC721Burnable: caller is not owner nor approved");
        _burn(tokenID);
    }
}
