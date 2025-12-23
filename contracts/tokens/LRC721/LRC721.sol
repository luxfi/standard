// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

import "@luxfi/standard/lib/token/ERC721/ERC721.sol";
import "@luxfi/standard/lib/token/ERC721/extensions/ERC721Enumerable.sol";
import "@luxfi/standard/lib/token/ERC721/extensions/ERC721URIStorage.sol";
import "@luxfi/standard/lib/token/ERC721/extensions/ERC721Pausable.sol";
import "@luxfi/standard/lib/token/ERC721/extensions/ERC721Burnable.sol";
import "@luxfi/standard/lib/token/ERC721/extensions/ERC721Royalty.sol";
import "@luxfi/standard/lib/access/AccessControl.sol";

/**
 * @title LRC721
 * @author Lux Network
 * @notice Lux Request for Comments 721 - Full-featured NFT standard
 * @dev Extends OpenZeppelin ERC721 with all major extensions:
 * - Enumerable: On-chain token enumeration
 * - URIStorage: Flexible token URI storage
 * - Pausable: Emergency pause functionality
 * - Burnable: Token burning capability
 * - Royalty: EIP-2981 royalty support
 * - AccessControl: Role-based permissions
 */
contract LRC721 is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Pausable,
    ERC721Burnable,
    ERC721Royalty,
    AccessControl
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ROYALTY_ADMIN_ROLE = keccak256("ROYALTY_ADMIN_ROLE");

    uint256 private _nextTokenId;
    string private _baseTokenURI;

    event BaseURIUpdated(string oldURI, string newURI);
    event DefaultRoyaltySet(address receiver, uint96 feeNumerator);

    /**
     * @notice Constructor for LRC721 token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param baseURI_ Base URI for token metadata
     * @param royaltyReceiver Address to receive royalties
     * @param royaltyBps Royalty fee in basis points (e.g., 250 = 2.5%)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address royaltyReceiver,
        uint96 royaltyBps
    ) ERC721(name_, symbol_) {
        _baseTokenURI = baseURI_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(ROYALTY_ADMIN_ROLE, msg.sender);

        if (royaltyReceiver != address(0) && royaltyBps > 0) {
            _setDefaultRoyalty(royaltyReceiver, royaltyBps);
        }
    }

    /**
     * @notice Mint a new token
     * @param to Recipient address
     * @param uri Token-specific URI (optional, can be empty to use base URI)
     * @return tokenId The ID of the minted token
     */
    function safeMint(address to, string memory uri) public onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        if (bytes(uri).length > 0) {
            _setTokenURI(tokenId, uri);
        }
        return tokenId;
    }

    /**
     * @notice Batch mint tokens
     * @param to Recipient address
     * @param amount Number of tokens to mint
     * @return startTokenId First token ID minted
     */
    function safeMintBatch(address to, uint256 amount) public onlyRole(MINTER_ROLE) returns (uint256) {
        uint256 startTokenId = _nextTokenId;
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(to, _nextTokenId++);
        }
        return startTokenId;
    }

    /**
     * @notice Set base URI for all tokens
     */
    function setBaseURI(string memory baseURI_) public onlyRole(DEFAULT_ADMIN_ROLE) {
        emit BaseURIUpdated(_baseTokenURI, baseURI_);
        _baseTokenURI = baseURI_;
    }

    /**
     * @notice Set default royalty for all tokens
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyRole(ROYALTY_ADMIN_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    /**
     * @notice Set token-specific royalty
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyRole(ROYALTY_ADMIN_ROLE) {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    // ============ Required Overrides ============

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Royalty, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
