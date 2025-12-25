// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import "@luxfi/standard/lib/token/ERC20/extensions/IERC20Permit.sol";
import "@luxfi/standard/lib/utils/cryptography/ECDSA.sol";
import "@luxfi/standard/lib/utils/cryptography/EIP712.sol";
import "@luxfi/standard/lib/utils/Nonces.sol";

/**
 * @title LRC20Permit
 * @author Lux Industries
 * @notice LRC-20 extension for gasless approvals via EIP-2612 (LP-3026)
 * @dev Composable extension implementing permit functionality
 */
abstract contract LRC20Permit is ERC20, IERC20Permit, EIP712, Nonces {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /**
     * @notice Error thrown when permit signature has expired
     */
    error LRC20PermitExpiredSignature(uint256 deadline);

    /**
     * @notice Error thrown when recovered signer doesn't match owner
     */
    error LRC20PermitInvalidSigner(address signer, address owner);

    /**
     * @notice Initializes EIP-712 domain separator
     * @param name Token name for EIP-712 domain
     */
    constructor(string memory name) EIP712(name, "1") {}

    /**
     * @notice Sets allowance via signature (EIP-2612)
     * @param owner Token owner
     * @param spender Approved spender
     * @param value Approval amount
     * @param deadline Signature expiry timestamp
     * @param v Recovery byte
     * @param r ECDSA signature r
     * @param s ECDSA signature s
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        if (block.timestamp > deadline) {
            revert LRC20PermitExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline)
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);

        if (signer != owner) {
            revert LRC20PermitInvalidSigner(signer, owner);
        }

        _approve(owner, spender, value);
    }

    /**
     * @notice Returns current nonce for address
     * @param owner Token owner
     * @return Current nonce
     */
    function nonces(address owner) public view virtual override(IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @notice Returns EIP-712 domain separator
     * @return Domain separator hash
     */
    function DOMAIN_SEPARATOR() external view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }
}
