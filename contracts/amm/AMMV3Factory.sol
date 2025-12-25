// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "./AMMV3Pool.sol";

/// @title AMMV3Factory - Uniswap V3 Compatible Factory
/// @notice Creates and manages concentrated liquidity pools
/// @dev Supports multiple fee tiers with corresponding tick spacings
contract AMMV3Factory {
    /// @notice Emitted when a new pool is created
    event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool);

    /// @notice Emitted when a new fee amount is enabled
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    /// @notice Emitted when owner is changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    address public owner;

    /// @notice Returns the tick spacing for a given fee amount
    mapping(uint24 => int24) public feeAmountTickSpacing;

    /// @notice Returns the pool address for a given pair of tokens and fee
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    /// @notice All pools created by this factory
    address[] public allPools;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // Initialize fee tiers (fee in hundredths of a bip, i.e. 1e-6)
        feeAmountTickSpacing[100] = 1;      // 0.01% - stablecoins
        feeAmountTickSpacing[500] = 10;     // 0.05% - stable pairs
        feeAmountTickSpacing[3000] = 60;    // 0.30% - standard pairs
        feeAmountTickSpacing[10000] = 200;  // 1.00% - exotic pairs

        emit FeeAmountEnabled(100, 1);
        emit FeeAmountEnabled(500, 10);
        emit FeeAmountEnabled(3000, 60);
        emit FeeAmountEnabled(10000, 200);
    }

    /// @notice Returns the number of pools created
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Creates a pool for the given two tokens and fee
    /// @param tokenA One of the two tokens in the desired pool
    /// @param tokenB The other of the two tokens in the desired pool
    /// @param fee The desired fee for the pool
    /// @return pool The address of the newly created pool
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool) {
        require(tokenA != tokenB, "AMMV3: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "AMMV3: ZERO_ADDRESS");
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0, "AMMV3: FEE_NOT_ENABLED");
        require(getPool[token0][token1][fee] == address(0), "AMMV3: POOL_EXISTS");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1, fee));
        pool = address(new AMMV3Pool{salt: salt}());
        AMMV3Pool(pool).initialize(token0, token1, fee, tickSpacing);

        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool;
        allPools.push(pool);
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @notice Updates the owner of the factory
    /// @param _owner The new owner of the factory
    function setOwner(address _owner) external {
        require(msg.sender == owner, "AMMV3: NOT_OWNER");
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @notice Enables a fee amount with the given tickSpacing
    /// @param fee The fee amount to enable (in hundredths of a bip)
    /// @param tickSpacing The spacing between ticks for pools with this fee
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external {
        require(msg.sender == owner, "AMMV3: NOT_OWNER");
        require(fee < 1000000, "AMMV3: FEE_TOO_LARGE");
        require(tickSpacing > 0 && tickSpacing < 16384, "AMMV3: INVALID_TICK_SPACING");
        require(feeAmountTickSpacing[fee] == 0, "AMMV3: FEE_ALREADY_ENABLED");

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
