// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Bridge interface for OmnichainLP
interface IBridge {
    function bridge(address token, uint256 amount, uint256 destChainId, bytes calldata extraData) external payable;
    function estimateFee(uint256 destChainId) external view returns (uint256);
}

/// @title Simple Bridge implementation for OmnichainLP
abstract contract Bridge {
    /// @notice Emit when tokens are bridged
    event Bridged(address indexed token, uint256 amount, uint256 indexed destChainId);
    
    /// @notice Bridge tokens to another chain
    function _bridge(address token, uint256 amount, uint256 destChainId, bytes calldata extraData) internal virtual;
    
    /// @notice Estimate fee for bridging
    function _estimateFee(uint256 destChainId) internal view virtual returns (uint256);
}
