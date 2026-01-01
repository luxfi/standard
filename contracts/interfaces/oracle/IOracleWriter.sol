// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IOracleWriter
/// @notice Interface for writing prices to the Oracle from off-chain sources
/// @dev Used by DEX gateway, keepers, and validator attestation network
interface IOracleWriter {
    /// @notice Price update with source metadata
    struct PriceUpdate {
        address asset;
        uint256 price;        // 18 decimals, USD
        uint256 timestamp;
        uint256 confidence;   // 0-10000 basis points
        bytes32 source;       // keccak256 of source name
    }

    /// @notice Signed price update from validator
    struct SignedPriceUpdate {
        PriceUpdate update;
        bytes signature;      // Validator signature
        address validator;    // Validator address
    }

    /// @notice Write a single price (requires WRITER_ROLE)
    /// @param asset Token address
    /// @param price Price with 18 decimals
    /// @param timestamp When price was observed
    function writePrice(address asset, uint256 price, uint256 timestamp) external;

    /// @notice Write multiple prices in batch (gas efficient)
    /// @param updates Array of price updates
    function writePrices(PriceUpdate[] calldata updates) external;

    /// @notice Write price with validator signature (trustless)
    /// @param update Signed price update
    function writeSignedPrice(SignedPriceUpdate calldata update) external;

    /// @notice Write prices with quorum of validator signatures
    /// @param updates Array of signed updates (same asset, multiple validators)
    /// @param minQuorum Minimum number of agreeing validators
    function writeQuorumPrice(SignedPriceUpdate[] calldata updates, uint256 minQuorum) external;

    /// @notice Check if address has writer role
    function isWriter(address account) external view returns (bool);

    /// @notice Check if validator is registered
    function isValidator(address validator) external view returns (bool);

    /// @notice Get required quorum for asset
    function getQuorum(address asset) external view returns (uint256);

    // Events
    event PriceWritten(address indexed asset, uint256 price, uint256 timestamp, bytes32 indexed source);
    event ValidatorPriceWritten(address indexed asset, uint256 price, address indexed validator);
    event QuorumPriceWritten(address indexed asset, uint256 price, uint256 validatorCount);
}
