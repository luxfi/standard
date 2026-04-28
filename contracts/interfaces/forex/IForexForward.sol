// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title IForexForward
/// @author Lux Industries
/// @notice Interface for FX forward contracts
interface IForexForward {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    enum ForwardStatus {
        OPEN, // Created, awaiting counterparty
        ACTIVE, // Both parties deposited collateral
        SETTLED, // Exchanged at maturity
        CANCELLED, // Cancelled before activation
        DEFAULTED // Collateral liquidated due to insufficient margin
    }

    struct Forward {
        uint256 pairId; // FX pair ID
        address buyer; // Buys base at agreed rate
        address seller; // Sells base at agreed rate
        uint256 rate; // Agreed forward rate (18 decimals)
        uint256 baseAmount; // Amount of base currency
        uint256 maturityDate; // Settlement timestamp
        uint256 buyerCollateral; // Buyer's deposited collateral (in quote)
        uint256 sellerCollateral; // Seller's deposited collateral (in base)
        ForwardStatus status;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event ForwardCreated(
        uint256 indexed forwardId,
        uint256 indexed pairId,
        address indexed buyer,
        uint256 rate,
        uint256 baseAmount,
        uint256 maturityDate
    );
    event ForwardActivated(uint256 indexed forwardId, address indexed seller);
    event ForwardSettled(uint256 indexed forwardId, uint256 settlementRate, uint256 pnlBase, uint256 pnlQuote);
    event ForwardCancelled(uint256 indexed forwardId);
    event ForwardDefaulted(uint256 indexed forwardId, address indexed defaulter);
    event CollateralToppedUp(uint256 indexed forwardId, address indexed party, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ForwardNotFound();
    error ForwardNotOpen();
    error ForwardNotActive();
    error ForwardNotMature();
    error ForwardAlreadyActive();
    error InvalidMaturityDate();
    error InvalidRate();
    error InsufficientCollateral();
    error NotParty();
    error ZeroAmount();
    error ZeroAddress();

    // ═══════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Create a forward contract (buyer side)
    /// @param pairId The FX pair ID
    /// @param rate Agreed forward rate (18 decimals)
    /// @param baseAmount Amount of base currency
    /// @param maturityDate Settlement timestamp
    /// @return forwardId New forward ID
    function createForward(uint256 pairId, uint256 rate, uint256 baseAmount, uint256 maturityDate)
        external
        returns (uint256 forwardId);

    /// @notice Accept a forward as seller, depositing collateral
    /// @param forwardId The forward ID
    function acceptForward(uint256 forwardId) external;

    /// @notice Settle forward at maturity
    /// @param forwardId The forward ID
    function settleForward(uint256 forwardId) external;

    /// @notice Cancel an open (unmatched) forward
    /// @param forwardId The forward ID
    function cancelForward(uint256 forwardId) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get forward details
    function getForward(uint256 forwardId) external view returns (Forward memory);
}
