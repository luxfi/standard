// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IRegulatedProvider.sol";

/// @title NullProvider — default no-op provider.
/// @notice Used by Lux exchange forks that operate in open-DeFi mode only
///         (crypto-to-crypto, no regulated securities). Returns
///         "not-handled" for every symbol so the router falls through to
///         native Lux AMM/DEX liquidity. Zero gas overhead on the hot path.
contract NullProvider is IRegulatedProvider {
    function isEligible(address, string calldata) external pure override returns (bool, uint8) {
        return (false, 255); // provider disabled
    }

    function handles(string calldata) external pure override returns (bool) {
        return false;
    }

    function onboard(address, bytes calldata) external pure override {
        revert("NullProvider: regulated flow disabled");
    }

    function bestPrice(string calldata, Side) external pure override returns (uint256) {
        return 0;
    }

    function routedSwap(address, address, address, uint256, uint256, string calldata)
        external
        pure
        override
        returns (uint256)
    {
        revert("NullProvider: regulated flow disabled");
    }
}
