// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

abstract contract LamportBase {
    bool initialized = false;
    bytes32 pkh; // public key hash

    // initial setup of the Lamport system
    function init(bytes32 firstPKH) public {
        require(!initialized, "LamportBase: Already initialized");
        pkh = firstPKH;
        initialized = true;
    }

    // get the current public key hash
    function getPKH() public view returns (bytes32) {
        return pkh;
    }

    // lamport 'verify' logic
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

    modifier onlyLamportOwner(
        bytes32[2][256] calldata currentpub,
        bytes[256] calldata sig,
        bytes32 nextPKH,
        bytes memory prepacked
    ) {
        require(initialized, "LamportBase: not initialized"); // 1. contract must be ready
        require(
            keccak256(abi.encodePacked(currentpub)) == pkh,
            "LamportBase: currentpub does not match known PUBLIC KEY HASH"
        );

        require(
            verify_u256(
                uint256(keccak256(abi.encodePacked(prepacked, nextPKH))),
                sig,
                currentpub
            ),
            "LamportBase: Signature not valid"
        );

        pkh = nextPKH;
        _;
    }
}
