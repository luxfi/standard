// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "../../FHE.sol";

/**
 * @title IConfidentialLRC721
 * @author Lux Industries Inc
 * @notice Interface for LRC721 NFTs with encrypted ownership
 * @dev Extends standard NFT functionality with FHE-encrypted ownership.
 *      Token ownership is encrypted - observers cannot see who owns which token.
 *
 * Privacy guarantees:
 * - Token ownership (ownerOf) is encrypted as eaddress
 * - Balance counts (balanceOf) are encrypted as euint64
 * - Transfers verify ownership via encrypted comparison
 * - Token existence and metadata are public
 *
 * Key differences from standard ERC721:
 * - ownerOf returns eaddress instead of address
 * - balanceOf returns euint64 instead of uint256
 * - Approvals work with encrypted ownership verification
 */
interface IConfidentialLRC721 {
    // ============================================================
    // EVENTS
    // ============================================================

    /**
     * @notice Emitted when a token is transferred
     * @param from Previous owner (or zero address for mints)
     * @param to New owner (or zero address for burns)
     * @param tokenId The token being transferred
     * @dev From/to are public for indexing; actual ownership is encrypted
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @notice Emitted when an approval is set
     * @param owner Token owner (public for indexing)
     * @param approved Approved address
     * @param tokenId Token ID
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @notice Emitted when operator approval is set
     * @param owner Token owner
     * @param operator Operator address
     * @param approved Whether approved
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ============================================================
    // ERRORS
    // ============================================================

    /// @notice The caller is not authorized (not owner or approved)
    error NotAuthorized();

    /// @notice The token does not exist
    error TokenNotFound(uint256 tokenId);

    /// @notice Invalid recipient (zero address)
    error InvalidRecipient();

    /// @notice Token already exists
    error TokenAlreadyExists(uint256 tokenId);

    /// @notice Approval to current owner
    error ApprovalToCurrentOwner();

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    /**
     * @notice Get the encrypted owner of a token
     * @param tokenId The token ID
     * @return owner Encrypted owner address
     * @dev Only the actual owner can decrypt this value via FHE.allow()
     */
    function ownerOf(uint256 tokenId) external view returns (eaddress owner);

    /**
     * @notice Get the encrypted balance of an address
     * @param owner The address to query
     * @return balance Encrypted balance (count of tokens owned)
     */
    function balanceOf(address owner) external view returns (euint64 balance);

    /**
     * @notice Get the approved address for a token
     * @param tokenId The token ID
     * @return approved The approved address (or zero if none)
     * @dev Approvals are public for gas efficiency
     */
    function getApproved(uint256 tokenId) external view returns (address approved);

    /**
     * @notice Check if an operator is approved for all tokens
     * @param owner Token owner
     * @param operator Operator address
     * @return isApproved Whether the operator is approved
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool isApproved);

    /**
     * @notice Get the token name
     * @return name Token name
     */
    function name() external view returns (string memory name);

    /**
     * @notice Get the token symbol
     * @return symbol Token symbol
     */
    function symbol() external view returns (string memory symbol);

    /**
     * @notice Get the total supply of tokens
     * @return totalSupply Total tokens minted (public for enumeration)
     */
    function totalSupply() external view returns (uint256 totalSupply);

    /**
     * @notice Check if a token exists
     * @param tokenId The token ID
     * @return exists Whether the token exists
     */
    function exists(uint256 tokenId) external view returns (bool exists);

    // ============================================================
    // TRANSFER FUNCTIONS
    // ============================================================

    /**
     * @notice Transfer a token (caller must be owner or approved)
     * @param to Recipient address
     * @param tokenId Token to transfer
     * @dev Uses encrypted ownership verification
     */
    function transferFrom(address to, uint256 tokenId) external;

    /**
     * @notice Safe transfer with receiver check
     * @param to Recipient address
     * @param tokenId Token to transfer
     */
    function safeTransferFrom(address to, uint256 tokenId) external;

    /**
     * @notice Safe transfer with data
     * @param to Recipient address
     * @param tokenId Token to transfer
     * @param data Additional data
     */
    function safeTransferFrom(address to, uint256 tokenId, bytes memory data) external;

    // ============================================================
    // APPROVAL FUNCTIONS
    // ============================================================

    /**
     * @notice Approve an address to transfer a specific token
     * @param approved Address to approve
     * @param tokenId Token to approve
     * @dev Caller must be owner (verified via encrypted comparison)
     */
    function approve(address approved, uint256 tokenId) external;

    /**
     * @notice Set operator approval for all tokens
     * @param operator Operator address
     * @param approved Whether to approve
     */
    function setApprovalForAll(address operator, bool approved) external;
}
