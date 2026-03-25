// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {AMMV2Pair} from "./AMMV2Pair.sol";

/// @title AMMV2Factory - Uniswap V2 Compatible Factory
/// @notice Creates and manages LP pairs for token swaps
/// @dev Compatible with Uniswap V2 interface for ecosystem integration
contract AMMV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "AMMV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "AMMV2: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "AMMV2: PAIR_EXISTS");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new AMMV2Pair{salt: salt}());
        AMMV2Pair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /// @notice Pre-compute the address a pair would be deployed to
    /// @param tokenA One of the two tokens in the pair
    /// @param tokenB The other token in the pair
    /// @return The deterministic address via CREATE2
    function computeAddress(address tokenA, address tokenB) external view returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 hash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(type(AMMV2Pair).creationCode)
        ));
        return address(uint160(uint256(hash)));
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "AMMV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "AMMV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
