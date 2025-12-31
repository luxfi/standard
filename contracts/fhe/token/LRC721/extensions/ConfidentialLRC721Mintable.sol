// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ConfidentialLRC721} from "../ConfidentialLRC721.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title ConfidentialLRC721Mintable
 * @author Lux Industries Inc
 * @notice Mintable extension for ConfidentialLRC721
 * @dev Adds owner-controlled minting and burning with encrypted ownership
 */
abstract contract ConfidentialLRC721Mintable is ConfidentialLRC721, Ownable2Step {
    /// @notice Next token ID to mint
    uint256 private _nextTokenId;

    /// @notice Base URI for token metadata
    string private _baseTokenURI;

    /// @notice Token ID to URI mapping (for per-token URIs)
    mapping(uint256 tokenId => string uri) private _tokenURIs;

    // ============================================================
    // EVENTS
    // ============================================================

    event BaseURIUpdated(string oldURI, string newURI);

    // ============================================================
    // CONSTRUCTOR
    // ============================================================

    /**
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param owner_ Initial owner
     * @param baseURI_ Base URI for metadata
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        string memory baseURI_
    ) ConfidentialLRC721(name_, symbol_) Ownable(owner_) {
        _baseTokenURI = baseURI_;
    }

    // ============================================================
    // MINTING
    // ============================================================

    /**
     * @notice Mint a new token to an address
     * @param to Recipient address
     * @return tokenId The minted token ID
     */
    function mint(address to) public virtual onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Mint a new token with specific URI
     * @param to Recipient address
     * @param uri Token-specific URI
     * @return tokenId The minted token ID
     */
    function mintWithURI(address to, string memory uri) public virtual onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        _tokenURIs[tokenId] = uri;
        return tokenId;
    }

    /**
     * @notice Batch mint tokens to an address
     * @param to Recipient address
     * @param amount Number of tokens to mint
     * @return startTokenId First token ID minted
     */
    function mintBatch(address to, uint256 amount) public virtual onlyOwner returns (uint256) {
        uint256 startTokenId = _nextTokenId;
        for (uint256 i = 0; i < amount; i++) {
            _mint(to, _nextTokenId++);
        }
        return startTokenId;
    }

    // ============================================================
    // BURNING
    // ============================================================

    /**
     * @notice Burn a token (caller must own it)
     * @param tokenId Token to burn
     */
    function burn(uint256 tokenId) public virtual {
        _burn(tokenId);
        delete _tokenURIs[tokenId];
    }

    // ============================================================
    // URI FUNCTIONS
    // ============================================================

    /**
     * @notice Set the base URI for all tokens
     * @param baseURI_ New base URI
     */
    function setBaseURI(string memory baseURI_) public virtual onlyOwner {
        emit BaseURIUpdated(_baseTokenURI, baseURI_);
        _baseTokenURI = baseURI_;
    }

    /**
     * @notice Get the token URI
     * @param tokenId Token ID
     * @return uri Token URI
     */
    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        if (!exists(tokenId)) revert TokenNotFound(tokenId);

        // Check for token-specific URI
        string memory _tokenURI = _tokenURIs[tokenId];
        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }

        // Fall back to base URI + token ID
        return string(abi.encodePacked(_baseTokenURI, _toString(tokenId)));
    }

    /**
     * @notice Get the base URI
     * @return baseURI Base URI
     */
    function baseURI() public view virtual returns (string memory) {
        return _baseTokenURI;
    }

    // ============================================================
    // INTERNAL HELPERS
    // ============================================================

    /**
     * @dev Convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
