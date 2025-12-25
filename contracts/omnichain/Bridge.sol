// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";

/// @title Bridge interface for OmnichainLP
interface IBridge {
    function bridge(address token, uint256 amount, uint256 destChainId, bytes calldata extraData) external payable;
    function estimateFee(uint256 destChainId) external view returns (uint256);
}

/// @title Bridge implementation for OmnichainLP with cross-chain token support
abstract contract Bridge {
    /// @notice Token types supported by the bridge
    enum Type {
        ERC20,
        ERC721,
        ERC1155,
        NATIVE
    }

    /// @notice Token representation for cross-chain operations
    struct Token {
        Type kind;
        uint256 id;
        uint256 chainId;
        address tokenAddress;
        bool enabled;
    }

    /// @notice Emit when tokens are bridged
    event Bridged(address indexed token, uint256 amount, uint256 indexed destChainId);
    
    /// @notice Emit when a swap is initiated
    event SwapInitiated(
        address indexed fromToken,
        address indexed toToken,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    /// @notice Bridge tokens to another chain
    function _bridge(address token, uint256 amount, uint256 destChainId, bytes calldata extraData) internal virtual;

    /// @notice Estimate fee for bridging
    function _estimateFee(uint256 destChainId) internal view virtual returns (uint256);

    /// @notice Swap tokens across chains
    function swap(
        Token memory fromToken,
        Token memory toToken,
        address recipient,
        uint256 amount,
        uint256 deadline
    ) external virtual;

    /// @notice Register a token for bridging
    function setToken(Token memory token) external virtual;
}
