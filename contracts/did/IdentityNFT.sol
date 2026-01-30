// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IdentityNFT
 * @author Lux Industries Inc
 * @notice ERC721 NFT bound to DID identities
 * @dev Each DID (did:lux:alice) is represented by an NFT
 *
 * The NFT serves as:
 * - Proof of identity ownership
 * - Transferable identity (can sell/transfer your DID)
 * - Visual representation in wallets
 */
contract IdentityNFT is ERC721, Ownable {
    uint256 private _tokenIdCounter;
    address public registry;

    string public baseURI;

    event RegistryUpdated(address indexed newRegistry);
    event BaseURIUpdated(string newBaseURI);

    error OnlyRegistry();
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC721(name_, symbol_) Ownable(owner_) {
        _tokenIdCounter = 1; // Start from 1
    }

    modifier onlyRegistry() {
        if (msg.sender != registry) revert OnlyRegistry();
        _;
    }

    /**
     * @notice Set the registry address (DID Registry contract)
     */
    function setRegistry(address registry_) external onlyOwner {
        if (registry_ == address(0)) revert ZeroAddress();
        registry = registry_;
        emit RegistryUpdated(registry_);
    }

    /**
     * @notice Set base URI for token metadata
     */
    function setBaseURI(string calldata baseURI_) external onlyOwner {
        baseURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    /**
     * @notice Mint a new identity NFT
     * @dev Only callable by the registry
     */
    function mint(address to) external onlyRegistry returns (uint256) {
        if (to == address(0)) revert ZeroAddress();

        uint256 tokenId = _tokenIdCounter++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @notice Burn an identity NFT
     * @dev Only callable by registry (when identity is unclaimed)
     */
    function burn(uint256 tokenId) external onlyRegistry {
        _burn(tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
