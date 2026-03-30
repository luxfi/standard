// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title IComplianceGate
 * @author Lux Industries
 * @notice Interface for KYC/AML compliance wrapper around options operations
 * @dev Gates all options operations through a ComplianceRegistry check
 */
interface IComplianceGate {
    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when user is not compliant (not whitelisted or blacklisted)
    error NotCompliant(address user);

    /// @notice Thrown when user is not accredited for a restricted series
    error NotAccredited(address user);

    /// @notice Thrown when user's jurisdiction is blocked
    error JurisdictionBlocked(address user, bytes2 jurisdiction);

    /// @notice Thrown when compliance registry address is zero
    error InvalidRegistry();

    /// @notice Thrown when series does not exist
    error SeriesNotFound(uint256 seriesId);

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Emitted when the compliance registry is updated
    event ComplianceRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when accredited-only restriction is toggled for a series
    event AccreditedOnlySet(uint256 indexed seriesId, bool required);

    /// @notice Emitted when a jurisdiction is blocked or unblocked
    event JurisdictionBlockSet(bytes2 indexed jurisdiction, bool blocked);

    // ═══════════════════════════════════════════════════════════════════════
    // GATED OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Write options with compliance checks
     * @param seriesId Option series ID
     * @param amount Number of options to write
     * @param recipient Recipient of option tokens (must also be compliant)
     * @return collateralRequired Collateral locked
     */
    function writeCompliant(uint256 seriesId, uint256 amount, address recipient)
        external
        returns (uint256 collateralRequired);

    /**
     * @notice Exercise options with compliance checks
     * @param seriesId Option series ID
     * @param amount Number of options to exercise
     * @return payout Payout amount
     */
    function exerciseCompliant(uint256 seriesId, uint256 amount) external returns (uint256 payout);

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Update the compliance registry address
     * @param registry New compliance registry
     */
    function setComplianceRegistry(address registry) external;

    /**
     * @notice Set whether a series requires accredited investor status
     * @param seriesId Option series ID
     * @param required True to require accreditation
     */
    function setAccreditedOnly(uint256 seriesId, bool required) external;

    /**
     * @notice Block or unblock a jurisdiction
     * @param jurisdiction ISO 3166-1 alpha-2 country code
     * @param blocked True to block
     */
    function setJurisdictionBlock(bytes2 jurisdiction, bool blocked) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if a user is compliant for a given series
     * @param user User address
     * @param seriesId Series ID
     * @return compliant True if user can trade this series
     */
    function isCompliantForSeries(address user, uint256 seriesId) external view returns (bool compliant);

    /**
     * @notice Get the compliance registry address
     * @return registry Current compliance registry
     */
    function complianceRegistry() external view returns (address registry);

    /**
     * @notice Check if a series requires accredited status
     * @param seriesId Series ID
     * @return required True if accreditation is required
     */
    function accreditedOnly(uint256 seriesId) external view returns (bool required);
}
