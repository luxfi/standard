// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

interface IComplianceGate {
    error NotCompliant(address user);
    error NotAccredited(address user);
    error CountryBlocked(address user, uint16 country);
    error InvalidRegistry();
    error SeriesNotFound(uint256 seriesId);

    event IdentityRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event AccreditedOnlySet(uint256 indexed seriesId, bool required);
    event CountryBlockSet(uint16 indexed country, bool blocked);
    event AccreditationTopicSet(uint256 topic);

    function writeCompliant(uint256 seriesId, uint256 amount, address recipient)
        external
        returns (uint256 collateralRequired);

    function exerciseCompliant(uint256 seriesId, uint256 amount) external returns (uint256 payout);

    function setIdentityRegistry(address registry) external;
    function setAccreditedOnly(uint256 seriesId, bool required) external;
    function setCountryBlock(uint16 country, bool blocked) external;
    function setAccreditationTopic(uint256 topic) external;

    function isCompliantForSeries(address user, uint256 seriesId) external view returns (bool);
    function identityRegistry() external view returns (address);
    function accreditedOnly(uint256 seriesId) external view returns (bool);
}
