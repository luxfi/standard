// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

/**
    ██╗     ██████╗  ██████╗ ██╗ ██╗███████╗███████╗██████╗
    ██║     ██╔══██╗██╔════╝███║███║██╔════╝██╔════╝██╔══██╗
    ██║     ██████╔╝██║     ╚██║╚██║███████╗███████╗██████╔╝
    ██║     ██╔══██╗██║      ██║ ██║╚════██║╚════██║██╔══██╗
    ███████╗██║  ██║╚██████╗ ██║ ██║███████║███████║██████╔╝
    ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝╚══════╝╚═════╝

    LRC1155B - Bridge-compatible multi-token base using LRC1155 standards
 */

import {LRC1155} from "./LRC1155/LRC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LRC1155B
 * @notice Bridge-compatible multi-token base contract
 * @dev Extends LRC1155 with bridge mint/burn capabilities for cross-chain transfers
 */
contract LRC1155B is LRC1155, Ownable {
    event BridgeMint(address indexed to, uint256 indexed id, uint256 amount);
    event BridgeBurn(address indexed from, uint256 indexed id, uint256 amount);
    event BridgeMintBatch(address indexed to, uint256[] ids, uint256[] amounts);
    event BridgeBurnBatch(address indexed from, uint256[] ids, uint256[] amounts);

    /**
     * @notice Constructor for bridge multi-token
     * @param name_ Collection name
     * @param symbol_ Collection symbol
     * @param baseURI_ Base URI for metadata
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    )
        LRC1155(name_, symbol_, baseURI_, address(0), 0)
        Ownable(msg.sender)
    {
        // Grant bridge admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @notice Bridge mint - mint tokens from cross-chain transfer
     * @param to Recipient address
     * @param id Token ID
     * @param amount Amount to mint
     */
    function bridgeMint(address to, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, "");
        emit BridgeMint(to, id, amount);
    }

    /**
     * @notice Bridge burn - burn tokens for cross-chain transfer
     * @param from Token holder address
     * @param id Token ID
     * @param amount Amount to burn
     */
    function bridgeBurn(address from, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, id, amount);
        emit BridgeBurn(from, id, amount);
    }

    /**
     * @notice Batch bridge mint
     * @param to Recipient address
     * @param ids Array of token IDs
     * @param amounts Array of amounts
     */
    function bridgeMintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, "");
        emit BridgeMintBatch(to, ids, amounts);
    }

    /**
     * @notice Batch bridge burn
     * @param from Token holder address
     * @param ids Array of token IDs
     * @param amounts Array of amounts
     */
    function bridgeBurnBatch(
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) {
        _burnBatch(from, ids, amounts);
        emit BridgeBurnBatch(from, ids, amounts);
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
     * @dev Override supportsInterface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(LRC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
