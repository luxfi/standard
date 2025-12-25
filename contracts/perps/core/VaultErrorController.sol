// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;


import "./interfaces/IVault.sol";
import "../access/Governable.sol";

contract VaultErrorController is Governable {
    function setErrors(IVault _vault, string[] calldata _errors) external onlyGov {
        for (uint256 i = 0; i < _errors.length; i++) {
            _vault.setError(i, _errors[i]);
        }
    }
}
