// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/HanzoRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployRegistry
 * @dev Deploy core HanzoRegistry (works on ANY EVM chain)
 *
 * Usage:
 * forge script script/DeployRegistry.s.sol:DeployRegistry --rpc-url $RPC_URL --broadcast
 *
 * Networks (works on ANY EVM):
 * - Hanzo: --rpc-url https://rpc.hanzo.ai
 * - Zoo: --rpc-url https://rpc.zoo.network
 * - Lux C-Chain: --rpc-url https://api.lux.network/ext/bc/C/rpc
 * - Ethereum: --rpc-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
 * - Any EVM-compatible chain
 */
contract DeployRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying HanzoRegistry to chain:", block.chainid);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy simple NFT for identity binding
        SimpleIdentityNFT identityNft = new SimpleIdentityNFT();
        console.log("IdentityNFT deployed at:", address(identityNft));

        // 2. Deploy HanzoRegistry implementation
        HanzoRegistry registryImpl = new HanzoRegistry();
        console.log("Registry implementation:", address(registryImpl));

        // 3. Deploy proxy
        // Note: aiToken can be address(0) if not using AI features
        address aiToken = address(0); // Override with env var if needed
        if (vm.envOr("AI_TOKEN_ADDRESS", address(0)) != address(0)) {
            aiToken = vm.envAddress("AI_TOKEN_ADDRESS");
        }

        bytes memory initData = abi.encodeWithSelector(
            HanzoRegistry.initialize.selector,
            deployer, // admin
            aiToken,  // AI token (0x0 if not using)
            address(identityNft)
        );

        ERC1967Proxy registryProxy = new ERC1967Proxy(
            address(registryImpl),
            initData
        );
        console.log("Registry proxy deployed at:", address(registryProxy));

        // 4. Grant registry permission to mint NFTs
        identityNft.grantMinterRole(address(registryProxy));
        console.log("Granted minter role to registry");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("HanzoRegistry (Proxy):", address(registryProxy));
        console.log("HanzoRegistry (Implementation):", address(registryImpl));
        console.log("IdentityNFT:", address(identityNft));
        console.log("AI Token:", aiToken == address(0) ? "Not configured" : vm.toString(aiToken));
    }
}

/**
 * @dev Minimal NFT for identity binding (works on any chain)
 */
contract SimpleIdentityNFT {
    uint256 private _tokenIdCounter;
    mapping(uint256 => address) private _owners;
    mapping(address => bool) public minters;
    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    constructor() {
        owner = msg.sender;
        minters[msg.sender] = true;
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "Not a minter");
        _;
    }

    function grantMinterRole(address minter) external {
        require(msg.sender == owner, "Not owner");
        minters[minter] = true;
    }

    function mint(address to) external onlyMinter returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function burn(uint256 tokenId) external {
        require(_owners[tokenId] == msg.sender, "Not owner");
        delete _owners[tokenId];
        emit Transfer(msg.sender, address(0), tokenId);
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }
}
