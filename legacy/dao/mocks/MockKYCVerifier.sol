// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IKYCVerifierV1} from "../interfaces/dao/services/IKYCVerifierV1.sol";
import {IVersion} from "../interfaces/dao/deployables/IVersion.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract MockKYCVerifier is IKYCVerifierV1, IVersion, ERC165 {
    bool internal _verify;

    constructor() {
        initialize();
    }

    function initialize() public {}

    function setVerify(bool verify_) public {
        _verify = verify_;
    }

    function updateVerifier(address) public virtual override {}

    function verify(address, uint48, bytes calldata) public virtual override {
        if (!_verify) revert InvalidSignature();
    }

    function verifier() public view virtual override returns (address) {
        return address(0);
    }

    function nonce(address) public view virtual override returns (uint256) {
        return 0;
    }

    function checkVerify(
        address,
        address,
        uint48,
        bytes calldata
    ) public view virtual override returns (bool) {
        return _verify;
    }

    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IKYCVerifierV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
