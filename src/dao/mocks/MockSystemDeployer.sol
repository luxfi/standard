// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockSystemDeployer
 * @dev Mock implementation of SystemDeployerV1 for testing purposes.
 * Provides functionality needed for testing UtilityRolesManagementV1.
 * Uses an external recorder contract to properly track delegatecall contexts.
 */
contract MockSystemDeployer {
    // Track deployed proxies
    mapping(bytes32 => address) public deployedProxies;

    // Track the deployer (address(this)) for each deployment
    mapping(address => address) public proxyDeployers;

    // Counter for generating predictable addresses
    uint256 private proxyCounter;

    // Event to track deployments
    event ProxyDeployed(
        address indexed implementation,
        address indexed proxy,
        address indexed deployer
    );

    /**
     * @dev Deploy a proxy (mock implementation)
     * @param implementation The implementation address
     * @param initData The initialization data
     * @param salt The salt for deterministic deployment
     * @return proxy The deployed proxy address
     */
    function deployProxy(
        address implementation,
        bytes calldata initData,
        bytes32 salt
    ) external returns (address proxy) {
        // In production, this would deploy a real proxy
        // For our mock, we'll use address(this) as the deployer to simulate
        // the delegatecall behavior where the Safe is the actual deployer
        address deployer = address(this);

        // Create deterministic key
        bytes32 key = keccak256(
            abi.encodePacked(implementation, initData, salt, deployer)
        );

        // Check if already deployed
        if (deployedProxies[key] != address(0)) {
            return deployedProxies[key];
        }

        // Generate predictable address
        proxyCounter++;
        proxy = address(
            uint160(uint256(keccak256(abi.encodePacked(key, proxyCounter))))
        );
        deployedProxies[key] = proxy;

        // Capture who deployed this proxy
        proxyDeployers[proxy] = deployer;

        // Proxy deployed

        emit ProxyDeployed(implementation, proxy, deployer);

        return proxy;
    }

    /**
     * @dev Predict the address of a proxy
     * @param implementation The implementation address
     * @param initData The initialization data
     * @param salt The salt for deterministic deployment
     * @param deployer The address that will deploy the proxy
     * @return predicted The predicted proxy address
     */
    function predictProxyAddress(
        address implementation,
        bytes calldata initData,
        bytes32 salt,
        address deployer
    ) external view returns (address predicted) {
        // For consistency with deployProxy, always use the deployer parameter
        // (which should be the Safe address when called from tests)
        bytes32 key = keccak256(
            abi.encodePacked(implementation, initData, salt, deployer)
        );

        // Return existing proxy if already deployed
        if (deployedProxies[key] != address(0)) {
            return deployedProxies[key];
        }

        // Otherwise predict the address
        uint256 nextCounter = proxyCounter + 1;
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(key, nextCounter))))
        );

        return predicted;
    }
}
