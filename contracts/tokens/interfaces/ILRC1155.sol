// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

/**
 * @title ILRC1155
 * @author Lux Network
 * @notice Lux Request for Comments 1155 - Multi-token interface
 * @dev Extends IERC1155 for full ERC-1155 compatibility while establishing Lux naming.
 *
 * LRC1155 tokens are fully ERC-1155 compatible. This interface exists to:
 * - Establish Lux-specific naming conventions
 * - Provide a base for future Lux-specific extensions
 * - Signal that the token follows Lux Network standards
 *
 * All LRC1155 implementations support standard ERC-1155 operations.
 */
interface ILRC1155 is IERC1155 {
    // Inherits all IERC1155 functions:
    // - balanceOf(address account, uint256 id) external view returns (uint256)
    // - balanceOfBatch(address[] calldata accounts, uint256[] calldata ids) external view returns (uint256[] memory)
    // - setApprovalForAll(address operator, bool approved) external
    // - isApprovedForAll(address account, address operator) external view returns (bool)
    // - safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external
    // - safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external
}

/**
 * @title ILRC1155MetadataURI
 * @notice LRC1155 with metadata URI extension
 */
interface ILRC1155MetadataURI is ILRC1155, IERC1155MetadataURI {
    // Inherits metadata function:
    // - uri(uint256 id) external view returns (string memory)
}
