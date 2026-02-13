// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IKYCVerifierV1
} from "../../interfaces/services/IKYCVerifierV1.sol";
import {IVersion} from "../../interfaces/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/IDeploymentBlock.sol";
import {
    DeploymentBlockNonInitializable
} from "../../DeploymentBlockNonInitializable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    Ownable2Step,
    Ownable
} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title KYCVerifierV1
 * @author Lux Industriesn Inc
 * @notice KYC verification service using EIP-712 signature verification
 * @dev This contract implements IKYCVerifierV1, providing KYC verification
 * through cryptographic signature verification.
 *
 * Implementation details:
 * - Uses EIP-712 structured data signing for verification
 * - Requires signature from authorized verifier address
 * - Deployed as singleton service per chain
 * - Supports operating contract-specific verification
 *
 * Security considerations:
 * - Verifier address is immutable and set at deployment
 * - Uses ECDSA signature recovery for verification
 * - EIP-712 prevents signature replay across different domains
 * - Operating contract context prevents cross-contract signature reuse
 *
 * @custom:security-contact security@lux.network
 */
contract KYCVerifierV1 is
    IKYCVerifierV1,
    IVersion,
    DeploymentBlockNonInitializable,
    ERC165,
    EIP712,
    Ownable2Step
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    address private _verifier;

    mapping(address account => uint256 nonce) private _nonces;

    bytes32 internal constant TYPEHASH =
        keccak256(
            "VerificationData(address operator,address account,uint48 signatureExpiration,uint256 nonce)"
        );

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor(
        address owner_,
        address verifier_
    ) EIP712("KYCVerifier", "1") Ownable(owner_) {
        _verifier = verifier_;
    }

    // ======================================================================
    // IKYCVerifier
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IKYCVerifierV1
     */
    function verifier() public view virtual override returns (address) {
        return _verifier;
    }

    /**
     * @inheritdoc IKYCVerifierV1
     */
    function nonce(
        address account_
    ) public view virtual override returns (uint256) {
        return _nonces[account_];
    }

    /**
     * @inheritdoc IKYCVerifierV1
     */
    function checkVerify(
        address operator_,
        address account_,
        uint48 signatureExpiration_,
        bytes calldata signature_
    ) public view virtual override returns (bool) {
        if (block.timestamp > signatureExpiration_) {
            return false;
        }

        return
            ECDSA.recover(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            TYPEHASH,
                            operator_,
                            account_,
                            signatureExpiration_,
                            _nonces[account_]
                        )
                    )
                ),
                signature_
            ) == _verifier;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IKYCVerifierV1
     * @dev Verifies KYC status using EIP-712 signature verification. The signature
     * must be provided by the authorized verifier address to confirm KYC compliance.
     */
    function verify(
        address account_,
        uint48 signatureExpiration_,
        bytes calldata signature_
    ) public virtual override {
        if (block.timestamp > signatureExpiration_) {
            revert SignatureExpired();
        }

        uint256 accountNonce = _nonces[account_];

        if (
            ECDSA.recover(
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            TYPEHASH,
                            msg.sender,
                            account_,
                            signatureExpiration_,
                            accountNonce
                        )
                    )
                ),
                signature_
            ) == _verifier
        ) {
            // KYC signature is valid
            _nonces[account_]++;

            emit SignatureVerified(
                msg.sender,
                account_,
                signatureExpiration_,
                accountNonce
            );
        } else {
            // KYC signature is invalid
            revert InvalidSignature();
        }
    }

    /**
     * @inheritdoc IKYCVerifierV1
     */
    function updateVerifier(
        address verifier_
    ) public virtual override onlyOwner {
        _verifier = verifier_;

        emit VerifierUpdated(verifier_);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports IKYCVerifierV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IKYCVerifierV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
