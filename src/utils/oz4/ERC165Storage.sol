// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.x compatibility shim
// ERC165Storage was removed in OZ 5.x - use ERC165 directly
pragma solidity ^0.8.0;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/// @notice ERC165Storage compatibility shim
/// @dev ERC165Storage was removed in OZ 5.x. Use ERC165 with _registerInterface pattern.
abstract contract ERC165Storage is ERC165 {
    mapping(bytes4 => bool) private _supportedInterfaces;

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || _supportedInterfaces[interfaceId];
    }

    function _registerInterface(bytes4 interfaceId) internal virtual {
        require(interfaceId != 0xffffffff, "ERC165: invalid interface id");
        _supportedInterfaces[interfaceId] = true;
    }
}
