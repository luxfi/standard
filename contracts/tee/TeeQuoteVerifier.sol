// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ILux.sol";

/**
 * @title TeeQuoteVerifier
 * @notice Verifies TEE attestation quotes from Intel SGX, AMD SEV, and NVIDIA GPU TEEs
 */
contract TeeQuoteVerifier {
    using ILux for ILux.TeeType;

    /// @notice TEE root certificates (simplified - in production these would be full cert chains)
    mapping(ILux.TeeType => bytes32) public rootCertificates;

    /// @notice Known good measurement values for each TEE type
    mapping(ILux.TeeType => mapping(bytes32 => bool)) public trustedMeasurements;

    constructor() {
        // Initialize root certificates (simplified)
        rootCertificates[ILux.TeeType.SGX] = keccak256("INTEL_SGX_ROOT_CA");
        rootCertificates[ILux.TeeType.TDX] = keccak256("INTEL_TDX_ROOT_CA");
        rootCertificates[ILux.TeeType.SNP] = keccak256("AMD_SEV_ROOT_CA");
        rootCertificates[ILux.TeeType.GPU] = keccak256("NVIDIA_GPU_ROOT_CA");
    }

    /**
     * @notice Verify a TEE quote
     * @param teeType Type of TEE that generated the quote
     * @param quote Raw quote bytes from TEE
     * @param expectedPayloadHash Expected hash of job payload
     * @param merkleRoot Merkle root of execution trace
     * @return valid Whether the quote is valid
     */
    function verifyQuote(
        ILux.TeeType teeType,
        bytes calldata quote,
        bytes32 expectedPayloadHash,
        bytes32 merkleRoot
    ) external view returns (bool valid) {
        if (teeType == ILux.TeeType.SGX) {
            return verifySGXQuote(quote, expectedPayloadHash, merkleRoot);
        } else if (teeType == ILux.TeeType.TDX) {
            return verifyTDXQuote(quote, expectedPayloadHash, merkleRoot);
        } else if (teeType == ILux.TeeType.SNP) {
            return verifySNPQuote(quote, expectedPayloadHash, merkleRoot);
        } else if (teeType == ILux.TeeType.GPU) {
            return verifyGPUQuote(quote, expectedPayloadHash, merkleRoot);
        }
        return false;
    }

    /**
     * @notice Verify Intel SGX quote
     */
    function verifySGXQuote(
        bytes calldata quote,
        bytes32 expectedPayloadHash,
        bytes32 merkleRoot
    ) internal view returns (bool) {
        // SGX Quote Format (simplified):
        // [0:4] = version
        // [4:6] = attestation key type
        // [6:10] = reserved
        // [10:42] = report body hash
        // [42:74] = report data (user data)
        // [74:...] = signature
        
        require(quote.length >= 432, "Invalid SGX quote length");
        
        // Extract version
        uint32 version = uint32(bytes4(quote[0:4]));
        require(version == 3 || version == 4, "Unsupported SGX quote version");
        
        // Extract and verify report data (should contain job hash + merkle root)
        bytes32 reportData1 = bytes32(quote[42:74]);
        bytes32 reportData2 = bytes32(quote[74:106]);
        
        require(reportData1 == expectedPayloadHash, "Payload hash mismatch");
        require(reportData2 == merkleRoot, "Merkle root mismatch");
        
        // In production: verify signature chain to Intel root CA
        // For now, simplified check
        bytes32 measurementHash = bytes32(quote[106:138]);
        return trustedMeasurements[ILux.TeeType.SGX][measurementHash];
    }

    /**
     * @notice Verify Intel TDX quote
     */
    function verifyTDXQuote(
        bytes calldata quote,
        bytes32 expectedPayloadHash,
        bytes32 merkleRoot
    ) internal view returns (bool) {
        // TDX TDREPORT structure verification
        require(quote.length >= 1024, "Invalid TDX quote length");
        
        // Extract TD measurements
        bytes32 tdMeasurement = bytes32(quote[32:64]);
        
        // Verify expected data in report
        bytes32 reportData = bytes32(quote[512:544]);
        require(reportData == keccak256(abi.encode(expectedPayloadHash, merkleRoot)), "Report data mismatch");
        
        return trustedMeasurements[ILux.TeeType.TDX][tdMeasurement];
    }

    /**
     * @notice Verify AMD SEV-SNP quote
     */
    function verifySNPQuote(
        bytes calldata quote,
        bytes32 expectedPayloadHash,
        bytes32 merkleRoot
    ) internal view returns (bool) {
        // SEV-SNP attestation report structure
        require(quote.length >= 1184, "Invalid SNP quote length");
        
        // Extract measurement
        bytes32 measurement = bytes32(quote[96:128]);
        
        // Extract and verify host data
        bytes32 hostData = bytes32(quote[192:224]);
        require(hostData == keccak256(abi.encode(expectedPayloadHash, merkleRoot)), "Host data mismatch");
        
        return trustedMeasurements[ILux.TeeType.SNP][measurement];
    }

    /**
     * @notice Verify NVIDIA GPU TEE quote
     */
    function verifyGPUQuote(
        bytes calldata quote,
        bytes32 expectedPayloadHash,
        bytes32 merkleRoot
    ) internal view returns (bool) {
        // NVIDIA Hopper Attestation Token
        require(quote.length >= 512, "Invalid GPU quote length");
        
        // Extract nonce (should contain our data)
        bytes32 nonce = bytes32(quote[64:96]);
        require(nonce == keccak256(abi.encode(expectedPayloadHash, merkleRoot)), "Nonce mismatch");
        
        // Extract measurement
        bytes32 measurement = bytes32(quote[128:160]);
        
        return trustedMeasurements[ILux.TeeType.GPU][measurement];
    }

    /**
     * @notice Add a trusted measurement (admin only in production)
     */
    function addTrustedMeasurement(
        ILux.TeeType teeType,
        bytes32 measurement
    ) external {
        trustedMeasurements[teeType][measurement] = true;
    }

    /**
     * @notice Parse quote to extract key fields
     */
    function parseQuote(
        ILux.TeeType teeType,
        bytes calldata quote
    ) external pure returns (
        bytes32 measurement,
        bytes32 userData,
        uint256 version
    ) {
        if (teeType == ILux.TeeType.SGX) {
            version = uint32(bytes4(quote[0:4]));
            userData = bytes32(quote[42:74]);
            measurement = bytes32(quote[106:138]);
        } else if (teeType == ILux.TeeType.TDX) {
            version = 1; // TDX version
            userData = bytes32(quote[512:544]);
            measurement = bytes32(quote[32:64]);
        } else if (teeType == ILux.TeeType.SNP) {
            version = uint32(bytes4(quote[0:4]));
            userData = bytes32(quote[192:224]);
            measurement = bytes32(quote[96:128]);
        } else if (teeType == ILux.TeeType.GPU) {
            version = 1; // GPU TEE version
            userData = bytes32(quote[64:96]);
            measurement = bytes32(quote[128:160]);
        }
    }
}