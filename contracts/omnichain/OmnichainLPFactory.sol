// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { OmnichainLP } from "./OmnichainLP.sol";
import { Ownable } from "@luxfi/standard/lib/access/Ownable.sol";
import { Bridge } from "./Bridge.sol";

/**
 * @title OmnichainLPFactory
 * @dev Factory contract for deploying OmnichainLP pairs with bridge integration
 */
contract OmnichainLPFactory is Ownable {
    // Bridge contract reference
    Bridge public immutable bridge;
    
    // Mapping of token pairs to LP addresses
    mapping(address => mapping(address => address)) public getPair;
    
    // Array of all LP pairs
    address[] public allPairs;
    
    // Chain-specific pair tracking
    mapping(uint256 => address[]) public chainPairs;
    
    // Fee recipient for protocol fees
    address public feeRecipient;
    
    // Events
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);
    event BridgeUpdated(address indexed newBridge);
    event FeeRecipientUpdated(address indexed newRecipient);
    
    constructor(address _bridge, address _feeRecipient) Ownable(msg.sender) {
        require(_bridge != address(0), "OmnichainLPFactory: Invalid bridge");
        require(_feeRecipient != address(0), "OmnichainLPFactory: Invalid fee recipient");

        bridge = Bridge(_bridge);
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @dev Create a new OmnichainLP pair
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "OmnichainLPFactory: Identical addresses");
        require(tokenA != address(0) && tokenB != address(0), "OmnichainLPFactory: Zero address");
        
        // Sort tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(getPair[token0][token1] == address(0), "OmnichainLPFactory: Pair exists");
        
        // Generate pair name and symbol
        string memory name = string(abi.encodePacked("Lux Omnichain LP"));
        string memory symbol = string(abi.encodePacked("LUX-OLP"));
        
        // Deploy new OmnichainLP contract
        bytes memory bytecode = type(OmnichainLP).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        
        // Initialize the pair
        OmnichainLP(pair).initialize(address(bridge), token0, token1, name, symbol);
        
        // Update mappings
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // Bidirectional mapping
        allPairs.push(pair);
        chainPairs[block.chainid].push(pair);
        
        // Register pair with bridge
        _registerPairWithBridge(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    /**
     * @dev Register an LP pair with the bridge for cross-chain support
     */
    function _registerPairWithBridge(address pair) internal {
        Bridge.Token memory token = Bridge.Token({
            kind: Bridge.Type.ERC20,
            id: 0,
            chainId: block.chainid,
            tokenAddress: pair,
            enabled: true
        });
        
        bridge.setToken(token);
    }
    
    /**
     * @dev Get all pairs count
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
    
    /**
     * @dev Get pairs on specific chain
     */
    function getChainPairs(uint256 chainId) external view returns (address[] memory) {
        return chainPairs[chainId];
    }
    
    /**
     * @dev Update fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "OmnichainLPFactory: Invalid fee recipient");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }
    
    /**
     * @dev Calculate CREATE2 address for a pair
     */
    function calculatePairAddress(address token0, address token1) external view returns (address) {
        require(token0 < token1, "OmnichainLPFactory: Invalid token order");
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(type(OmnichainLP).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}