// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.31;

/// @title FROST Library
/// @notice Library for verifying FROST(secp256k1, SHA-256) signatures.
/// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9591>
library FROST {
    /// @notice The secp256k1 prime field order.
    uint256 private constant _P = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
    /// @notice The secp256k1 curve order.
    uint256 private constant _N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    /// @notice Compute the mul-mul-add operation `-z⋅G + e⋅P` and return the
    /// hash of the resulting point.
    /// @dev This function uses a trick to abuse the `ecrecover` precompile in
    /// order to compute a mul-mul-add operation of `-z` times the curve
    /// generator point plus `e` time the point `P` defined by the coordinates
    /// `{x, y}`. The caveat with this trick is that it doesn't return the
    /// resulting point, but a public address (which is a truncated hash of the
    /// resulting point's coordinates).
    /// @param z The scalar to multiply the generator point with.
    /// @param x The x-coordinate of the point `P`.
    /// @param y The y-coordinate of the point `P`.
    /// @param e The scalar to multiple the point `P` with.
    /// @return result The address corresponding to the point `-z⋅G + e⋅P`.
    /// @custom:reference <https://ethresear.ch/t/you-can-kinda-abuse-ecrecover-to-do-ecmul-in-secp256k1-today/2384>
    function _ecmulmuladd(uint256 z, uint256 x, uint256 y, uint256 e) private view returns (address result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, mulmod(z, x, _N))
            mstore(add(ptr, 0x20), add(and(y, 1), 27))
            mstore(add(ptr, 0x40), x)
            mstore(add(ptr, 0x60), mulmod(e, x, _N))
            result := mul(mload(0x00), staticcall(gas(), 0x1, ptr, 0x80, 0x00, 0x20))
        }
    }

    /// @notice Compute the address corresponding to a point.
    /// @param x The x-coordinate of the point.
    /// @param y The y-coordinate of the point.
    /// @return result The address corresponding to the specified point.
    function _address(uint256 x, uint256 y) private pure returns (address result) {
        assembly ("memory-safe") {
            mstore(0x00, x)
            mstore(0x20, y)
            result := and(keccak256(0x00, 0x40), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /// @notice Checks whether a point is on the curve.
    /// @param x The x-coordinate of the point.
    /// @param y The y-coordinate of the point.
    /// @return result Whether the point is on the curve.
    function _isOnCurve(uint256 x, uint256 y) private pure returns (bool result) {
        assembly ("memory-safe") {
            result :=
                and(eq(mulmod(y, y, _P), addmod(mulmod(x, mulmod(x, x, _P), _P), 7, _P)), and(lt(x, _P), lt(y, _P)))
        }
    }

    /// @notice Checks whether an integer is a valid curve scalar.
    /// @param a The integer to check.
    /// @return result Whether integer is a valid curve scalar in the range
    /// `(0, _N)`.
    function _isScalar(uint256 a) private pure returns (bool result) {
        assembly ("memory-safe") {
            result := and(gt(a, 0), lt(a, _N))
        }
    }

    /// @notice Compute the pre-image to the challenge used for signature
    /// verification.
    /// @dev This is the pre-image to the hashing function used in the Schnorr
    /// signature scheme and is the concatenation of the group commitment point
    /// `R` from FROST signature, the group public key point `P` and the signed
    /// message. Points are both in SEC1 compressed form.
    /// @custom:note There is no restriction to the length of `message`, but we
    /// keep it to a constant 32 bytes in our implementation, since almost all
    /// on-chain signature verification uses 32-byte signing messages.
    /// @param rx The x-coordinate of the signature point `R`.
    /// @param ry The y-coordinate of the signature point `R`.
    /// @param px The x-coordinate of the public key point `P`.
    /// @param py The y-coordinate of the public key point `P`.
    /// @param message The signed message.
    /// @return preimage The pre-image bytes.
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9591#section-4.6>
    /// @custom:reference <https://secg.org/sec1-v2.pdf>
    function _preimage(uint256 rx, uint256 ry, uint256 px, uint256 py, bytes32 message)
        private
        pure
        returns (bytes memory preimage)
    {
        preimage = new bytes(98);
        assembly ("memory-safe") {
            mstore8(add(preimage, 0x20), add(2, and(ry, 1)))
            mstore(add(preimage, 0x21), rx)
            mstore8(add(preimage, 0x41), add(2, and(py, 1)))
            mstore(add(preimage, 0x42), px)
            mstore(add(preimage, 0x62), message)
        }
    }

    /// @notice Expands `message` to generate a uniformly random byte string.
    /// @dev This uses the XMD variant of message expansion, as specified by
    /// the hashing function for FROST(secp256k1, SHA-256).
    /// @param message The message to expand.
    /// @param dst The domain separation tag.
    /// @param len The number of uniformly random bytes to generate.
    /// @return uniform `len` uniformly random bytes.
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9380#section-5.3.1>
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9591#section-6.5>
    function _expandMessageXmd(bytes memory message, string memory dst, uint256 len)
        private
        view
        returns (bytes memory uniform)
    {
        assembly ("memory-safe") {
            uniform := mload(0x40)
            mstore(0x40, add(uniform, and(add(0x3f, len), 0xffe0)))
            mstore(uniform, len)

            let prime := mload(0x40)
            let ptr := prime

            mstore(ptr, 0)
            ptr := add(ptr, 0x20)
            mstore(ptr, 0)
            ptr := add(ptr, 0x20)

            mcopy(ptr, add(message, 0x20), mload(message))
            ptr := add(ptr, mload(message))
            mstore(ptr, shl(240, len))
            ptr := add(ptr, 3)

            let bPtr := sub(ptr, 0x21)
            let iPtr := sub(ptr, 0x01)

            mcopy(ptr, add(dst, 0x20), mload(dst))
            ptr := add(ptr, mload(dst))
            mstore8(ptr, mload(dst))
            ptr := add(ptr, 0x01)

            let bLen := sub(ptr, bPtr)

            if iszero(staticcall(gas(), 0x2, prime, sub(ptr, prime), bPtr, 0x20)) { revert(0x00, 0x00) }
            let b0 := mload(bPtr)
            mstore8(iPtr, 1)
            if iszero(staticcall(gas(), 0x2, bPtr, bLen, add(uniform, 0x20), 0x20)) { revert(0x00, 0x00) }
            for { let i := 2 } gt(len, 0x20) {
                i := add(i, 1)
                len := sub(len, 32)
            } {
                let uPtr := add(uniform, shl(5, i))
                mstore(bPtr, xor(b0, mload(sub(uPtr, 0x20))))
                mstore8(iPtr, i)
                if iszero(staticcall(gas(), 0x2, bPtr, bLen, uPtr, 0x20)) { revert(0x00, 0x00) }
            }
        }
    }

    /// @notice Hash a `message` to a field element.
    /// @dev It is somewhat confusing, but the hashing functions from
    /// FROST(secp256k1, SHA-256) are specified to use the curve order instead
    /// of the field order. This makes sense because:
    /// 1. The curve order is also prime, and so also forms a prime field.
    /// 2. The scalar is multiplied by a point during signature verification
    ///    meaning that only values `[0, _N)` produce unique points.
    /// @param message The message to hash.
    /// @param dst The domain separation tag.
    /// @return e The hashed message as a field element.
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9380#section-5.3.1>
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9591#section-6.5>
    function _hashToField(bytes memory message, string memory dst) private view returns (uint256 e) {
        bytes memory uniform = _expandMessageXmd(message, dst, 48);
        assembly ("memory-safe") {
            e := mulmod(mload(add(uniform, 0x20)), 0x100000000000000000000000000000000, _N)
            e := addmod(e, shr(128, mload(add(uniform, 0x40))), _N)
        }
    }

    /// @notice Computes the challenge for the FROST(secp256k1, SHA-256)
    /// Schnorr signature.
    /// @dev Defined as the H2 hashing function for FROST(secp256k1, SHA-256).
    /// @custom:note There is no restriction to the length of `message`, but we
    /// keep it to a constant 32 bytes in our implementation, since almost all
    /// on-chain signature verification uses 32-byte signing messages.
    /// @param rx The x-coordinate of the signature point `R`.
    /// @param ry The y-coordinate of the signature point `R`.
    /// @param px The x-coordinate of the public key point `P`.
    /// @param py The y-coordinate of the public key point `P`.
    /// @param message The signed message.
    /// @return e The Schnorr signature challenge.
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9591#section-6.5>
    function _challenge(uint256 rx, uint256 ry, uint256 px, uint256 py, bytes32 message)
        private
        view
        returns (uint256 e)
    {
        return _hashToField(_preimage(rx, ry, px, py, message), "FROST-secp256k1-SHA256-v1chal");
    }

    /// @notice Checks whether a point is on the curve and is a supported FROST
    /// public key.
    /// @dev In addition to being a valid point of the curve, the `x`-coordinate
    /// of the public key must be smaller than the curve order for the math trick
    /// with `ecrecover` to work and supported by this verifier implementation.
    /// @param x The x-coordinate of the point.
    /// @param y The y-coordinate of the point.
    /// @return result Whether the point is valid and supported.
    function isValidPublicKey(uint256 x, uint256 y) internal pure returns (bool result) {
        assembly ("memory-safe") {
            result :=
                and(eq(mulmod(y, y, _P), addmod(mulmod(x, mulmod(x, x, _P), _P), 7, _P)), and(lt(x, _N), lt(y, _P)))
        }
    }

    /// @notice Verify a FROST(secp256k1, SHA-256) Schnorr signature.
    /// @dev Note that public key's x-coordinate `px` must be smaller than the
    /// curve order for the math trick with `ecrecover` to work. You must use
    /// public keys that have been checked with `FROST.isValidPublicKey(px, py)`,
    /// as not all public keys are supported by this verifier implementation.
    /// @custom:note There is no restriction to the length of `message`, but we
    /// keep it to a constant 32 bytes in our implementation, since almost all
    /// on-chain signature verification uses 32-byte signing messages.
    /// @param message The signed message.
    /// @param rx The x-coordinate of the signature point `R`.
    /// @param ry The y-coordinate of the signature point `R`.
    /// @param px The x-coordinate of the public key point `P`.
    /// @param py The y-coordinate of the public key point `P`.
    /// @param z The z-scalar of the signature.
    /// @return signer The address of the public key point `P`, or `0` if
    /// signature verification failed.
    /// @custom:reference <https://datatracker.ietf.org/doc/html/rfc9591#section-6.5>
    /// @custom:reference <https://en.wikipedia.org/wiki/Schnorr_signature#Verifying>
    /// @custom:reference <https://ethresear.ch/t/you-can-kinda-abuse-ecrecover-to-do-ecmul-in-secp256k1-today/2384/19>
    function verify(bytes32 message, uint256 px, uint256 py, uint256 rx, uint256 ry, uint256 z)
        internal
        view
        returns (address signer)
    {
        // This is where the madness happens!
        //
        // Schnorr signature verification is fairly straight forward. Given:
        // - generator point `G`
        // - message bytes `MSG`
        // - public key point `P`
        // - signature point `R`
        // - signature scalar `z`
        // - hashing function `H` (`H2` from the FROST(secp256k1, SHA-256)
        //   specification - used in computing the signature `_challenge`)
        //
        // Let `e` be the signature challenge computed by applying the hashing
        // function `H` to `R`, `P` and `MSG` (note that for FROST, the points
        // are encoded in SEC1 compressed form):
        //      e = H(R || P || MSG)
        //
        // The goal is to show that:
        //      z⋅G - H(R || P || MSG)⋅P = R
        //                     z⋅G - e⋅P = R
        //
        // If we abuse the `ecrecover` mul-mul-add trick, we get a convienient
        // way of computing:
        //      address(-z⋅G + e⋅P) = address(-(z⋅G - e⋅P))
        //                         = address(-(z⋅G - H(R || P || MSG)⋅P))
        //                         = address(-R)
        //
        // We can trivially compute the additive inverse `-R` of `R`:
        //      -R = {rx,-ry}
        //
        // This means you just need to compute the additive inverse of its
        // y-coordinate `ry` in the curve's finite field:
        //      -ry = (_P - ry) % _P
        //          = _P - ry
        //
        // We can omit the modulus since `ry` is already an element of the
        // curve's finite field and thus in the range `[0, _P)`.
        //
        // Note that Schnorr lacks standardization, and in some schemes you
        // compute `z⋅G - e⋅P = R` and in others `z⋅G + e⋅P = R`. The math
        // works out to the same in the end - you just need to be careful about
        // the sign of the scalars from the signature. FROST in particular uses
        // the former construction.

        // TODO(nlordell): I don't think this is required for Schnorr
        // signatures, but do it anyway for now just in case. At least, this
        // prevents some signature malleability with `z` (since it gets mapped
        // to a curve scalar, there are some values of `z` that can be
        // specified in more than one way.
        {
            bool pOk = isValidPublicKey(px, py);
            bool rOk = _isOnCurve(rx, ry);
            bool zOk = _isScalar(z);
            bool ok;
            assembly ("memory-safe") {
                ok := and(pOk, and(rOk, zOk))
            }

            if (!ok) {
                return address(0);
            }
        }

        uint256 e = _challenge(rx, ry, px, py, message);
        unchecked {
            address minusR = _address(rx, _P - ry); // address(-R)
            address minusRv = _ecmulmuladd(z, px, py, e); // address(-z⋅G + e⋅P)

            signer = _address(px, py);
            assembly ("memory-safe") {
                signer := mul(signer, eq(minusR, minusRv))
            }
        }
    }
}
