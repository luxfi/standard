// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

library LamportLib {
    function verify_u256(
        uint256 bits,
        bytes[256] calldata sig,
        bytes32[2][256] calldata pub
    ) public pure returns (bool) {
        unchecked {
            for (uint256 i; i < 256; i++) {
                if (
                    pub[i][((bits & (1 << (255 - i))) > 0) ? 1 : 0] !=
                    keccak256(sig[i])
                ) return false;
            }

            return true;
        }
    }

    /// @notice Verify a Lamport signature (bytes32[] format)
    /// @param message The message hash that was signed
    /// @param signature Array of 256 bytes32 values (the revealed private key halves)
    /// @param publicKey 256x2 array of bytes32 (the public key hashes)
    function verify(
        bytes32 message,
        bytes32[] memory signature,
        bytes32[2][256] memory publicKey
    ) internal pure returns (bool) {
        require(signature.length == 256, "Invalid signature length");
        
        uint256 bits = uint256(message);
        for (uint256 i = 0; i < 256; i++) {
            uint256 bit = (bits >> (255 - i)) & 1;
            // Check that hash of revealed private key matches public key
            if (keccak256(abi.encode(signature[i])) != publicKey[i][bit]) {
                return false;
            }
        }
        return true;
    }
}
