// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../contracts/crypto/lamport/LamportTest.sol";
import "../../contracts/crypto/lamport/LamportLib.sol";

contract LamportFoundryTest is Test {
    LamportTest public lamportContract;
    
    // Test keys (normally generated off-chain)
    bytes32[256][2] public testPrivateKey;
    bytes32[256][2] public testPublicKey;
    
    function setUp() public {
        lamportContract = new LamportTest();
        
        // Generate a test key pair
        // In production, this would be done off-chain
        for (uint i = 0; i < 256; i++) {
            testPrivateKey[i][0] = keccak256(abi.encode("private", i, 0));
            testPrivateKey[i][1] = keccak256(abi.encode("private", i, 1));
            
            testPublicKey[i][0] = keccak256(abi.encode(testPrivateKey[i][0]));
            testPublicKey[i][1] = keccak256(abi.encode(testPrivateKey[i][1]));
        }
    }
    
    function testLamportSignatureGeneration() public {
        bytes32 message = keccak256("Test message");
        bytes32[] memory signature = new bytes32[](256);
        
        // Generate signature
        for (uint i = 0; i < 256; i++) {
            uint8 bit = uint8((uint256(message) >> (255 - i)) & 1);
            signature[i] = testPrivateKey[i][bit];
        }
        
        // Verify signature
        bool isValid = LamportLib.verify(message, signature, testPublicKey);
        assertTrue(isValid);
    }
    
    function testInvalidSignature() public {
        bytes32 message = keccak256("Test message");
        bytes32[] memory signature = new bytes32[](256);
        
        // Generate incorrect signature (use wrong bit)
        for (uint i = 0; i < 256; i++) {
            uint8 bit = uint8((uint256(message) >> (255 - i)) & 1);
            // Intentionally use wrong key half
            signature[i] = testPrivateKey[i][1 - bit];
        }
        
        // Verification should fail
        bool isValid = LamportLib.verify(message, signature, testPublicKey);
        assertFalse(isValid);
    }
    
    function testDifferentMessage() public {
        bytes32 message1 = keccak256("Message 1");
        bytes32 message2 = keccak256("Message 2");
        bytes32[] memory signature = new bytes32[](256);
        
        // Generate signature for message1
        for (uint i = 0; i < 256; i++) {
            uint8 bit = uint8((uint256(message1) >> (255 - i)) & 1);
            signature[i] = testPrivateKey[i][bit];
        }
        
        // Verify with message1 - should pass
        assertTrue(LamportLib.verify(message1, signature, testPublicKey));
        
        // Verify with message2 - should fail
        assertFalse(LamportLib.verify(message2, signature, testPublicKey));
    }
    
    function testLamportContract() public {
        // Set public key in contract
        lamportContract.setPubKey(testPublicKey);
        
        // Generate a message and signature
        bytes32 message = keccak256("Contract test message");
        bytes32[] memory signature = new bytes32[](256);
        
        for (uint i = 0; i < 256; i++) {
            uint8 bit = uint8((uint256(message) >> (255 - i)) & 1);
            signature[i] = testPrivateKey[i][bit];
        }
        
        // Call the contract with valid signature
        lamportContract.doSomething(message, signature);
        
        // Test with invalid signature should revert
        bytes32[] memory badSignature = new bytes32[](256);
        for (uint i = 0; i < 256; i++) {
            badSignature[i] = bytes32(0);
        }
        
        vm.expectRevert();
        lamportContract.doSomething(message, badSignature);
    }
    
    function testGasUsage() public {
        // Set up contract with public key
        lamportContract.setPubKey(testPublicKey);
        
        bytes32 message = keccak256("Gas test message");
        bytes32[] memory signature = new bytes32[](256);
        
        for (uint i = 0; i < 256; i++) {
            uint8 bit = uint8((uint256(message) >> (255 - i)) & 1);
            signature[i] = testPrivateKey[i][bit];
        }
        
        // Measure gas for verification
        uint256 gasBefore = gasleft();
        lamportContract.doSomething(message, signature);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas usage
        emit log_named_uint("Lamport verification gas used", gasUsed);
        
        // Assert reasonable gas usage (should be under 1M gas)
        assertLt(gasUsed, 1000000);
    }
    
    function testFuzzMessageAndSignature(bytes32 message) public {
        // Generate signature for fuzzed message
        bytes32[] memory signature = new bytes32[](256);
        
        for (uint i = 0; i < 256; i++) {
            uint8 bit = uint8((uint256(message) >> (255 - i)) & 1);
            signature[i] = testPrivateKey[i][bit];
        }
        
        // Verification should always pass with correct signature
        assertTrue(LamportLib.verify(message, signature, testPublicKey));
        
        // Modify one bit of signature - should fail
        signature[0] = testPrivateKey[0][1 - uint8(uint256(message) >> 255 & 1)];
        assertFalse(LamportLib.verify(message, signature, testPublicKey));
    }
}