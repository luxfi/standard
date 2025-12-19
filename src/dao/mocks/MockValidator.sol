// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IFunctionValidator
} from "../interfaces/dao/services/IFunctionValidator.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract MockValidator is IFunctionValidator, ERC165 {
    bool private shouldValidate;

    function setShouldValidate(bool _shouldValidate) external {
        shouldValidate = _shouldValidate;
    }

    function validateOperation(
        address, // sender
        address, // lightAccountOwner
        address, // targetContract
        bytes calldata // callData
    ) external view returns (bool) {
        // Return the configured validation result
        return shouldValidate;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IFunctionValidator).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
