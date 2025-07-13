// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CREATE2Factory
 * @notice Factory contract for deploying contracts with deterministic addresses using CREATE2
 * @dev Allows deploying any contract to a predictable address across multiple chains
 */
contract CREATE2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt, address indexed deployer);
    
    /**
     * @notice Get the address where a contract will be deployed using CREATE2
     * @param salt The salt for deterministic deployment
     * @param bytecode The creation bytecode of the contract to deploy
     * @return The address where the contract will be deployed
     */
    function getAddress(bytes32 salt, bytes memory bytecode) public view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(bytecode)
                        )
                    )
                )
            )
        );
    }

    /**
     * @notice Deploy a contract using CREATE2
     * @param salt The salt for deterministic deployment
     * @param bytecode The creation bytecode of the contract to deploy
     * @return addr The address of the deployed contract
     */
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address addr) {
        require(bytecode.length > 0, "Bytecode is empty");
        
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        
        require(addr != address(0), "CREATE2 deployment failed");
        
        emit Deployed(addr, salt, msg.sender);
    }

    /**
     * @notice Deploy a contract using CREATE2 and call an initialization function
     * @param salt The salt for deterministic deployment
     * @param bytecode The creation bytecode of the contract to deploy
     * @param init The initialization calldata
     * @return addr The address of the deployed contract
     */
    function deployAndInit(
        bytes32 salt,
        bytes memory bytecode,
        bytes memory init
    ) public returns (address addr) {
        addr = deploy(salt, bytecode);
        
        if (init.length > 0) {
            (bool success, bytes memory reason) = addr.call(init);
            require(success, string(reason));
        }
    }

    /**
     * @notice Compute the salt for a given deployer and nonce
     * @param deployer The address of the deployer
     * @param nonce A nonce to make the salt unique
     * @return The computed salt
     */
    function computeSalt(address deployer, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, nonce));
    }

    /**
     * @notice Check if a contract is already deployed at a given address
     * @param addr The address to check
     * @return True if a contract exists at the address
     */
    function isDeployed(address addr) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}