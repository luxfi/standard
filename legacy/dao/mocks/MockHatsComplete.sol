// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockHatsComplete
 * @dev Complete mock implementation of Hats Protocol for testing.
 * Provides all functionality needed for testing UtilityRolesManagementV1.
 */
contract MockHatsComplete {
    // Storage for hat details
    mapping(uint256 => string) public hatDetails;
    mapping(uint256 => string) public hatImageURIs;
    mapping(uint256 => uint32) public hatMaxSupply;
    mapping(uint256 => address) public hatEligibility;
    mapping(uint256 => address) public hatToggle;
    mapping(uint256 => bool) public hatMutable;
    mapping(address => mapping(uint256 => bool)) public isWearingHat;

    // Track last top hat ID for testing
    uint32 public lastTopHatId = 0;

    // Track next IDs for each hat
    mapping(uint256 => uint256) private nextIds;

    /**
     * @dev Mint a top hat to an address
     * @param _target The address to mint the top hat to
     * @param _details The details string for the hat
     * @param _imageURI The image URI for the hat
     * @return topHatId The ID of the minted top hat
     */
    function mintTopHat(
        address _target,
        string calldata _details,
        string calldata _imageURI
    ) external returns (uint256 topHatId) {
        lastTopHatId++;
        topHatId = uint256(lastTopHatId) << 224; // Top hat IDs have top 32 bits set

        isWearingHat[_target][topHatId] = true;
        hatDetails[topHatId] = _details;
        hatImageURIs[topHatId] = _imageURI;

        return topHatId;
    }

    /**
     * @dev Create a new hat under a parent hat
     * @param _parentId The parent hat ID
     * @param _details The details string for the hat
     * @param _maxSupply The maximum supply for the hat
     * @param _eligibility The eligibility module address
     * @param _toggle The toggle module address
     * @param _mutable Whether the hat is mutable
     * @param _imageURI The image URI for the hat
     * @return newHatId The ID of the created hat
     */
    function createHat(
        uint256 _parentId,
        string calldata _details,
        uint32 _maxSupply,
        address _eligibility,
        address _toggle,
        bool _mutable,
        string calldata _imageURI
    ) external returns (uint256 newHatId) {
        newHatId = getNextId(_parentId);

        hatDetails[newHatId] = _details;
        hatMaxSupply[newHatId] = _maxSupply;
        hatEligibility[newHatId] = _eligibility;
        hatToggle[newHatId] = _toggle;
        hatMutable[newHatId] = _mutable;
        hatImageURIs[newHatId] = _imageURI;

        nextIds[_parentId]++;

        return newHatId;
    }

    /**
     * @dev Mint a hat to an address
     * @param _hatId The hat ID to mint
     * @param _wearer The address to mint to
     * @return success Whether the mint was successful
     */
    function mintHat(
        uint256 _hatId,
        address _wearer
    ) external returns (bool success) {
        isWearingHat[_wearer][_hatId] = true;
        return true;
    }

    /**
     * @dev Get the next available ID for a parent hat
     * @param _parentId The parent hat ID
     * @return nextId The next available ID
     */
    function getNextId(uint256 _parentId) public view returns (uint256 nextId) {
        // Simplified logic for testing - always returns parent + nextIds[parent] + 1
        return _parentId + nextIds[_parentId] + 1;
    }

    /**
     * @dev Check if an address is wearing a specific hat
     * @param _wearer The address to check
     * @param _hatId The hat ID to check
     * @return bool Whether the address is wearing the hat
     */
    function isWearerOfHat(
        address _wearer,
        uint256 _hatId
    ) external view returns (bool) {
        return isWearingHat[_wearer][_hatId];
    }

    /**
     * @dev Set wearing status directly (for testing)
     * @param wearer The address to set status for
     * @param hatId The hat ID
     * @param isWearing Whether the address is wearing the hat
     */
    function setWearerStatus(
        address wearer,
        uint256 hatId,
        bool isWearing
    ) external {
        isWearingHat[wearer][hatId] = isWearing;
    }
}
