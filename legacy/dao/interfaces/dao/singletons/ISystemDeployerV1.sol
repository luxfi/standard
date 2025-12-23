// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IVotesERC20V1} from "../deployables/IVotesERC20V1.sol";

/**
 * @title ISystemDeployerV1
 * @notice Singleton contract for orchestrating complete DAO system deployments
 * @dev This contract is deployed once per chain and provides a comprehensive deployment
 * system for DAO Protocol DAOs. It handles the complex initialization sequence
 * required for circular dependencies between contracts and ensures proper configuration.
 *
 * Key features:
 * - One-transaction deployment of complete DAO systems
 * - Handles circular dependency resolution (Azorius ↔ Strategy ↔ VotingConfigs)
 * - Deploys and configures all governance components
 * - Supports multiple governance token deployments
 * - Configures freeze mechanisms for parent-child DAO relationships
 * - Uses CREATE2 for deterministic proxy addresses
 *
 * Deployment orchestration:
 * 1. Deploys governance tokens (VotesERC20V1)
 * 2. Deploys proposer adapters for proposal creation rules
 * 3. Deploys strategy with initial configuration
 * 4. Deploys voting adapters for vote counting
 * 5. Deploys Azorius module as the main governance system
 * 6. Completes strategy initialization with Azorius and voting adapters
 * 7. Optionally deploys freeze mechanisms for parent DAO control
 *
 * Security:
 * - Must be called through delegatecall from Safe during setup
 * - Direct calls to deployProxy will revert with MustBeCalledViaDelegatecall
 * - Validates all implementation addresses before deployment
 * - Ensures proper initialization of all components
 * - Gracefully handles existing contracts at predicted addresses
 */
interface ISystemDeployerV1 {
    // --- Errors ---

    /** @notice Thrown when attempting to deploy a proxy with a non-contract implementation */
    error ImplementationMustBeAContract();

    /** @notice Thrown when deployProxy is called directly instead of via delegatecall */
    error MustBeCalledViaDelegatecall();

    /** @notice Thrown when referencing a governance token that wasn't deployed */
    error VotesERC20V1NotFoundAtIndex(uint256 tokenIndex);

    /** @notice Thrown when attempting to deploy multiple freeze voting contracts */
    error CannotDeployMultipleFreezeVotingContracts();

    /** @notice Thrown when freeze guard references a freeze voting contract that wasn't deployed */
    error FreezeVotingContractNotDeployed();

    /** @notice Thrown when freeze components reference an Azorius module that wasn't deployed */
    error AzoriusModuleNotDeployed();

    /** @notice Thrown when FreezeVotingStandaloneV1 is paired with FreezeGuardAzoriusV1 */
    error InvalidFreezeVotingGuardPairing();

    // --- Structs ---

    /**
     * @notice Parameters for deploying a governance token
     * @param implementation The VotesERC20V1 implementation address
     * @param metadata Token name and symbol
     * @param allocations Initial token distribution to addresses
     * @param locked Whether the token is non-transferable
     * @param maxTotalSupply Maximum supply cap (0 for unlimited)
     * @param safeSupply Additional tokens allocated to the Safe
     */
    struct VotesERC20V1Params {
        address implementation;
        IVotesERC20V1.Metadata metadata;
        IVotesERC20V1.Allocation[] allocations;
        bool locked;
        uint256 maxTotalSupply;
        uint256 safeSupply;
    }

    /**
     * @notice Parameters for ERC20-based proposal creation rules
     * @param implementation The ProposerAdapterERC20V1 implementation
     * @param token Existing token address or 0 to use newly deployed token
     * @param newTokenIndex Index in votesERC20V1Params array if using new token
     * @param proposerThreshold Minimum tokens required to create proposals
     */
    struct ProposerAdapterERC20V1Params {
        address implementation;
        address token;
        uint256 newTokenIndex;
        uint256 proposerThreshold;
    }

    /**
     * @notice Parameters for NFT-based proposal creation rules
     * @param implementation The ProposerAdapterERC721V1 implementation
     * @param token The NFT contract address
     * @param proposerThreshold Minimum NFTs required to create proposals
     */
    struct ProposerAdapterERC721V1Params {
        address implementation;
        address token;
        uint256 proposerThreshold;
    }

    /**
     * @notice Parameters for Hats Protocol role-based proposal creation
     * @param implementation The ProposerAdapterHatsV1 implementation
     * @param hatsContract The Hats Protocol contract address
     * @param whitelistedHatIds Array of Hat IDs allowed to create proposals
     */
    struct ProposerAdapterHatsV1Params {
        address implementation;
        address hatsContract;
        uint256[] whitelistedHatIds;
    }

    /**
     * @notice Collection of all proposer adapter configurations
     */
    struct ProposerAdapterParams {
        ProposerAdapterERC20V1Params[] proposerAdapterERC20V1Params;
        ProposerAdapterERC721V1Params[] proposerAdapterERC721V1Params;
        ProposerAdapterHatsV1Params[] proposerAdapterHatsV1Params;
    }

    /**
     * @notice Parameters for the voting strategy
     * @param implementation The StrategyV1 implementation address
     * @param votingPeriod Duration in seconds for voting on proposals
     * @param quorumThreshold Minimum total votes required (in basis points)
     * @param basisNumerator Pass threshold numerator (denominator is total votes)
     * @param lightAccountFactory Address of the LightAccountFactory
     */
    struct StrategyV1Params {
        address implementation;
        uint32 votingPeriod;
        uint256 quorumThreshold;
        uint256 basisNumerator;
        address lightAccountFactory;
    }

    /**
     * @notice Parameters for ERC20 token-based voting configuration
     * @param votingWeightImplementation The VotingWeightERC20V1 implementation
     * @param voteTrackerImplementation The VoteTrackerERC20V1 implementation
     * @param token Existing token or 0 to use newly deployed token
     * @param newTokenIndex Index in votesERC20V1Params if using new token
     * @param weightPerToken Voting weight per token
     */
    struct VotingConfigERC20V1Params {
        address votingWeightImplementation;
        address voteTrackerImplementation;
        address token;
        uint256 newTokenIndex;
        uint256 weightPerToken;
    }

    /**
     * @notice Parameters for NFT-based voting configuration
     * @param votingWeightImplementation The VotingWeightERC721V1 implementation
     * @param voteTrackerImplementation The VoteTrackerERC721V1 implementation
     * @param token The NFT contract address
     * @param weightPerToken Voting weight per NFT
     */
    struct VotingConfigERC721V1Params {
        address votingWeightImplementation;
        address voteTrackerImplementation;
        address token;
        uint256 weightPerToken;
    }

    /**
     * @notice Collection of all voting configuration parameters
     */
    struct VotingConfigParams {
        VotingConfigERC20V1Params[] votingConfigERC20V1Params;
        VotingConfigERC721V1Params[] votingConfigERC721V1Params;
    }

    /**
     * @notice Parameters for the main governance module
     * @param implementation The ModuleAzoriusV1 implementation
     * @param timelockPeriod Delay after voting before execution (seconds)
     * @param executionPeriod Window for executing passed proposals (seconds)
     */
    struct ModuleAzoriusV1Params {
        address implementation;
        uint32 timelockPeriod;
        uint32 executionPeriod;
    }

    /**
     * @notice Complete configuration for Azorius-based governance
     */
    struct AzoriusGovernanceParams {
        ProposerAdapterParams proposerAdapterParams;
        StrategyV1Params strategyV1Params;
        VotingConfigParams votingConfigParams;
        ModuleAzoriusV1Params moduleAzoriusV1Params;
    }

    /**
     * @notice Parameters for Fractal module (parent-child DAO relationships)
     * @param implementation The ModuleFractalV1 implementation
     * @param owner The parent DAO that will control this module
     */
    struct ModuleFractalV1Params {
        address implementation;
        address owner;
    }

    /**
     * @notice Parameters for multisig freeze guard
     * @param implementation The FreezeGuardMultisigV1 implementation
     * @param owner The freeze voting contract that controls freezing
     * @param timelockPeriod Delay before freeze can be executed
     * @param executionPeriod Window for executing freeze
     */
    struct FreezeGuardMultisigV1Params {
        address implementation;
        address owner;
        uint32 timelockPeriod;
        uint32 executionPeriod;
    }

    /**
     * @notice Parameters for Azorius freeze guard
     * @param implementation The FreezeGuardAzoriusV1 implementation
     * @param owner The freeze voting contract that controls freezing
     */
    struct FreezeGuardAzoriusV1Params {
        address implementation;
        address owner;
    }

    /**
     * @notice Parameters for multisig-based freeze voting
     * @param implementation The FreezeVotingMultisigV1 implementation
     * @param owner The parent DAO that can update settings
     * @param freezeVotesThreshold Votes required to freeze
     * @param freezeProposalPeriod Duration for freeze voting
     * @param parentSafe The parent Safe whose owners can cast freeze votes
     * @param lightAccountFactory Address of the LightAccountFactory
     */
    struct FreezeVotingMultisigV1Params {
        address implementation;
        address owner;
        uint256 freezeVotesThreshold;
        uint32 freezeProposalPeriod;
        address parentSafe;
        address lightAccountFactory;
    }

    /**
     * @notice Parameters for Azorius-based freeze voting
     * @param implementation The FreezeVotingAzoriusV1 implementation
     * @param owner The parent DAO that can update settings
     * @param freezeVotesThreshold Votes required to freeze
     * @param freezeProposalPeriod Duration for freeze voting
     * @param parentAzorius The parent DAO's Azorius module
     * @param lightAccountFactory Address of the LightAccountFactory
     */
    struct FreezeVotingAzoriusV1Params {
        address implementation;
        address owner;
        uint256 freezeVotesThreshold;
        uint32 freezeProposalPeriod;
        address parentAzorius;
        address lightAccountFactory;
    }

    /**
     * @notice Parameters for standalone freeze voting
     * @param implementation The FreezeVotingStandaloneV1 implementation
     * @param freezeVotesThreshold Votes required to freeze
     * @param unfreezeVotesThreshold Votes required to unfreeze
     * @param freezeProposalPeriod Duration for freeze voting
     * @param unfreezeProposalPeriod Duration for unfreeze voting
     * @param lightAccountFactory Address of the LightAccountFactory
     */
    struct FreezeVotingStandaloneV1Params {
        address implementation;
        uint256 freezeVotesThreshold;
        uint256 unfreezeVotesThreshold;
        uint32 freezeProposalPeriod;
        uint32 unfreezeProposalPeriod;
        address lightAccountFactory;
    }

    /**
     * @notice Freeze guard configurations (choose one)
     */
    struct FreezeGuardParams {
        FreezeGuardMultisigV1Params freezeGuardMultisigV1Params;
        FreezeGuardAzoriusV1Params freezeGuardAzoriusV1Params;
    }

    /**
     * @notice Parameters for standalone freeze voting with its voting configs
     * @param freezeVotingStandaloneV1Params Configuration for standalone token-based freeze voting
     * @param votingConfigParams Voting configurations for the standalone freeze voting
     */
    struct FreezeVotingStandaloneParams {
        FreezeVotingStandaloneV1Params freezeVotingStandaloneV1Params;
        VotingConfigParams votingConfigParams;
    }

    /**
     * @notice Freeze voting configurations (choose one)
     */
    struct FreezeVotingParams {
        FreezeVotingMultisigV1Params freezeVotingMultisigV1Params;
        FreezeVotingAzoriusV1Params freezeVotingAzoriusV1Params;
        FreezeVotingStandaloneParams freezeVotingStandaloneParams;
    }

    /**
     * @notice Complete freeze mechanism configuration
     */
    struct FreezeParams {
        FreezeGuardParams freezeGuardParams;
        FreezeVotingParams freezeVotingParams;
    }

    // --- Events ---

    /**
     * @notice Emitted when a proxy contract is deployed
     * @param proxy The deployed proxy address
     * @param implementation The implementation address the proxy points to
     */
    event ProxyDeployed(address indexed proxy, address indexed implementation);

    /**
     * @notice Emitted when a complete DAO system is deployed
     * @param safeProxyFactory The Safe proxy factory used
     * @param salt The salt used for deterministic deployment
     * @param initData The initialization data for the Safe
     */
    event SystemDeployed(
        address indexed safeProxyFactory,
        bytes32 salt,
        bytes initData
    );

    // --- View Functions ---

    /**
     * @notice Predicts the address of a proxy before deployment
     * @dev Uses CREATE2 to calculate deterministic addresses. Useful for
     * pre-calculating addresses for circular dependency resolution.
     * @param implementation_ The implementation contract address
     * @param initData_ The initialization calldata
     * @param salt_ The salt for CREATE2
     * @param deployer_ The address that will deploy (usually this contract)
     * @return proxy The predicted proxy address
     */
    function predictProxyAddress(
        address implementation_,
        bytes memory initData_,
        bytes32 salt_,
        address deployer_
    ) external view returns (address proxy);

    // --- State-Changing Functions ---

    /**
     * @notice Deploys and configures a complete DAO system
     * @dev Called via delegatecall from a Safe during its setup. Orchestrates
     * the deployment of all governance components in the correct order.
     * @param salt_ Salt for deterministic deployment addresses
     * @param safeProxyFactory_ Safe proxy factory for event emission
     * @param systemDeployerEventEmitter_ Contract that emits deployment events
     * @param votesERC20V1Params_ Governance token configurations
     * @param azoriusGovernanceParams_ Complete Azorius governance setup
     * @param moduleFractalV1Params_ Fractal module for parent-child relationships
     * @param freezeParams_ Freeze mechanism configurations
     * @custom:note Empty arrays/structs skip deployment of those components
     */
    function setupSafe(
        bytes32 salt_,
        address safeProxyFactory_,
        address systemDeployerEventEmitter_,
        VotesERC20V1Params[] calldata votesERC20V1Params_,
        AzoriusGovernanceParams calldata azoriusGovernanceParams_,
        ModuleFractalV1Params calldata moduleFractalV1Params_,
        FreezeParams calldata freezeParams_
    ) external;

    /**
     * @notice Deploys a proxy contract with deterministic address
     * @dev Uses CREATE2 for deterministic deployment. The proxy uses ERC1967 standard.
     * If a contract already exists at the predicted address, returns that address
     * without redeploying. Must be called via delegatecall from a Safe.
     * @param implementation_ The implementation contract address
     * @param initData_ Initialization calldata to call on the proxy
     * @param salt_ Salt for CREATE2 deployment
     * @return proxy The deployed proxy address (or existing contract address)
     * @custom:throws ImplementationMustBeAContract if implementation has no code
     * @custom:throws MustBeCalledViaDelegatecall if called directly
     * @custom:emits ProxyDeployed (only emitted for new deployments, not existing contracts)
     */
    function deployProxy(
        address implementation_,
        bytes memory initData_,
        bytes32 salt_
    ) external returns (address proxy);
}
