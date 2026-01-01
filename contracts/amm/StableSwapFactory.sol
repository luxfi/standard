// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {StableSwap} from "./StableSwap.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title StableSwapFactory
 * @author Lux Industries
 * @notice Factory for deploying StableSwap (Curve-style) pools
 * @dev Manages pool registry and provides standard fee structures
 */
contract StableSwapFactory is AccessControl {

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /// @notice Standard fee for stablecoin pools (0.04%)
    uint256 public constant STABLECOIN_FEE = 4e6;

    /// @notice Standard fee for metapools (0.08%)
    uint256 public constant METAPOOL_FEE = 8e6;

    /// @notice Standard admin fee (50% of swap fee)
    uint256 public constant STANDARD_ADMIN_FEE = 5e9;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Array of all deployed pools
    address[] public allPools;

    /// @notice Pool for a given pair of tokens (sorted)
    mapping(bytes32 => address) public getPool;

    /// @notice Base pool for metapools
    mapping(address => bool) public isBasePool;

    /// @notice Pool implementation for clones (future use)
    address public poolImplementation;

    /// @notice Fee receiver address
    address public feeReceiver;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PoolCreated(
        address indexed pool,
        address[] tokens,
        uint256 A,
        uint256 fee,
        string name,
        string symbol
    );

    event BasePoolSet(address indexed pool, bool isBase);
    event FeeReceiverUpdated(address indexed receiver);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error PoolExists();
    error InvalidTokens();
    error ZeroAddress();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _admin, address _feeReceiver) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_feeReceiver == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(DEPLOYER_ROLE, _admin);

        feeReceiver = _feeReceiver;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POOL CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploy a new stablecoin pool
     * @param tokens Array of token addresses (2-4 stablecoins)
     * @param A Amplification coefficient (typically 100-2000 for stables)
     * @param name LP token name
     * @param symbol LP token symbol
     * @return pool Address of deployed pool
     */
    function deployStablePool(
        address[] calldata tokens,
        uint256 A,
        string calldata name,
        string calldata symbol
    ) external onlyRole(DEPLOYER_ROLE) returns (address pool) {
        return _deployPool(tokens, A, STABLECOIN_FEE, STANDARD_ADMIN_FEE, name, symbol);
    }

    /**
     * @notice Deploy a custom fee pool
     * @param tokens Array of token addresses
     * @param A Amplification coefficient
     * @param fee Swap fee (in FEE_DENOMINATOR units)
     * @param adminFee Admin fee as % of swap fee
     * @param name LP token name
     * @param symbol LP token symbol
     * @return pool Address of deployed pool
     */
    function deployPool(
        address[] calldata tokens,
        uint256 A,
        uint256 fee,
        uint256 adminFee,
        string calldata name,
        string calldata symbol
    ) external onlyRole(DEPLOYER_ROLE) returns (address pool) {
        return _deployPool(tokens, A, fee, adminFee, name, symbol);
    }

    /**
     * @notice Deploy a metapool using a base pool
     * @param basePool Address of base StableSwap pool
     * @param token New token to pair with base pool LP
     * @param A Amplification coefficient
     * @param name LP token name
     * @param symbol LP token symbol
     * @return pool Address of deployed metapool
     */
    function deployMetapool(
        address basePool,
        address token,
        uint256 A,
        string calldata name,
        string calldata symbol
    ) external onlyRole(DEPLOYER_ROLE) returns (address pool) {
        if (!isBasePool[basePool]) revert InvalidTokens();

        address[] memory tokens = new address[](2);
        tokens[0] = token;
        tokens[1] = basePool; // Base pool LP token

        return _deployPool(tokens, A, METAPOOL_FEE, STANDARD_ADMIN_FEE, name, symbol);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _deployPool(
        address[] memory tokens,
        uint256 A,
        uint256 fee,
        uint256 adminFee,
        string memory name,
        string memory symbol
    ) internal returns (address pool) {
        if (tokens.length < 2 || tokens.length > 4) revert InvalidTokens();

        // Check for duplicates and get pool key
        bytes32 poolKey = _getPoolKey(tokens);
        if (getPool[poolKey] != address(0)) revert PoolExists();

        // Get decimals for each token
        uint256[] memory decimals = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidTokens();
            decimals[i] = IERC20Metadata(tokens[i]).decimals();
        }

        // Deploy pool
        StableSwap newPool = new StableSwap(
            tokens,
            decimals,
            name,
            symbol,
            A,
            fee,
            adminFee,
            feeReceiver
        );

        pool = address(newPool);
        getPool[poolKey] = pool;
        allPools.push(pool);

        emit PoolCreated(pool, tokens, A, fee, name, symbol);
    }

    function _getPoolKey(address[] memory tokens) internal pure returns (bytes32) {
        // Sort tokens for consistent key
        address[] memory sorted = _sortTokens(tokens);
        return keccak256(abi.encodePacked(sorted));
    }

    function _sortTokens(address[] memory tokens) internal pure returns (address[] memory) {
        address[] memory sorted = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            sorted[i] = tokens[i];
        }

        // Simple bubble sort (ok for small arrays)
        for (uint256 i = 0; i < sorted.length - 1; i++) {
            for (uint256 j = 0; j < sorted.length - i - 1; j++) {
                if (sorted[j] > sorted[j + 1]) {
                    (sorted[j], sorted[j + 1]) = (sorted[j + 1], sorted[j]);
                }
            }
        }
        return sorted;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Mark a pool as base pool for metapools
    function setBasePool(address pool, bool _isBase) external onlyRole(ADMIN_ROLE) {
        isBasePool[pool] = _isBase;
        emit BasePoolSet(pool, _isBase);
    }

    /// @notice Update fee receiver
    function setFeeReceiver(address _feeReceiver) external onlyRole(ADMIN_ROLE) {
        if (_feeReceiver == address(0)) revert ZeroAddress();
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get total number of pools
    function poolCount() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Get all pools
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    /// @notice Find pool for tokens
    function findPool(address[] calldata tokens) external view returns (address) {
        return getPool[_getPoolKey(tokens)];
    }
}
