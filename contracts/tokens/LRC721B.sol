// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

/**
    ██╗     ██████╗  ██████╗███████╗██████╗  ██╗██████╗
    ██║     ██╔══██╗██╔════╝╚════██║╚════██╗███║██╔══██╗
    ██║     ██████╔╝██║         ██╔╝ █████╔╝╚██║██████╔╝
    ██║     ██╔══██╗██║        ██╔╝ ██╔═══╝  ██║██╔══██╗
    ███████╗██║  ██║╚██████╗   ██║  ███████╗ ██║██████╔╝
    ╚══════╝╚═╝  ╚═╝ ╚═════╝   ╚═╝  ╚══════╝ ╚═╝╚═════╝

    LRC721B - Bridge-compatible NFT base using LRC721 standards
 */

import {LRC721} from "./LRC721/LRC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title LRC721B
 * @notice Bridge-compatible NFT base contract
 * @dev Extends LRC721 with bridge mint/burn capabilities for cross-chain NFT transfers
 */
contract LRC721B is LRC721, Ownable {
    event BridgeMint(address indexed to, uint256 indexed tokenId);
    event BridgeBurn(address indexed from, uint256 indexed tokenId);

    /**
     * @notice Constructor for bridge NFT
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param baseURI_ Base URI for metadata
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) 
        LRC721(name_, symbol_, baseURI_, address(0), 0)
        Ownable(msg.sender) 
    {
        // Grant bridge admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @notice Bridge mint - mint NFT with specific tokenId from cross-chain transfer
     * @param to Recipient address
     * @param tokenId Token ID to mint
     */
    function bridgeMint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
        emit BridgeMint(to, tokenId);
    }

    /**
     * @notice Bridge burn - burn NFT for cross-chain transfer
     * @param tokenId Token ID to burn
     */
    function bridgeBurn(uint256 tokenId) external onlyRole(MINTER_ROLE) {
        address owner = ownerOf(tokenId);
        _burn(tokenId);
        emit BridgeBurn(owner, tokenId);
    }

    /**
     * @notice Batch bridge mint
     * @param to Recipient address
     * @param tokenIds Array of token IDs to mint
     */
    function bridgeMintBatch(address to, uint256[] calldata tokenIds) external onlyRole(MINTER_ROLE) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _safeMint(to, tokenIds[i]);
            emit BridgeMint(to, tokenIds[i]);
        }
    }

    /**
     * @notice Grant bridge operator role
     * @param operator Address to grant role to
     */
    function grantBridgeOperator(address operator) external onlyOwner {
        _grantRole(MINTER_ROLE, operator);
    }

    /**
     * @notice Revoke bridge operator role
     * @param operator Address to revoke role from
     */
    function revokeBridgeOperator(address operator) external onlyOwner {
        _revokeRole(MINTER_ROLE, operator);
    }

    /**
     * @notice Check if address is bridge operator
     * @param operator Address to check
     * @return bool True if operator has bridge role
     */
    function isBridgeOperator(address operator) external view returns (bool) {
        return hasRole(MINTER_ROLE, operator);
    }

    /**
     * @dev Override supportsInterface to include Ownable
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(LRC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
