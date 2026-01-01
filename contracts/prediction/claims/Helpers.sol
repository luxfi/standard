// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Helpers - Helper library for Claims contract
/// @author Gnosis (original), Lux Industries (0.8.31 port)
/// @notice Provides pure/view helper functions for condition, collection, and position IDs
/// @dev Uses elliptic curve point addition on the alt_bn128 curve for collection ID generation
library Helpers {
    // ============ Errors ============

    /// @dev Thrown when parent collection ID is invalid (not a valid curve point)
    error InvalidParentCollectionId();

    /// @dev Thrown when ecadd precompile call fails
    error ECAddFailed();

    // ============ Constants ============

    /// @dev BN254 curve prime
    uint256 private constant P = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @dev BN254 curve parameter B
    uint256 private constant B = 3;

    // ============ Core Functions ============

    /// @notice Constructs a condition ID from an oracle, a question ID, and the outcome slot count.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition.
    /// @return The condition ID as a bytes32 hash.
    function getConditionId(
        address oracle,
        bytes32 questionId,
        uint256 outcomeSlotCount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /// @notice Constructs an outcome collection ID from a parent collection and an outcome collection.
    /// @dev Uses elliptic curve point addition for hierarchical collection composition.
    /// @param parentCollectionId Collection ID of the parent outcome collection, or bytes32(0) if no parent.
    /// @param conditionId Condition ID of the outcome collection to combine with the parent.
    /// @param indexSet Index set of the outcome collection to combine with the parent.
    /// @return The collection ID as a bytes32.
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) internal view returns (bytes32) {
        // Derive initial point from condition and index set
        uint256 x1 = uint256(keccak256(abi.encodePacked(conditionId, indexSet)));
        bool odd = x1 >> 255 != 0;
        uint256 y1;
        uint256 yy;

        // Find valid curve point by incrementing x until we get a valid y
        unchecked {
            do {
                x1 = addmod(x1, 1, P);
                yy = addmod(mulmod(x1, mulmod(x1, x1, P), P), B, P);
                y1 = _sqrt(yy);
            } while (mulmod(y1, y1, P) != yy);
        }

        // Ensure correct parity of y
        if ((odd && y1 % 2 == 0) || (!odd && y1 % 2 == 1)) {
            y1 = P - y1;
        }

        uint256 x2 = uint256(parentCollectionId);
        if (x2 != 0) {
            // Parent collection exists, need to add points
            odd = x2 >> 254 != 0;
            x2 = (x2 << 2) >> 2; // Clear top 2 bits
            yy = addmod(mulmod(x2, mulmod(x2, x2, P), P), B, P);
            uint256 y2 = _sqrt(yy);

            if ((odd && y2 % 2 == 0) || (!odd && y2 % 2 == 1)) {
                y2 = P - y2;
            }

            if (mulmod(y2, y2, P) != yy) {
                revert InvalidParentCollectionId();
            }

            // Call ecadd precompile (address 6)
            (bool success, bytes memory ret) = address(6).staticcall(abi.encode(x1, y1, x2, y2));
            if (!success) {
                revert ECAddFailed();
            }
            (x1, y1) = abi.decode(ret, (uint256, uint256));
        }

        // Encode y parity in top bit
        if (y1 % 2 == 1) {
            x1 ^= 1 << 254;
        }

        return bytes32(x1);
    }

    /// @notice Constructs a position ID from a collateral token and an outcome collection.
    /// @dev These IDs are used as the ERC-1155 token IDs.
    /// @param collateralToken Collateral token which backs the position.
    /// @param collectionId ID of the outcome collection associated with this position.
    /// @return The position ID as a uint256.
    function getPositionId(
        IERC20 collateralToken,
        bytes32 collectionId
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    // ============ Internal Functions ============

    /// @dev Compute modular square root using Tonelli-Shanks for BN254 curve.
    /// @param x The value to compute square root of.
    /// @return y The square root such that y*y = x (mod P), or 0 if no square root exists.
    function _sqrt(uint256 x) private pure returns (uint256 y) {
        // BN254 has P % 4 == 3, so we can use the simple formula: y = x^((P+1)/4)
        // (P + 1) / 4 = 5472060717959818805561601436314318772174077789324455915672259473661306552146

        // Use optimized addition chain for exponentiation
        uint256 p = P;

        assembly {
            y := mulmod(x, x, p)
            {
                let z := mulmod(y, y, p)
                z := mulmod(z, z, p)
                y := mulmod(y, z, p)
                x := mulmod(x, y, p)
                y := mulmod(y, x, p)
                z := mulmod(y, y, p)
                {
                    let t := mulmod(z, z, p)
                    t := mulmod(z, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    z := mulmod(z, t, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(z, z, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(y, z, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    z := mulmod(x, x, p)
                    z := mulmod(z, z, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    t := mulmod(z, z, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    z := mulmod(z, t, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(z, z, p)
                    z := mulmod(x, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    t := mulmod(z, z, p)
                    t := mulmod(t, t, p)
                    t := mulmod(z, t, p)
                    t := mulmod(y, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    z := mulmod(z, t, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    z := mulmod(z, z, p)
                    t := mulmod(z, z, p)
                    t := mulmod(z, t, p)
                    {
                        let w := mulmod(t, t, p)
                        w := mulmod(w, w, p)
                        w := mulmod(w, w, p)
                        w := mulmod(w, w, p)
                        w := mulmod(w, w, p)
                        t := mulmod(t, w, p)
                    }
                    z := mulmod(z, t, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    z := mulmod(x, x, p)
                    z := mulmod(x, z, p)
                    z := mulmod(z, z, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    z := mulmod(z, z, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(z, z, p)
                    z := mulmod(y, z, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    z := mulmod(z, z, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    z := mulmod(z, z, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    t := mulmod(z, z, p)
                    t := mulmod(t, t, p)
                    t := mulmod(z, t, p)
                    t := mulmod(x, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    z := mulmod(z, t, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    z := mulmod(x, x, p)
                    z := mulmod(x, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    z := mulmod(z, z, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    z := mulmod(x, x, p)
                    z := mulmod(z, z, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    z := mulmod(x, x, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    z := mulmod(y, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    x := mulmod(x, z, p)
                    z := mulmod(x, x, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(x, z, p)
                    y := mulmod(y, z, p)
                    x := mulmod(x, y, p)
                    z := mulmod(x, x, p)
                    t := mulmod(x, z, p)
                    t := mulmod(t, t, p)
                    t := mulmod(t, t, p)
                    z := mulmod(z, t, p)
                    y := mulmod(y, z, p)
                    z := mulmod(y, y, p)
                    x := mulmod(x, z, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    x := mulmod(x, y, p)
                    y := mulmod(y, x, p)
                    z := mulmod(y, y, p)
                    t := mulmod(y, z, p)
                    z := mulmod(y, t, p)
                    z := mulmod(z, z, p)
                    z := mulmod(z, z, p)
                    z := mulmod(t, z, p)
                }
                x := mulmod(x, z, p)
                y := mulmod(y, x, p)
                x := mulmod(x, y, p)
                y := mulmod(y, x, p)
                x := mulmod(x, y, p)
                z := mulmod(x, x, p)
                z := mulmod(x, z, p)
                y := mulmod(y, z, p)
            }
            x := mulmod(x, y, p)

            // Final squaring chain (128 iterations)
            for { let i := 0 } lt(i, 128) { i := add(i, 1) } {
                x := mulmod(x, x, p)
            }

            y := mulmod(y, x, p)
        }
    }
}
