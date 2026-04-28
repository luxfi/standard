// SPDX-License-Identifier: MIT
// Lux Standard Library — Securities Module
//
// Originally based on Arca Labs ST-Contracts (https://github.com/arcalabs/st-contracts)
// Updated to Solidity ^0.8.24 with OpenZeppelin v5 by the Hanzo AI team
//
// Copyright (c) 2026 Lux Partners Limited — https://lux.network
// Copyright (c) 2019 Arca Labs Inc — https://arca.digital
pragma solidity ^0.8.24;

import { AccessControl } from "@luxfi/oz/access/AccessControl.sol";

/**
 * @title DocumentRegistry
 * @notice On-chain document storage for security tokens.
 *
 * Implements document management per ERC-1643 (Document Management Standard).
 * Stores document URIs and content hashes on-chain for regulatory compliance.
 */
contract DocumentRegistry is AccessControl {
    bytes32 public constant DOCUMENT_ADMIN_ROLE = keccak256("DOCUMENT_ADMIN_ROLE");

    struct Document {
        string uri;
        bytes32 documentHash;
        uint256 lastModified;
    }

    /// @notice document name => Document
    mapping(bytes32 => Document) private _documents;

    /// @notice Ordered list of document names.
    bytes32[] private _documentNames;
    mapping(bytes32 => bool) private _documentExists;

    // ──────────────────────────────────────────────────────────────────────────
    // Events (per ERC-1643)
    // ──────────────────────────────────────────────────────────────────────────

    event DocumentUpdated(bytes32 indexed name, string uri, bytes32 documentHash);
    event DocumentRemoved(bytes32 indexed name);

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error EmptyURI();
    error DocumentNotFound(bytes32 name);

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DOCUMENT_ADMIN_ROLE, admin);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Document management
    // ──────────────────────────────────────────────────────────────────────────

    /**
     * @notice Set or update a document.
     * @param name         Document identifier (e.g., keccak256("PROSPECTUS"))
     * @param uri          URI pointing to the document (IPFS, HTTPS, etc.)
     * @param documentHash Content hash for integrity verification
     */
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash)
        external
        onlyRole(DOCUMENT_ADMIN_ROLE)
    {
        if (bytes(uri).length == 0) revert EmptyURI();

        if (!_documentExists[name]) {
            _documentExists[name] = true;
            _documentNames.push(name);
        }

        _documents[name] = Document({ uri: uri, documentHash: documentHash, lastModified: block.timestamp });

        emit DocumentUpdated(name, uri, documentHash);
    }

    /**
     * @notice Remove a document.
     */
    function removeDocument(bytes32 name) external onlyRole(DOCUMENT_ADMIN_ROLE) {
        if (!_documentExists[name]) revert DocumentNotFound(name);

        delete _documents[name];
        _documentExists[name] = false;

        // Remove from names array
        uint256 len = _documentNames.length;
        for (uint256 i; i < len; ++i) {
            if (_documentNames[i] == name) {
                _documentNames[i] = _documentNames[len - 1];
                _documentNames.pop();
                break;
            }
        }

        emit DocumentRemoved(name);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Queries
    // ──────────────────────────────────────────────────────────────────────────

    function getDocument(bytes32 name)
        external
        view
        returns (string memory uri, bytes32 documentHash, uint256 lastModified)
    {
        if (!_documentExists[name]) revert DocumentNotFound(name);
        Document storage doc = _documents[name];
        return (doc.uri, doc.documentHash, doc.lastModified);
    }

    function getAllDocumentNames() external view returns (bytes32[] memory) {
        return _documentNames;
    }

    function documentCount() external view returns (uint256) {
        return _documentNames.length;
    }
}
