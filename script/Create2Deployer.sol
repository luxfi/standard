// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Create2Deployer
/// @notice Deterministic deployment factory using CREATE2
/// @dev Deploy this contract first at same address on all chains, then deploy all other contracts through it
///
/// DEPLOYMENT STRATEGY:
/// 1. Deploy Create2Deployer using a vanity address or keyless deployment
/// 2. Use consistent salts for each contract across all chains
/// 3. This ensures identical addresses across Lux Mainnet, Testnet, Hanzo, Zoo
contract Create2Deployer {
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event ContractDeployed(
        address indexed deployer,
        address indexed deployed,
        bytes32 indexed salt,
        bytes32 bytecodeHash
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error DeploymentFailed();
    error ZeroAddress();
    error AlreadyDeployed(address existing);

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Track deployed contracts to prevent double deployment
    mapping(bytes32 => address) public deployedContracts;

    /// @notice Deployment nonce for each deployer (for generating unique salts)
    mapping(address => uint256) public deployerNonce;

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Deploy contract using CREATE2 with explicit salt
    /// @param salt The salt for CREATE2 (should be same across all chains)
    /// @param bytecode The contract creation bytecode (including constructor args)
    /// @return deployed The deployed contract address
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address deployed) {
        bytes32 bytecodeHash = keccak256(bytecode);

        // Check if already deployed
        bytes32 key = keccak256(abi.encodePacked(salt, bytecodeHash));
        if (deployedContracts[key] != address(0)) {
            revert AlreadyDeployed(deployedContracts[key]);
        }

        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        if (deployed == address(0)) revert DeploymentFailed();

        deployedContracts[key] = deployed;

        emit ContractDeployed(msg.sender, deployed, salt, bytecodeHash);
    }

    /// @notice Deploy contract with deployer-specific salt prefix
    /// @dev Salt = keccak256(deployer, contractName)
    /// @param contractName Human-readable name for the contract
    /// @param bytecode The contract creation bytecode
    /// @return deployed The deployed contract address
    function deployNamed(string calldata contractName, bytes memory bytecode) external returns (address deployed) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, contractName));
        return this.deploy(salt, bytecode);
    }

    /// @notice Deploy and initialize in one transaction (for proxies)
    /// @param salt The salt for CREATE2
    /// @param bytecode The contract creation bytecode
    /// @param initData The initialization calldata
    /// @return deployed The deployed contract address
    function deployAndInit(
        bytes32 salt,
        bytes memory bytecode,
        bytes calldata initData
    ) external returns (address deployed) {
        deployed = this.deploy(salt, bytecode);

        if (initData.length > 0) {
            (bool success, ) = deployed.call(initData);
            require(success, "Initialization failed");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Compute the address that would be deployed for given salt and bytecode
    /// @param salt The CREATE2 salt
    /// @param bytecodeHash The keccak256 hash of the creation bytecode
    /// @return The predicted contract address
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }

    /// @notice Compute address from raw bytecode (convenience function)
    /// @param salt The CREATE2 salt
    /// @param bytecode The creation bytecode
    /// @return The predicted contract address
    function computeAddressFromBytecode(bytes32 salt, bytes memory bytecode) external view returns (address) {
        return this.computeAddress(salt, keccak256(bytecode));
    }

    /// @notice Check if a contract can be deployed (not already deployed)
    /// @param salt The CREATE2 salt
    /// @param bytecodeHash The bytecode hash
    /// @return True if deployment is possible
    function canDeploy(bytes32 salt, bytes32 bytecodeHash) external view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(salt, bytecodeHash));
        return deployedContracts[key] == address(0);
    }
}

/// @title Create2DeployerKeyless
/// @notice Keyless deployment for getting same address across all chains
/// @dev Uses Nick's method (EIP-2470 style)
///
/// Steps to deploy Create2Deployer at same address on all chains:
/// 1. Generate a deployment transaction with fixed gas price and no chain ID
/// 2. Sign it with a known private key (use a burner, never use for real funds)
/// 3. Fund the sender address on each chain
/// 4. Broadcast the same raw transaction on each chain
///
/// Alternative: Use existing deterministic deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
library Create2DeployerKeyless {
    /// @notice Standard deterministic deployer (EIP-2470)
    address constant DETERMINISTIC_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Check if deterministic deployer exists on current chain
    function hasDeployer() internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(DETERMINISTIC_DEPLOYER)
        }
        return size > 0;
    }

    /// @notice Deploy through standard deterministic deployer
    function deploy(bytes32 salt, bytes memory bytecode) internal returns (address deployed) {
        require(hasDeployer(), "No deterministic deployer on this chain");

        bytes memory data = abi.encodePacked(salt, bytecode);
        (bool success, bytes memory result) = DETERMINISTIC_DEPLOYER.call(data);
        require(success && result.length == 20, "Deployment failed");

        assembly {
            deployed := mload(add(result, 20))
        }
    }
}
