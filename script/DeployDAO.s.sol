// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "./DeployConfig.s.sol";

// Safe imports (from @safe-global/safe-smart-account)
import {Safe} from "@safe-global/safe-smart-account/Safe.sol";
import {SafeL2} from "@safe-global/safe-smart-account/SafeL2.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/proxies/SafeProxy.sol";
import {MultiSend} from "@safe-global/safe-smart-account/libraries/MultiSend.sol";
import {MultiSendCallOnly} from "@safe-global/safe-smart-account/libraries/MultiSendCallOnly.sol";
import {CompatibilityFallbackHandler} from "@safe-global/safe-smart-account/handler/CompatibilityFallbackHandler.sol";

// Lux Safe extensions
import {LuxSafeFactory} from "../contracts/safe/LuxSafeFactory.sol";

// Governance imports
import {VotesToken} from "../contracts/dao/governance/VotesToken.sol";
import {LuxGovernor} from "../contracts/dao/governance/LuxGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title DeployDAO
/// @notice Deploys Safe infrastructure and DAO governance for Lux Network
/// @dev Deploys:
///   1. Safe singleton contracts (Safe, SafeL2)
///   2. Safe infrastructure (Factory, MultiSend, FallbackHandler)
///   3. Governance token (VotesToken)
///   4. Timelock Controller
///   5. Governor contract
contract DeployDAO is Script, DeployConfig {

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    struct SafeDeployment {
        // Singletons
        address safeSingleton;
        address safeL2Singleton;

        // Infrastructure
        address safeProxyFactory;
        address luxSafeFactory;
        address multiSend;
        address multiSendCallOnly;
        address fallbackHandler;
    }

    struct GovernanceDeployment {
        address votesToken;
        address timelock;
        address governor;
    }

    struct DAODeployment {
        SafeDeployment safe;
        GovernanceDeployment governance;
    }

    DAODeployment public deployment;

    // ═══════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    // Governance parameters (can be overridden)
    string public constant TOKEN_NAME = "Delegated Lux";
    string public constant TOKEN_SYMBOL = "DLUX";
    uint256 public constant MAX_SUPPLY = 100_000_000e18; // 100M max supply (no initial)

    // Governor parameters
    uint48 public constant VOTING_DELAY = 7200;      // ~1 day (12s blocks)
    uint32 public constant VOTING_PERIOD = 50400;    // ~7 days (12s blocks)
    uint256 public constant PROPOSAL_THRESHOLD = 100_000e18; // 100K tokens
    uint256 public constant QUORUM_PERCENTAGE = 4;   // 4%

    // Timelock delay
    uint256 public constant TIMELOCK_MIN_DELAY = 2 days;

    // ═══════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════

    function run() public virtual {
        _initConfigs();
        ChainConfig memory config = getConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("");
        console.log("+==============================================================+");
        console.log("|          LUX DAO & SAFE INFRASTRUCTURE DEPLOYMENT            |");
        console.log("+==============================================================+");
        console.log("|  Chain ID:", block.chainid);
        console.log("|  Deployer:", deployer);
        console.log("|  Network:", _getNetworkName());
        console.log("+==============================================================+");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Phase 1: Safe Infrastructure
        console.log("================================================================");
        console.log("  PHASE 1: Safe Infrastructure");
        console.log("================================================================");
        _deploySafeInfrastructure();

        // Phase 2: Governance System
        console.log("");
        console.log("================================================================");
        console.log("  PHASE 2: Governance System");
        console.log("================================================================");
        _deployGovernance(deployer, config);

        vm.stopBroadcast();

        _printSummary();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT PHASES
    // ═══════════════════════════════════════════════════════════════════════

    function _deploySafeInfrastructure() internal {
        console.log("  Deploying Safe singletons and infrastructure...");

        // Deploy Safe singleton (for mainnet use)
        Safe safeSingleton = new Safe();
        deployment.safe.safeSingleton = address(safeSingleton);
        console.log("    Safe Singleton:", deployment.safe.safeSingleton);

        // Deploy SafeL2 singleton (for L2/subnet use with events)
        SafeL2 safeL2Singleton = new SafeL2();
        deployment.safe.safeL2Singleton = address(safeL2Singleton);
        console.log("    SafeL2 Singleton:", deployment.safe.safeL2Singleton);

        // Deploy standard SafeProxyFactory
        SafeProxyFactory proxyFactory = new SafeProxyFactory();
        deployment.safe.safeProxyFactory = address(proxyFactory);
        console.log("    SafeProxyFactory:", deployment.safe.safeProxyFactory);

        // Deploy Lux-branded SafeFactory
        LuxSafeFactory luxFactory = new LuxSafeFactory();
        deployment.safe.luxSafeFactory = address(luxFactory);
        console.log("    LuxSafeFactory:", deployment.safe.luxSafeFactory);

        // Deploy MultiSend for batched transactions
        MultiSend multiSend = new MultiSend();
        deployment.safe.multiSend = address(multiSend);
        console.log("    MultiSend:", deployment.safe.multiSend);

        // Deploy MultiSendCallOnly (safer, no delegatecalls)
        MultiSendCallOnly multiSendCallOnly = new MultiSendCallOnly();
        deployment.safe.multiSendCallOnly = address(multiSendCallOnly);
        console.log("    MultiSendCallOnly:", deployment.safe.multiSendCallOnly);

        // Deploy Fallback Handler
        CompatibilityFallbackHandler fallbackHandler = new CompatibilityFallbackHandler();
        deployment.safe.fallbackHandler = address(fallbackHandler);
        console.log("    FallbackHandler:", deployment.safe.fallbackHandler);
    }

    function _deployGovernance(address deployer, ChainConfig memory) internal {
        console.log("  Deploying governance system...");

        // 1. Deploy governance token with no initial supply
        // DLUX is minted via governance proposals or staking mechanisms
        VotesToken.Allocation[] memory allocations = new VotesToken.Allocation[](0);

        VotesToken votesToken = new VotesToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            allocations,
            deployer,    // Owner (can mint via governance)
            MAX_SUPPLY,  // 100M max supply
            false        // Not locked
        );
        deployment.governance.votesToken = address(votesToken);
        console.log("    DLUX:", deployment.governance.votesToken);

        // 2. Deploy Timelock Controller
        address[] memory proposers = new address[](0); // Governor will be proposer
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        TimelockController timelock = new TimelockController(
            TIMELOCK_MIN_DELAY,
            proposers,
            executors,
            deployer  // Admin (should renounce after setup)
        );
        deployment.governance.timelock = address(timelock);
        console.log("    TimelockController:", deployment.governance.timelock);

        // 3. Deploy Governor
        LuxGovernor governor = new LuxGovernor(
            IVotes(address(votesToken)),
            timelock,
            "Lux DAO Governor",
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_PERCENTAGE
        );
        deployment.governance.governor = address(governor);
        console.log("    LuxGovernor:", deployment.governance.governor);

        // 4. Configure Timelock roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();

        // Grant proposer role to Governor
        timelock.grantRole(proposerRole, address(governor));

        // Grant canceller role to Governor
        timelock.grantRole(cancellerRole, address(governor));

        console.log("    Timelock roles configured");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════

    function _getNetworkName() internal view returns (string memory) {
        if (block.chainid == LUX_MAINNET) return "Lux Mainnet";
        if (block.chainid == LUX_TESTNET) return "Lux Testnet";
        if (block.chainid == HANZO_MAINNET) return "Hanzo Mainnet";
        if (block.chainid == HANZO_TESTNET) return "Hanzo Testnet";
        if (block.chainid == ZOO_MAINNET) return "Zoo Mainnet";
        if (block.chainid == ZOO_TESTNET) return "Zoo Testnet";
        if (block.chainid == 31337) return "Anvil (Local)";
        return "Unknown";
    }

    function _printSummary() internal view {
        console.log("");
        console.log("+==============================================================+");
        console.log("|                 DAO DEPLOYMENT COMPLETE                      |");
        console.log("+==============================================================+");
        console.log("|  SAFE INFRASTRUCTURE                                         |");
        console.log("|    Safe Singleton:", deployment.safe.safeSingleton);
        console.log("|    SafeL2 Singleton:", deployment.safe.safeL2Singleton);
        console.log("|    SafeProxyFactory:", deployment.safe.safeProxyFactory);
        console.log("|    LuxSafeFactory:", deployment.safe.luxSafeFactory);
        console.log("|    MultiSend:", deployment.safe.multiSend);
        console.log("|    MultiSendCallOnly:", deployment.safe.multiSendCallOnly);
        console.log("|    FallbackHandler:", deployment.safe.fallbackHandler);
        console.log("+==============================================================+");
        console.log("|  GOVERNANCE                                                  |");
        console.log("|    DLUX:", deployment.governance.votesToken);
        console.log("|    TimelockController:", deployment.governance.timelock);
        console.log("|    LuxGovernor:", deployment.governance.governor);
        console.log("+==============================================================+");
        console.log("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPER: Create a Safe via Factory
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Helper to create a new Safe multisig
    /// @param owners Array of owner addresses
    /// @param threshold Number of required signatures
    /// @param useL2 Whether to use SafeL2 (for L2/subnets)
    /// @return safe Address of the created Safe
    function createSafe(
        address[] memory owners,
        uint256 threshold,
        bool useL2
    ) public returns (address safe) {
        address singleton = useL2
            ? deployment.safe.safeL2Singleton
            : deployment.safe.safeSingleton;

        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            threshold,
            address(0),  // to (optional delegate call target)
            "",          // data (optional delegate call data)
            deployment.safe.fallbackHandler,
            address(0),  // payment token (0 = ETH)
            0,           // payment
            payable(address(0))  // payment receiver
        );

        SafeProxy proxy = SafeProxyFactory(deployment.safe.safeProxyFactory)
            .createProxyWithNonce(
                singleton,
                initializer,
                uint256(keccak256(abi.encodePacked(owners, threshold, block.timestamp)))
            );

        return address(proxy);
    }
}

/// @title DeployDAOLocal
/// @notice Local Anvil deployment
contract DeployDAOLocal is DeployDAO {
    function run() public override {
        require(block.chainid == 31337, "Use Anvil");
        super.run();
    }
}

/// @title DeployDAOTestnet
/// @notice Testnet deployment
contract DeployDAOTestnet is DeployDAO {
    function run() public override {
        require(isTestnet(), "Wrong network");
        super.run();
    }
}

/// @title DeployDAOMainnet
/// @notice Mainnet deployment
contract DeployDAOMainnet is DeployDAO {
    function run() public override {
        require(block.chainid == LUX_MAINNET, "Wrong network");
        super.run();
    }
}
