// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    ISystemDeployerV1
} from "../interfaces/dao/singletons/ISystemDeployerV1.sol";
import {ISafe} from "../interfaces/safe/ISafe.sol";
import {
    IVotesERC20V1
} from "../interfaces/dao/deployables/IVotesERC20V1.sol";
import {
    IProposerAdapterERC20V1
} from "../interfaces/dao/deployables/IProposerAdapterERC20V1.sol";
import {
    IProposerAdapterERC721V1
} from "../interfaces/dao/deployables/IProposerAdapterERC721V1.sol";
import {
    IProposerAdapterHatsV1
} from "../interfaces/dao/deployables/IProposerAdapterHatsV1.sol";
import {IStrategyV1} from "../interfaces/dao/deployables/IStrategyV1.sol";
import {IVotingTypes} from "../interfaces/dao/deployables/IVotingTypes.sol";
import {
    IVotingWeightERC20V1
} from "../interfaces/dao/deployables/IVotingWeightERC20V1.sol";
import {
    IVotingWeightERC721V1
} from "../interfaces/dao/deployables/IVotingWeightERC721V1.sol";
import {
    IVoteTrackerV1
} from "../interfaces/dao/deployables/IVoteTrackerV1.sol";
import {
    IModuleAzoriusV1
} from "../interfaces/dao/deployables/IModuleAzoriusV1.sol";
import {
    IModuleFractalV1
} from "../interfaces/dao/deployables/IModuleFractalV1.sol";
import {
    IFreezeVotingMultisigV1
} from "../interfaces/dao/deployables/IFreezeVotingMultisigV1.sol";
import {
    IFreezeVotingAzoriusV1
} from "../interfaces/dao/deployables/IFreezeVotingAzoriusV1.sol";
import {
    IFreezeVotingStandaloneV1
} from "../interfaces/dao/deployables/IFreezeVotingStandaloneV1.sol";
import {
    IFreezeGuardMultisigV1
} from "../interfaces/dao/deployables/IFreezeGuardMultisigV1.sol";
import {
    IFreezeGuardAzoriusV1
} from "../interfaces/dao/deployables/IFreezeGuardAzoriusV1.sol";
import {
    ISystemDeployerEventEmitterV1
} from "../interfaces/dao/singletons/ISystemDeployerEventEmitterV1.sol";
import {IVersion} from "../interfaces/dao/deployables/IVersion.sol";
import {IDeploymentBlock} from "../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockNonInitializable
} from "../DeploymentBlockNonInitializable.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title SystemDeployerV1
 * @author Lux Industriesn Inc
 * @notice Implementation of deployment orchestration for complete DAO systems
 * @dev This contract implements ISystemDeployerV1, providing a singleton deployment
 * service that orchestrates the creation of entire DAO governance systems.
 *
 * Implementation details:
 * - Deployed once per chain as a singleton service
 * - Non-upgradeable deployment pattern
 * - Uses CREATE2 for deterministic proxy addresses
 * - Handles circular dependency resolution
 * - Called via delegatecall from Safe during setup
 * - Validates implementation addresses before deployment
 *
 * Deployment flow:
 * 1. Deploy governance tokens (VotesERC20V1)
 * 2. Deploy proposer adapters using token references
 * 3. Deploy strategy with proposer adapters
 * 4. Deploy voting adapters linked to strategy
 * 5. Deploy Azorius module with strategy reference
 * 6. Complete circular initialization (Strategy ↔ Azorius ↔ VotingConfigs)
 * 7. Deploy optional Fractal module for parent-child relationships
 * 8. Deploy freeze mechanisms if configured
 *
 * Security considerations:
 * - Only accessible via delegatecall from Safe setup (enforced by MustBeCalledViaDelegatecall error)
 * - Validates all implementation contracts have code
 * - Ensures proper initialization of all components
 * - Gracefully handles existing contracts at predicted addresses
 * - Emits events only for new deployments (not for existing contracts)
 *
 * @custom:security-contact security@lux.network
 */
contract SystemDeployerV1 is
    ISystemDeployerV1,
    IVersion,
    DeploymentBlockNonInitializable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /** @notice Stores the SystemDeployer's address to detect delegatecall vs direct call */
    address private immutable SYSTEM_DEPLOYER_ADDRESS;

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    /**
     * @notice Enforces that the function can only be called via delegatecall
     * @dev This is used to ensure the Safe context is available during deployment
     */
    modifier onlyDelegatecall() {
        if (address(this) == SYSTEM_DEPLOYER_ADDRESS) {
            revert MustBeCalledViaDelegatecall();
        }
        _;
    }

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    constructor() {
        SYSTEM_DEPLOYER_ADDRESS = address(this);
    }

    // ======================================================================
    // ISystemDeployer
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ISystemDeployerV1
     */
    function predictProxyAddress(
        address implementation_,
        bytes memory initData_,
        bytes32 salt_,
        address deployer_
    ) public view override returns (address) {
        if (implementation_.code.length == 0) {
            revert ImplementationMustBeAContract();
        }

        // Calculate the proxy bytecode (implementation address + init data)
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation_, initData_)
        );

        // Calculate the CREATE2 address
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer_,
                salt_,
                keccak256(bytecode)
            )
        );

        return address(uint160(uint256(hash)));
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc ISystemDeployerV1
     * @dev Checks if a contract already exists at the predicted address and returns it if so.
     * Also enforces that this function must be called via delegatecall.
     */
    function deployProxy(
        address implementation_,
        bytes memory initData_,
        bytes32 salt_
    ) public onlyDelegatecall returns (address) {
        if (implementation_.code.length == 0) {
            revert ImplementationMustBeAContract();
        }

        // Predict the proxy address using the existing function
        address predictedAddress = predictProxyAddress(
            implementation_,
            initData_,
            salt_,
            address(this)
        );

        // Check if a contract already exists at the predicted address
        if (predictedAddress.code.length > 0) {
            // Contract already exists, return the existing address
            return predictedAddress;
        }

        // Deploy new proxy
        address proxy = address(
            new ERC1967Proxy{salt: salt_}(implementation_, initData_)
        );

        emit ProxyDeployed(proxy, implementation_);

        return proxy;
    }

    /**
     * @inheritdoc ISystemDeployerV1
     * @dev Orchestrates the deployment of all governance components in the correct order.
     * This function is called via delegatecall from a Safe during its setup, giving it
     * access to the Safe's context for enabling modules and setting guards.
     */
    function setupSafe(
        bytes32 salt_,
        address safeProxyFactory_,
        address systemDeployerEventEmitter_,
        VotesERC20V1Params[] calldata votesERC20V1Params_,
        AzoriusGovernanceParams calldata azoriusGovernanceParams_,
        ModuleFractalV1Params calldata moduleFractalV1Params_,
        FreezeParams calldata freezeParams_
    ) public virtual override {
        // create an array to hold the new VotesERC20V1 addresses
        address[] memory newVotesERC20V1Addresses = new address[](
            votesERC20V1Params_.length
        );

        _deployVotesERC20V1(
            salt_,
            votesERC20V1Params_,
            newVotesERC20V1Addresses
        );

        address azoriusModuleAddress = _deployAzoriusGovernance(
            salt_,
            azoriusGovernanceParams_,
            newVotesERC20V1Addresses
        );

        _deployModuleFractal(salt_, moduleFractalV1Params_);

        _deployFreezeContracts(
            salt_,
            freezeParams_,
            azoriusModuleAddress,
            newVotesERC20V1Addresses
        );

        bytes memory initData = abi.encode(
            votesERC20V1Params_,
            azoriusGovernanceParams_,
            moduleFractalV1Params_,
            freezeParams_
        );

        ISystemDeployerEventEmitterV1(systemDeployerEventEmitter_)
            .emitSystemDeployed(safeProxyFactory_, salt_, initData);

        emit SystemDeployed(safeProxyFactory_, salt_, initData);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports ISystemDeployerV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(ISystemDeployerV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // Internal Functions
    // ======================================================================

    /**
     * @notice Deploys the complete Azorius governance system
     * @dev Handles the complex deployment order and circular dependency resolution
     * between Azorius, Strategy, and VotingConfigs.
     * @param salt_ Salt for deterministic deployment
     * @param azoriusGovernanceParams_ Complete governance configuration
     * @param newVotesERC20V1Addresses Addresses of newly deployed governance tokens
     * @return azoriusModuleAddress The deployed Azorius module address (or zero if skipped)
     */
    function _deployAzoriusGovernance(
        bytes32 salt_,
        AzoriusGovernanceParams calldata azoriusGovernanceParams_,
        address[] memory newVotesERC20V1Addresses
    ) internal returns (address) {
        address azoriusModuleAddress;

        ModuleAzoriusV1Params
            memory moduleAzoriusV1Params = azoriusGovernanceParams_
                .moduleAzoriusV1Params;

        // Skip deployment if no implementation provided
        if (moduleAzoriusV1Params.implementation != address(0)) {
            // Step 1: Deploy proposer adapters (who can create proposals)
            ProposerAdapterParams
                memory proposerAdapterParams = azoriusGovernanceParams_
                    .proposerAdapterParams;

            address[] memory proposerAdapterAddresses = _deployProposerAdapters(
                salt_,
                proposerAdapterParams,
                newVotesERC20V1Addresses
            );

            // Step 2: Deploy strategy with proposer adapters
            // Note: Strategy is partially initialized - needs Azorius and voting adapters
            StrategyV1Params memory strategyV1Params = azoriusGovernanceParams_
                .strategyV1Params;

            address strategyProxyAddress = _deployStrategy(
                salt_,
                strategyV1Params,
                proposerAdapterAddresses
            );

            // Step 3: Deploy voting configurations (weight strategies + vote trackers)
            IVotingTypes.VotingConfig[]
                memory votingConfigs = _deployVotingConfigs(
                    salt_,
                    azoriusGovernanceParams_.votingConfigParams,
                    newVotesERC20V1Addresses,
                    strategyProxyAddress
                );

            // Step 4: Deploy Azorius module with strategy reference
            azoriusModuleAddress = _deployModuleAzorius(
                salt_,
                moduleAzoriusV1Params,
                strategyProxyAddress
            );

            // Step 5: Complete strategy initialization with circular dependencies
            // This sets the Azorius module and voting configurations on the strategy
            IStrategyV1(strategyProxyAddress).initialize2(
                azoriusModuleAddress,
                votingConfigs
            );

            // Step 6: Enable Azorius as a module on the Safe
            // This gives Azorius permission to execute transactions
            ISafe(address(this)).enableModule(azoriusModuleAddress);
        }

        return azoriusModuleAddress;
    }

    /**
     * @notice Deploys governance tokens with initial allocations
     * @dev Adds an additional allocation to the Safe beyond user-specified allocations.
     * This ensures the Safe has tokens for treasury or future distributions.
     * @param salt_ Salt for deterministic deployment
     * @param votesERC20V1Params Array of token configurations
     * @param newVotesERC20V1Addresses Output array to store deployed token addresses
     */
    function _deployVotesERC20V1(
        bytes32 salt_,
        VotesERC20V1Params[] memory votesERC20V1Params,
        address[] memory newVotesERC20V1Addresses
    ) internal {
        for (uint256 i = 0; i < votesERC20V1Params.length; ) {
            VotesERC20V1Params memory votesERC20V1Param = votesERC20V1Params[i];

            uint256 allocationsLength = votesERC20V1Param.allocations.length;

            // Create array with space for user allocations + Safe allocation
            IVotesERC20V1.Allocation[]
                memory totalAllocations = new IVotesERC20V1.Allocation[](
                    allocationsLength + 1
                );

            // Copy user-specified allocations
            for (uint256 j = 0; j < allocationsLength; ) {
                totalAllocations[j] = votesERC20V1Param.allocations[j];

                unchecked {
                    ++j;
                }
            }

            // Add Safe's allocation at the end
            // This ensures the DAO treasury has initial tokens
            totalAllocations[allocationsLength] = IVotesERC20V1.Allocation({
                to: address(this),
                amount: votesERC20V1Param.safeSupply
            });

            // Deploy the token proxy with all allocations
            address votesERC20V1ProxyAddress = deployProxy(
                votesERC20V1Param.implementation,
                abi.encodeCall(
                    IVotesERC20V1.initialize,
                    (
                        votesERC20V1Param.metadata,
                        totalAllocations,
                        address(this),
                        votesERC20V1Param.locked,
                        votesERC20V1Param.maxTotalSupply
                    )
                ),
                salt_
            );

            // Store address for later reference by adapters
            newVotesERC20V1Addresses[i] = votesERC20V1ProxyAddress;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deploys all proposer adapters for the governance system
     * @dev Handles deployment of ERC20, ERC721, and Hats proposer adapters.
     * Returns a combined array with all adapter addresses in order.
     * @param salt_ Salt for deterministic deployment
     * @param proposerAdapterParams Configurations for all proposer adapter types
     * @param newVotesERC20V1Addresses Addresses of newly deployed governance tokens
     * @return proposerAdapterAddresses Combined array of all deployed adapter addresses
     */
    function _deployProposerAdapters(
        bytes32 salt_,
        ProposerAdapterParams memory proposerAdapterParams,
        address[] memory newVotesERC20V1Addresses
    ) internal returns (address[] memory) {
        ProposerAdapterERC20V1Params[]
            memory proposerAdapterERC20V1Params = proposerAdapterParams
                .proposerAdapterERC20V1Params;

        uint256 proposerAdapterERC20V1ParamsLength = proposerAdapterERC20V1Params
                .length;

        ProposerAdapterERC721V1Params[]
            memory proposerAdapterERC721V1Params = proposerAdapterParams
                .proposerAdapterERC721V1Params;

        uint256 proposerAdapterERC721V1ParamsLength = proposerAdapterERC721V1Params
                .length;

        ProposerAdapterHatsV1Params[]
            memory proposerAdapterHatsV1Params = proposerAdapterParams
                .proposerAdapterHatsV1Params;

        uint256 proposerAdapterHatsV1ParamsLength = proposerAdapterHatsV1Params
            .length;

        address[] memory proposerAdapterAddresses = new address[](
            proposerAdapterERC20V1ParamsLength +
                proposerAdapterERC721V1ParamsLength +
                proposerAdapterHatsV1ParamsLength
        );

        _deployProposerAdapterERC20(
            salt_,
            proposerAdapterERC20V1ParamsLength,
            proposerAdapterERC20V1Params,
            newVotesERC20V1Addresses,
            proposerAdapterAddresses
        );

        _deployProposerAdapterERC721(
            salt_,
            proposerAdapterERC721V1ParamsLength,
            proposerAdapterERC20V1ParamsLength,
            proposerAdapterERC721V1Params,
            proposerAdapterAddresses
        );

        _deployProposerAdapterHats(
            salt_,
            proposerAdapterHatsV1ParamsLength,
            proposerAdapterERC721V1ParamsLength,
            proposerAdapterERC20V1ParamsLength,
            proposerAdapterHatsV1Params,
            proposerAdapterAddresses
        );

        return proposerAdapterAddresses;
    }

    /**
     * @notice Deploys ERC20-based proposer adapters
     * @dev Handles token resolution - can use existing tokens or newly deployed ones.
     * Stores addresses in the first slots of proposerAdapterAddresses array.
     * @param salt_ Salt for deterministic deployment
     * @param proposerAdapterERC20V1ParamsLength Number of ERC20 adapters to deploy
     * @param proposerAdapterERC20V1Params Array of ERC20 adapter configurations
     * @param newVotesERC20V1Addresses Addresses of newly deployed governance tokens
     * @param proposerAdapterAddresses Output array to store deployed addresses
     */
    function _deployProposerAdapterERC20(
        bytes32 salt_,
        uint256 proposerAdapterERC20V1ParamsLength,
        ProposerAdapterERC20V1Params[] memory proposerAdapterERC20V1Params,
        address[] memory newVotesERC20V1Addresses,
        address[] memory proposerAdapterAddresses
    ) internal {
        for (uint256 i = 0; i < proposerAdapterERC20V1ParamsLength; ) {
            ProposerAdapterERC20V1Params
                memory proposerAdapterERC20V1Param = proposerAdapterERC20V1Params[
                    i
                ];

            address tokenAddress;
            uint256 newTokenIndex = proposerAdapterERC20V1Param.newTokenIndex;

            // Resolve token address - either existing or newly deployed
            if (proposerAdapterERC20V1Param.token == address(0)) {
                // Use newly deployed token at specified index
                tokenAddress = newVotesERC20V1Addresses[newTokenIndex];

                if (tokenAddress == address(0)) {
                    revert VotesERC20V1NotFoundAtIndex(newTokenIndex);
                }
            } else {
                // Use existing token address
                tokenAddress = proposerAdapterERC20V1Param.token;
            }

            proposerAdapterAddresses[i] = deployProxy(
                proposerAdapterERC20V1Param.implementation,
                abi.encodeCall(
                    IProposerAdapterERC20V1.initialize,
                    (
                        tokenAddress,
                        proposerAdapterERC20V1Param.proposerThreshold
                    )
                ),
                salt_
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deploys NFT-based proposer adapters
     * @dev Stores addresses after ERC20 adapters in the combined array.
     * NFTs must be existing contracts - no new deployment option.
     * @param salt_ Salt for deterministic deployment
     * @param proposerAdapterERC721V1ParamsLength Number of ERC721 adapters to deploy
     * @param proposerAdapterERC20V1ParamsLength Offset for array positioning
     * @param proposerAdapterERC721V1Params Array of ERC721 adapter configurations
     * @param proposerAdapterAddresses Output array to store deployed addresses
     */
    function _deployProposerAdapterERC721(
        bytes32 salt_,
        uint256 proposerAdapterERC721V1ParamsLength,
        uint256 proposerAdapterERC20V1ParamsLength,
        ProposerAdapterERC721V1Params[] memory proposerAdapterERC721V1Params,
        address[] memory proposerAdapterAddresses
    ) internal {
        for (uint256 i = 0; i < proposerAdapterERC721V1ParamsLength; ) {
            ProposerAdapterERC721V1Params
                memory proposerAdapterERC721V1Param = proposerAdapterERC721V1Params[
                    i
                ];

            // Store at position after ERC20 adapters
            proposerAdapterAddresses[
                proposerAdapterERC20V1ParamsLength + i
            ] = deployProxy(
                proposerAdapterERC721V1Param.implementation,
                abi.encodeCall(
                    IProposerAdapterERC721V1.initialize,
                    (
                        proposerAdapterERC721V1Param.token,
                        proposerAdapterERC721V1Param.proposerThreshold
                    )
                ),
                salt_
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deploys Hats Protocol role-based proposer adapters
     * @dev Stores addresses after ERC20 and ERC721 adapters in the combined array.
     * Each adapter can whitelist multiple Hat IDs for proposal creation.
     * @param salt_ Salt for deterministic deployment
     * @param proposerAdapterHatsV1ParamsLength Number of Hats adapters to deploy
     * @param proposerAdapterERC721V1ParamsLength Offset for ERC721 adapters
     * @param proposerAdapterERC20V1ParamsLength Offset for ERC20 adapters
     * @param proposerAdapterHatsV1Params Array of Hats adapter configurations
     * @param proposerAdapterAddresses Output array to store deployed addresses
     */
    function _deployProposerAdapterHats(
        bytes32 salt_,
        uint256 proposerAdapterHatsV1ParamsLength,
        uint256 proposerAdapterERC721V1ParamsLength,
        uint256 proposerAdapterERC20V1ParamsLength,
        ProposerAdapterHatsV1Params[] memory proposerAdapterHatsV1Params,
        address[] memory proposerAdapterAddresses
    ) internal {
        for (uint256 i = 0; i < proposerAdapterHatsV1ParamsLength; ) {
            ProposerAdapterHatsV1Params
                memory proposerAdapterHatsV1Param = proposerAdapterHatsV1Params[
                    i
                ];

            // Store at position after ERC20 and ERC721 adapters
            proposerAdapterAddresses[
                proposerAdapterERC20V1ParamsLength +
                    proposerAdapterERC721V1ParamsLength +
                    i
            ] = deployProxy(
                proposerAdapterHatsV1Param.implementation,
                abi.encodeCall(
                    IProposerAdapterHatsV1.initialize,
                    (
                        proposerAdapterHatsV1Param.hatsContract,
                        proposerAdapterHatsV1Param.whitelistedHatIds
                    )
                ),
                salt_
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deploys the voting strategy contract
     * @dev The strategy is partially initialized here with proposer adapters.
     * Full initialization happens later with Azorius and voting adapters.
     * @param salt_ Salt for deterministic deployment
     * @param strategyV1Params Strategy configuration parameters
     * @param proposerAdapterAddresses Array of deployed proposer adapter addresses
     * @return strategyProxyAddress The deployed strategy proxy address
     */
    function _deployStrategy(
        bytes32 salt_,
        StrategyV1Params memory strategyV1Params,
        address[] memory proposerAdapterAddresses
    ) internal returns (address) {
        return
            deployProxy(
                strategyV1Params.implementation,
                abi.encodeCall(
                    IStrategyV1.initialize,
                    (
                        strategyV1Params.votingPeriod,
                        strategyV1Params.quorumThreshold,
                        strategyV1Params.basisNumerator,
                        proposerAdapterAddresses,
                        strategyV1Params.lightAccountFactory
                    )
                ),
                salt_
            );
    }

    /**
     * @notice Deploys all voting configurations for the governance system
     * @dev Handles deployment of weight strategies and vote trackers.
     * @param salt_ Salt for deterministic deployment
     * @param votingConfigParams Configurations for all voting config types
     * @param newVotesERC20V1Addresses Addresses of newly deployed governance tokens
     * @param strategyAddress The address of the strategy contract to authorize on vote trackers
     * @return votingConfigs Combined array of all voting configurations
     */
    function _deployVotingConfigs(
        bytes32 salt_,
        VotingConfigParams memory votingConfigParams,
        address[] memory newVotesERC20V1Addresses,
        address strategyAddress
    ) internal returns (IVotingTypes.VotingConfig[] memory) {
        VotingConfigERC20V1Params[]
            memory votingConfigERC20V1Params = votingConfigParams
                .votingConfigERC20V1Params;

        uint256 votingConfigERC20V1ParamsLength = votingConfigERC20V1Params
            .length;

        VotingConfigERC721V1Params[]
            memory votingConfigERC721V1Params = votingConfigParams
                .votingConfigERC721V1Params;

        uint256 votingConfigERC721V1ParamsLength = votingConfigERC721V1Params
            .length;

        IVotingTypes.VotingConfig[]
            memory votingConfigs = new IVotingTypes.VotingConfig[](
                votingConfigERC20V1ParamsLength +
                    votingConfigERC721V1ParamsLength
            );

        _deployVotingConfigsERC20(
            salt_,
            votingConfigERC20V1ParamsLength,
            votingConfigERC20V1Params,
            newVotesERC20V1Addresses,
            votingConfigs,
            strategyAddress
        );

        _deployVotingConfigsERC721(
            salt_,
            votingConfigERC721V1ParamsLength,
            votingConfigERC20V1ParamsLength,
            votingConfigERC721V1Params,
            votingConfigs,
            strategyAddress
        );

        return votingConfigs;
    }

    /**
     * @notice Deploys ERC20-based voting configurations
     * @dev Handles token resolution and deploys weight strategies and vote trackers.
     * @param salt_ Salt for deterministic deployment
     * @param votingConfigERC20V1ParamsLength Number of ERC20 configs to deploy
     * @param votingConfigERC20V1Params Array of ERC20 config parameters
     * @param newVotesERC20V1Addresses Addresses of newly deployed governance tokens
     * @param votingConfigs Output array to store voting configurations
     * @param strategyAddress The address of the strategy contract to authorize on vote trackers
     */
    function _deployVotingConfigsERC20(
        bytes32 salt_,
        uint256 votingConfigERC20V1ParamsLength,
        VotingConfigERC20V1Params[] memory votingConfigERC20V1Params,
        address[] memory newVotesERC20V1Addresses,
        IVotingTypes.VotingConfig[] memory votingConfigs,
        address strategyAddress
    ) internal {
        for (uint256 i = 0; i < votingConfigERC20V1ParamsLength; ) {
            VotingConfigERC20V1Params memory param = votingConfigERC20V1Params[
                i
            ];
            address tokenAddress;

            // Resolve token address - either existing or newly deployed
            if (param.token == address(0)) {
                // Use newly deployed token at specified index
                uint256 newTokenIndex = param.newTokenIndex;
                tokenAddress = newVotesERC20V1Addresses[newTokenIndex];

                if (tokenAddress == address(0)) {
                    revert VotesERC20V1NotFoundAtIndex(newTokenIndex);
                }
            } else {
                // Use existing token address
                tokenAddress = param.token;
            }

            // Deploy weight strategy
            address votingWeight = deployProxy(
                param.votingWeightImplementation,
                abi.encodeCall(
                    IVotingWeightERC20V1.initialize,
                    (tokenAddress, param.weightPerToken)
                ),
                salt_
            );

            // Deploy vote tracker with strategy as authorized caller
            address[] memory authorizedCallers = new address[](1);
            authorizedCallers[0] = strategyAddress;

            // Use a unique salt for each vote tracker by combining the base salt with the index
            bytes32 voteTrackerSalt = keccak256(abi.encodePacked(salt_, i));

            address voteTracker = deployProxy(
                param.voteTrackerImplementation,
                abi.encodeCall(IVoteTrackerV1.initialize, (authorizedCallers)),
                voteTrackerSalt
            );

            // Create voting config
            votingConfigs[i] = IVotingTypes.VotingConfig({
                votingWeight: votingWeight,
                voteTracker: voteTracker
            });

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deploys NFT-based voting configurations
     * @dev Deploys weight strategies and vote trackers for NFT voting.
     * Stores configs after ERC20 configs in the combined array.
     * @param salt_ Salt for deterministic deployment
     * @param votingConfigERC721V1ParamsLength Number of ERC721 configs to deploy
     * @param votingConfigERC20V1ParamsLength Offset for array positioning
     * @param votingConfigERC721V1Params Array of ERC721 config parameters
     * @param votingConfigs Output array to store voting configurations
     * @param strategyAddress The address of the strategy contract to authorize on vote trackers
     */
    function _deployVotingConfigsERC721(
        bytes32 salt_,
        uint256 votingConfigERC721V1ParamsLength,
        uint256 votingConfigERC20V1ParamsLength,
        VotingConfigERC721V1Params[] memory votingConfigERC721V1Params,
        IVotingTypes.VotingConfig[] memory votingConfigs,
        address strategyAddress
    ) internal {
        for (uint256 i = 0; i < votingConfigERC721V1ParamsLength; ) {
            VotingConfigERC721V1Params
                memory param = votingConfigERC721V1Params[i];

            // Deploy weight strategy
            address votingWeight = deployProxy(
                param.votingWeightImplementation,
                abi.encodeCall(
                    IVotingWeightERC721V1.initialize,
                    (param.token, param.weightPerToken)
                ),
                salt_
            );

            // Deploy vote tracker with strategy as authorized caller
            address[] memory authorizedCallers = new address[](1);
            authorizedCallers[0] = strategyAddress;

            // Use a unique salt for each vote tracker by combining the base salt with the index
            bytes32 voteTrackerSalt = keccak256(abi.encodePacked(salt_, i));

            address voteTracker = deployProxy(
                param.voteTrackerImplementation,
                abi.encodeCall(IVoteTrackerV1.initialize, (authorizedCallers)),
                voteTrackerSalt
            );

            // Store at position after ERC20 configs
            votingConfigs[votingConfigERC20V1ParamsLength + i] = IVotingTypes
                .VotingConfig({
                    votingWeight: votingWeight,
                    voteTracker: voteTracker
                });

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Deploys the Azorius governance module
     * @dev The module is initialized with the Safe as owner, target, and avatar.
     * Links to the strategy for proposal validation and voting.
     * @param salt_ Salt for deterministic deployment
     * @param moduleAzoriusV1Params Azorius configuration parameters
     * @param strategyProxyAddress Address of the deployed strategy
     * @return azoriusProxyAddress The deployed Azorius module address
     */
    function _deployModuleAzorius(
        bytes32 salt_,
        ModuleAzoriusV1Params memory moduleAzoriusV1Params,
        address strategyProxyAddress
    ) internal returns (address) {
        return
            deployProxy(
                moduleAzoriusV1Params.implementation,
                abi.encodeCall(
                    IModuleAzoriusV1.initialize,
                    (
                        address(this),
                        address(this),
                        address(this),
                        strategyProxyAddress,
                        moduleAzoriusV1Params.timelockPeriod,
                        moduleAzoriusV1Params.executionPeriod
                    )
                ),
                salt_
            );
    }

    /**
     * @notice Deploys the Fractal module for parent-child DAO relationships
     * @dev Only deployed if implementation is provided. Enables parent DAO
     * to execute transactions on this Safe.
     * @param salt_ Salt for deterministic deployment
     * @param moduleFractalV1Params_ Fractal module configuration
     */
    function _deployModuleFractal(
        bytes32 salt_,
        ModuleFractalV1Params memory moduleFractalV1Params_
    ) internal {
        if (moduleFractalV1Params_.implementation != address(0)) {
            address moduleFractalProxyAddress = deployProxy(
                moduleFractalV1Params_.implementation,
                abi.encodeCall(
                    IModuleFractalV1.initialize,
                    (moduleFractalV1Params_.owner, address(this), address(this))
                ),
                salt_
            );

            // add Module Fractal to Safe as Module
            ISafe(address(this)).enableModule(moduleFractalProxyAddress);
        }
    }

    /**
     * @notice Deploys freeze mechanism contracts for parent-child DAO control
     * @dev Deploys freeze voting contract first, then freeze guard that references it.
     * The freeze guard is attached to either the Safe or Azorius module.
     * @param salt_ Salt for deterministic deployment
     * @param freezeParams_ Freeze mechanism configurations
     * @param azoriusModuleAddress Address of Azorius module (for freeze guard attachment)
     * @param newVotesERC20V1Addresses Addresses of newly deployed governance tokens
     */
    function _deployFreezeContracts(
        bytes32 salt_,
        FreezeParams memory freezeParams_,
        address azoriusModuleAddress,
        address[] memory newVotesERC20V1Addresses
    ) internal {
        // Validate that FreezeVotingStandaloneV1 is not paired with FreezeGuardAzoriusV1
        if (
            freezeParams_
                .freezeVotingParams
                .freezeVotingStandaloneParams
                .freezeVotingStandaloneV1Params
                .implementation !=
            address(0) &&
            freezeParams_
                .freezeGuardParams
                .freezeGuardAzoriusV1Params
                .implementation !=
            address(0)
        ) {
            revert InvalidFreezeVotingGuardPairing();
        }

        // Deploy freeze voting contract (controls when child can be frozen)
        address freezeVotingAddress = _deployFreezeVoting(
            salt_,
            freezeParams_.freezeVotingParams,
            newVotesERC20V1Addresses
        );

        // Deploy freeze guard (enforces freeze when activated)
        _deployFreezeGuard(
            salt_,
            freezeParams_.freezeGuardParams,
            freezeVotingAddress,
            azoriusModuleAddress
        );
    }

    /**
     * @notice Deploys freeze voting contract (multisig, Azorius-based, or standalone)
     * @dev Only one type can be deployed. Returns the deployed address or zero.
     * Validates that multiple types aren't specified.
     * @param salt_ Salt for deterministic deployment
     * @param freezeVotingParams_ Freeze voting configurations
     * @param newVotesERC20V1Addresses_ Addresses of newly deployed governance tokens
     * @return freezeVotingAddress The deployed freeze voting contract address
     */
    function _deployFreezeVoting(
        bytes32 salt_,
        FreezeVotingParams memory freezeVotingParams_,
        address[] memory newVotesERC20V1Addresses_
    ) internal returns (address) {
        FreezeVotingMultisigV1Params
            memory freezeVotingMultisigV1Params = freezeVotingParams_
                .freezeVotingMultisigV1Params;

        FreezeVotingAzoriusV1Params
            memory freezeVotingAzoriusV1Params = freezeVotingParams_
                .freezeVotingAzoriusV1Params;

        FreezeVotingStandaloneParams
            memory freezeVotingStandaloneParams = freezeVotingParams_
                .freezeVotingStandaloneParams;

        // Count how many freeze voting types are specified
        uint8 freezeVotingCount = 0;
        if (freezeVotingMultisigV1Params.implementation != address(0))
            freezeVotingCount++;
        if (freezeVotingAzoriusV1Params.implementation != address(0))
            freezeVotingCount++;
        if (
            freezeVotingStandaloneParams
                .freezeVotingStandaloneV1Params
                .implementation != address(0)
        ) freezeVotingCount++;

        if (freezeVotingCount > 1) {
            revert CannotDeployMultipleFreezeVotingContracts();
        }

        address freezeVotingAddress;

        if (freezeVotingMultisigV1Params.implementation != address(0)) {
            freezeVotingAddress = deployProxy(
                freezeVotingMultisigV1Params.implementation,
                abi.encodeCall(
                    IFreezeVotingMultisigV1.initialize,
                    (
                        freezeVotingMultisigV1Params.owner,
                        freezeVotingMultisigV1Params.freezeVotesThreshold,
                        freezeVotingMultisigV1Params.freezeProposalPeriod,
                        freezeVotingMultisigV1Params.parentSafe,
                        freezeVotingMultisigV1Params.lightAccountFactory
                    )
                ),
                salt_
            );
        }

        if (freezeVotingAzoriusV1Params.implementation != address(0)) {
            freezeVotingAddress = deployProxy(
                freezeVotingAzoriusV1Params.implementation,
                abi.encodeCall(
                    IFreezeVotingAzoriusV1.initialize,
                    (
                        freezeVotingAzoriusV1Params.owner,
                        freezeVotingAzoriusV1Params.freezeVotesThreshold,
                        freezeVotingAzoriusV1Params.freezeProposalPeriod,
                        freezeVotingAzoriusV1Params.parentAzorius,
                        freezeVotingAzoriusV1Params.lightAccountFactory
                    )
                ),
                salt_
            );
        }

        if (
            freezeVotingStandaloneParams
                .freezeVotingStandaloneV1Params
                .implementation != address(0)
        ) {
            freezeVotingAddress = _deployFreezeVotingStandalone(
                salt_,
                freezeVotingStandaloneParams,
                newVotesERC20V1Addresses_
            );
        }

        return freezeVotingAddress;
    }

    /**
     * @notice Deploys freeze guard contracts
     * @dev Can deploy multisig guard (on Safe) and/or Azorius guard (on module).
     * Each guard type attaches to different components.
     * @param salt_ Salt for deterministic deployment
     * @param freezeGuardParams_ Freeze guard configurations
     * @param freezeVotingAddress Address of deployed freeze voting contract
     * @param azoriusModuleAddress Address of Azorius module (for Azorius guard)
     */
    function _deployFreezeGuard(
        bytes32 salt_,
        FreezeGuardParams memory freezeGuardParams_,
        address freezeVotingAddress,
        address azoriusModuleAddress
    ) internal {
        FreezeGuardMultisigV1Params
            memory freezeGuardMultisigV1Params = freezeGuardParams_
                .freezeGuardMultisigV1Params;

        _deployFreezeGuardMultisig(
            salt_,
            freezeGuardMultisigV1Params,
            freezeVotingAddress
        );

        FreezeGuardAzoriusV1Params
            memory freezeGuardAzoriusV1Params = freezeGuardParams_
                .freezeGuardAzoriusV1Params;

        _deployFreezeGuardAzorius(
            salt_,
            freezeGuardAzoriusV1Params,
            freezeVotingAddress,
            azoriusModuleAddress
        );
    }

    /**
     * @notice Deploys multisig freeze guard and attaches to Safe
     * @dev Guard enforces timelock and freeze restrictions on Safe transactions.
     * Requires freeze voting contract to be deployed.
     * @param salt_ Salt for deterministic deployment
     * @param freezeGuardMultisigV1Params Multisig guard configuration
     * @param freezeVotingAddress Address of freeze voting contract that controls freezing
     */
    function _deployFreezeGuardMultisig(
        bytes32 salt_,
        FreezeGuardMultisigV1Params memory freezeGuardMultisigV1Params,
        address freezeVotingAddress
    ) internal {
        if (freezeGuardMultisigV1Params.implementation != address(0)) {
            if (freezeVotingAddress == address(0)) {
                revert FreezeVotingContractNotDeployed();
            }

            address multisigFreezeGuardAddress = deployProxy(
                freezeGuardMultisigV1Params.implementation,
                abi.encodeCall(
                    IFreezeGuardMultisigV1.initialize,
                    (
                        freezeGuardMultisigV1Params.timelockPeriod,
                        freezeGuardMultisigV1Params.executionPeriod,
                        freezeGuardMultisigV1Params.owner,
                        freezeVotingAddress,
                        address(this)
                    )
                ),
                salt_
            );

            // add multisig freeze guard to Safe
            ISafe(address(this)).setGuard(multisigFreezeGuardAddress);
        }
    }

    /**
     * @notice Deploys Azorius freeze guard and attaches to Azorius module
     * @dev Guard blocks proposal execution when DAO is frozen.
     * Requires both freeze voting and Azorius module to be deployed.
     * @param salt_ Salt for deterministic deployment
     * @param freezeGuardAzoriusV1Params Azorius guard configuration
     * @param freezeVotingAddress Address of freeze voting contract that controls freezing
     * @param azoriusModuleAddress Address of Azorius module to attach guard to
     */
    function _deployFreezeGuardAzorius(
        bytes32 salt_,
        FreezeGuardAzoriusV1Params memory freezeGuardAzoriusV1Params,
        address freezeVotingAddress,
        address azoriusModuleAddress
    ) internal {
        if (freezeGuardAzoriusV1Params.implementation != address(0)) {
            if (azoriusModuleAddress == address(0)) {
                revert AzoriusModuleNotDeployed();
            }

            if (freezeVotingAddress == address(0)) {
                revert FreezeVotingContractNotDeployed();
            }

            address azoriusFreezeGuardAddress = deployProxy(
                freezeGuardAzoriusV1Params.implementation,
                abi.encodeCall(
                    IFreezeGuardAzoriusV1.initialize,
                    (freezeGuardAzoriusV1Params.owner, freezeVotingAddress)
                ),
                salt_
            );

            // add azorius freeze guard to Azorius module
            // Azorius Module has same "setGuard" function signature as Safe
            ISafe(azoriusModuleAddress).setGuard(azoriusFreezeGuardAddress);
        }
    }

    /**
     * @notice Deploys FreezeVotingStandaloneV1 with voting configs
     * @dev Handles the circular dependency between FreezeVotingStandalone and VoteTrackers
     * by using a two-step initialization process.
     * @param salt_ Salt for deterministic deployment
     * @param freezeVotingStandaloneParams Parameters for standalone freeze voting and its voting configs
     * @param newVotesERC20V1Addresses_ Addresses of newly deployed governance tokens
     * @return freezeVotingAddress The deployed freeze voting standalone address
     */
    function _deployFreezeVotingStandalone(
        bytes32 salt_,
        FreezeVotingStandaloneParams memory freezeVotingStandaloneParams,
        address[] memory newVotesERC20V1Addresses_
    ) internal returns (address) {
        // Step 1: Deploy FreezeVotingStandalone without voting configs
        // This gives us a deterministic address we can use for vote tracker authorization
        address freezeVotingAddress = deployProxy(
            freezeVotingStandaloneParams
                .freezeVotingStandaloneV1Params
                .implementation,
            abi.encodeCall(
                IFreezeVotingStandaloneV1.initialize,
                (
                    freezeVotingStandaloneParams
                        .freezeVotingStandaloneV1Params
                        .freezeVotesThreshold,
                    freezeVotingStandaloneParams
                        .freezeVotingStandaloneV1Params
                        .unfreezeVotesThreshold,
                    freezeVotingStandaloneParams
                        .freezeVotingStandaloneV1Params
                        .freezeProposalPeriod,
                    freezeVotingStandaloneParams
                        .freezeVotingStandaloneV1Params
                        .unfreezeProposalPeriod,
                    freezeVotingStandaloneParams
                        .freezeVotingStandaloneV1Params
                        .lightAccountFactory
                )
            ),
            salt_
        );

        // Step 2: Deploy voting configs with FreezeVotingStandalone as authorized caller
        IVotingTypes.VotingConfig[] memory votingConfigs = _deployVotingConfigs(
            salt_,
            freezeVotingStandaloneParams.votingConfigParams,
            newVotesERC20V1Addresses_,
            freezeVotingAddress // Use freeze voting as authorized caller
        );

        // Step 3: Complete initialization by setting the voting configs
        IFreezeVotingStandaloneV1(freezeVotingAddress).initialize2(
            votingConfigs
        );

        return freezeVotingAddress;
    }
}
