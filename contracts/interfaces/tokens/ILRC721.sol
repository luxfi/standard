// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @title ILRC721
 * @author Lux Network
 * @notice Lux Request for Comments 721 - Non-fungible token interface
 * @dev Extends IERC721 for full ERC-721 compatibility while establishing Lux naming.
 *
 * LRC721 tokens are fully ERC-721 compatible. This interface exists to:
 * - Establish Lux-specific naming conventions
 * - Provide a base for future Lux-specific extensions
 * - Signal that the token follows Lux Network standards
 *
 * All LRC721 implementations support standard ERC-721 operations.
 */
interface ILRC721 is IERC721 {
    // Inherits all IERC721 functions:
    // - balanceOf(address owner) external view returns (uint256)
    // - ownerOf(uint256 tokenId) external view returns (address)
    // - safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data)
    // - safeTransferFrom(address from, address to, uint256 tokenId)
    // - transferFrom(address from, address to, uint256 tokenId)
    // - approve(address to, uint256 tokenId)
    // - setApprovalForAll(address operator, bool approved)
    // - getApproved(uint256 tokenId) external view returns (address)
    // - isApprovedForAll(address owner, address operator) external view returns (bool)
}

/**
 * @title ILRC721Metadata
 * @notice LRC721 with metadata extension
 */
interface ILRC721Metadata is ILRC721, IERC721Metadata {
    // Inherits metadata functions:
    // - name() external view returns (string memory)
    // - symbol() external view returns (string memory)
    // - tokenURI(uint256 tokenId) external view returns (string memory)
}

/**
 * @title ILRC721Enumerable
 * @notice LRC721 with enumerable extension
 */
interface ILRC721Enumerable is ILRC721, IERC721Enumerable {
    // Inherits enumerable functions:
    // - totalSupply() external view returns (uint256)
    // - tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256)
    // - tokenByIndex(uint256 index) external view returns (uint256)
}
