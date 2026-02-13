// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {LockupLinear, Broker} from "../sablier/types/DataTypes.sol";

/**
 * @title IUtilityRolesManagementV1
 * @notice Unified interface for creating and managing organizational roles with Hats Protocol and Sablier streams
 * @dev This interface provides comprehensive functionality for managing "roles" - the combination
 * of Hats Protocol positions and their associated Sablier payment streams. It handles the complete
 * lifecycle of roles including creation, payment management, and stream administration.
 *
 * Key features:
 * - Create complete organizational structures from scratch
 * - Add new roles to existing Hats trees
 * - Set up payment streams for all roles
 * - Support for both termed (elected) and untermed positions
 * - Integration with autonomous admin for automated management
 *
 * Workflow for new trees:
 * 1. Safe calls createAndDeclareTree via delegatecall
 * 2. Utility creates top hat and mints to Safe
 * 3. Utility creates admin hat with autonomous admin
 * 4. Utility creates all role hats with configurations
 * 5. Utility sets up payment streams for each role
 *
 * Workflow for adding roles:
 * 1. Safe with existing hat tree calls createRoleHats via delegatecall
 * 2. Utility creates new role hats under existing admin
 * 3. Utility sets up payment streams for new roles
 * 4. Utility creates eligibility modules if needed
 *
 * Use cases:
 * - Initial DAO setup with complete role structure
 * - Creating new departments or teams within a DAO
 * - Adding new contributors to existing teams
 * - Setting up compensation structures
 * - Establishing governance hierarchies
 */
interface IUtilityRolesManagementV1 {
    // --- Errors ---

    /** @notice Thrown when autonomous admin proxy deployment via delegatecall fails */
    error ProxyDeploymentFailed();

    /** @notice Thrown when entry point functions are called directly instead of via delegatecall */
    error MustBeCalledViaDelegatecall();

    // --- Structs ---

    /**
     * @notice Parameters for creating the top hat
     * @param details IPFS hash or description of the top hat
     * @param imageURI IPFS hash or URL for the top hat's image
     */
    struct TopHatParams {
        string details;
        string imageURI;
    }

    /**
     * @notice Parameters for creating the admin hat
     * @param details IPFS hash or description of the admin hat
     * @param imageURI IPFS hash or URL for the admin hat's image
     * @param isMutable Whether the admin hat's properties can be changed
     * @param salt Salt for deterministic autonomous admin deployment
     */
    struct AdminHatParams {
        string details;
        string imageURI;
        bool isMutable;
    }

    /**
     * @notice Parameters for creating a Sablier payment stream
     * @param sablier The Sablier V2 LockupLinear contract address
     * @param sender The address funding the stream (usually the Safe)
     * @param asset The ERC20 token to stream
     * @param timestamps Start and cliff times for the stream
     * @param broker Fee configuration for stream creation
     * @param totalAmount Total tokens to stream over the duration
     * @param cancelable Whether the stream can be cancelled
     * @param transferable Whether the stream NFT can be transferred
     */
    struct SablierStreamParams {
        address sablier;
        address sender;
        address asset;
        LockupLinear.Timestamps timestamps;
        Broker broker;
        uint128 totalAmount;
        bool cancelable;
        bool transferable;
    }

    /**
     * @notice Parameters for creating a single Hat (role)
     * @param wearer Initial wearer of the Hat
     * @param details IPFS hash or description of the role
     * @param imageURI IPFS hash or URL for the Hat's image
     * @param sablierStreamsParams Array of payment streams for this role
     * @param termEndDateTs Term end timestamp (0 for untermed roles)
     * @param maxSupply Maximum number of this Hat that can exist
     * @param isMutable Whether the Hat's properties can be changed
     */
    struct HatParams {
        address wearer;
        string details;
        string imageURI;
        SablierStreamParams[] sablierStreamsParams;
        uint128 termEndDateTs;
        uint32 maxSupply;
        bool isMutable;
    }

    /**
     * @notice Parameters for creating multiple role Hats in one transaction
     * @param hatsProtocol The Hats Protocol contract address
     * @param erc6551Registry Registry for creating token-bound accounts
     * @param hatsAccountImplementation Implementation address for ERC6551 Hat accounts
     * @param topHatId The top Hat ID in the organization hierarchy
     * @param topHatWearer The account wearing the top Hat
     * @param keyValuePairs Contract address for emitting metadata about streams
     * @param hatsModuleFactory Factory address for creating Hats modules
     * @param hatsElectionsEligibilityImplementation Election module implementation address
     * @param adminHatId The Hat ID that will admin the new Hats
     * @param hats Array of Hat configurations to create
     */
    struct CreateRoleHatsParams {
        address hatsProtocol;
        address erc6551Registry;
        address hatsAccountImplementation;
        uint256 topHatId;
        address topHatWearer;
        address keyValuePairs;
        address hatsModuleFactory;
        address hatsElectionsEligibilityImplementation;
        uint256 adminHatId;
        HatParams[] hats;
    }

    /**
     * @notice Parameters for creating a complete Hats tree
     * @param keyValuePairs Address of the KeyValuePairs contract for metadata
     * @param hatsProtocol Address of the Hats Protocol contract
     * @param erc6551Registry Registry for creating token-bound accounts
     * @param hatsModuleFactory Factory for creating Hats modules
     * @param systemDeployer Deploys the autonomous admin
     * @param daoAutonomousAdminImplementation Implementation for autonomous admin
     * @param hatsAccountImplementation Implementation for Hat accounts
     * @param hatsElectionsEligibilityImplementation Elections module for termed roles
     * @param topHat Parameters for the top hat
     * @param adminHat Parameters for the admin hat
     * @param hats Array of role hats to create
     */
    struct CreateTreeParams {
        address keyValuePairs;
        address hatsProtocol;
        address erc6551Registry;
        address hatsModuleFactory;
        address systemDeployer;
        address daoAutonomousAdminImplementation;
        address hatsAccountImplementation;
        address hatsElectionsEligibilityImplementation;
        TopHatParams topHat;
        AdminHatParams adminHat;
        HatParams[] hats;
    }

    // --- State-Changing Functions ---

    /**
     * @notice Creates a complete Hats tree and declares it for the calling Safe
     * @dev This function:
     * - Creates and mints a top hat to the Safe
     * - Creates an admin hat with AutonomousAdmin as wearer
     * - Creates all specified role hats with payment streams
     * - Associates the tree with the Safe via KeyValuePairs
     *
     * Must be called via delegatecall from a Safe to ensure proper ownership.
     *
     * @param treeParams_ All parameters needed to create the tree
     * @custom:security Must be called via delegatecall from a Safe
     * @custom:security Safe must have sufficient token balances for streams
     * @custom:emits Updates KeyValuePairs with "topHatId" => topHatId
     */
    function createAndDeclareTree(
        CreateTreeParams calldata treeParams_
    ) external;

    /**
     * @notice Creates new role hats with payment streams in an existing tree
     * @dev This function assumes a hat tree already exists and adds new roles.
     * It handles:
     * - Creating new hats under the specified admin
     * - Setting up eligibility modules for termed positions
     * - Creating payment streams for compensation
     * - Minting hats to initial wearers
     *
     * Useful for expanding teams without creating a new tree.
     *
     * @param roleHatsParams_ Configuration for the new role hats to create
     * @custom:security Must be called via delegatecall from a Safe
     */
    function createRoleHats(
        CreateRoleHatsParams calldata roleHatsParams_
    ) external;

    // --- Sablier Stream Management Functions ---

    /**
     * @notice Withdraws the maximum available amount from a stream
     * @dev This function is designed for streams owned by Hat smart accounts.
     * It proxies the withdrawal call through the Hat account to the Sablier contract.
     * If no funds are available to withdraw, the function returns without reverting.
     *
     * Call flow:
     * 1. Safe (via delegatecall) -> Hat Account -> Sablier.withdrawMax()
     *
     * @param sablier_ The Sablier V2 contract address
     * @param recipientHatAccount_ The Hat account that owns the stream
     * @param streamId_ The ID of the stream to withdraw from
     * @param to_ The address to receive the withdrawn funds
     * @custom:security Must be called via delegatecall from a Safe
     * @custom:security Requires the Safe to have control over the Hat account
     */
    function withdrawMaxFromStream(
        address sablier_,
        address recipientHatAccount_,
        uint256 streamId_,
        address to_
    ) external;

    /**
     * @notice Cancels an active stream
     * @dev This function cancels a stream owned by the calling Safe.
     * Only works for streams in PENDING or STREAMING status.
     * Cancelled streams distribute remaining funds according to Sablier rules.
     * If the stream cannot be cancelled, the function returns without reverting.
     *
     * @param sablier_ The Sablier V2 contract address
     * @param streamId_ The ID of the stream to cancel
     * @custom:security Must be called via delegatecall from a Safe
     * @custom:security Only the stream sender (Safe) can cancel
     */
    function cancelStream(address sablier_, uint256 streamId_) external;
}
