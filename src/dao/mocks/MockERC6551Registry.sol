// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

/**
 * @title MockERC6551Registry
 * @dev Mock implementation of ERC6551 Registry for testing purposes.
 * Provides functionality needed for testing UtilityRolesManagementV1.
 */
contract MockERC6551Registry {
    // Track created accounts for testing
    mapping(bytes32 => address) public accounts;

    // Counter for generating predictable addresses
    uint256 private accountCounter;

    /**
     * @dev Create a token-bound account
     * @param implementation The implementation address
     * @param salt The salt for deterministic deployment
     * @param chainId The chain ID
     * @param tokenContract The token contract address
     * @param tokenId The token ID
     * @return accountAddress The created account address
     */
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address accountAddress) {
        // Create deterministic key for the account
        bytes32 key = keccak256(
            abi.encodePacked(
                implementation,
                salt,
                chainId,
                tokenContract,
                tokenId
            )
        );

        // Check if account already exists
        if (accounts[key] != address(0)) {
            return accounts[key];
        }

        // Generate a predictable address for testing
        accountCounter++;
        accountAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(key, accountCounter))))
        );
        accounts[key] = accountAddress;

        return accountAddress;
    }

    /**
     * @dev Get the address of a token-bound account
     * @param implementation The implementation address
     * @param salt The salt for deterministic deployment
     * @param chainId The chain ID
     * @param tokenContract The token contract address
     * @param tokenId The token ID
     * @return The account address (returns zero if not created)
     */
    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view returns (address) {
        bytes32 key = keccak256(
            abi.encodePacked(
                implementation,
                salt,
                chainId,
                tokenContract,
                tokenId
            )
        );
        return accounts[key];
    }
}
