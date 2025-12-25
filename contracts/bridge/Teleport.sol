// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @dev Interface for bridgeable tokens (LRC20B compatible)
 */
interface ILRC20B {
    function balanceOf(address account) external view returns (uint256);
    function mint(address account, uint256 amount) external returns (bool);
    function burnIt(address account, uint256 amount) external returns (bool);
}

/**
 * @title Bridge
 * @author Lux Industries
 * @notice MPC-based cross-chain bridge for LRC20B tokens
 * @dev Uses MPC oracle signatures for secure cross-chain minting
 */
contract Bridge is Ownable, AccessControl {
    /// @notice Fee collected (in wei)
    uint256 internal fee;

    /// @notice Fee rate (default 1% = 10 * 10^15 / 10^18)
    uint256 public feeRate = 10 * (10 ** 15);

    /// @notice Fee payout address
    address internal payoutAddr;

    // Events
    event BridgeBurned(address indexed caller, uint256 amt);
    event SigMappingAdded(bytes key);
    event NewMPCOracleSet(address indexed MPCOracle);
    event BridgeMinted(address indexed recipient, address indexed token, uint256 amt);
    event AdminGranted(address indexed to);
    event AdminRevoked(address indexed to);

    /// @notice MPC Oracle address info
    struct MPCOracleAddrInfo {
        bool exists;
    }

    /// @notice Transaction info for replay protection
    struct TransactionInfo {
        string txid;
        bool exists;
    }

    /// @notice Internal struct for bridgeMint operations
    struct VarStruct {
        bytes32 tokenAddrHash;
        string amtStr;
        bytes32 toTargetAddrStrHash;
        bytes32 toChainIdHash;
        address toTargetAddr;
        ILRC20B token;
    }

    /// @notice MPC Oracle address mapping
    mapping(address => MPCOracleAddrInfo) internal MPCOracleAddrMap;

    /// @notice Transaction replay protection mapping
    mapping(bytes => TransactionInfo) internal transactionMap;

    /**
     * @notice Initialize bridge with deployer as admin
     */
    constructor() Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Restrict to admin role
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Bridge: caller is not admin");
        _;
    }

    /**
     * @notice Grant admin role
     * @param to Address to grant admin role
     */
    function grantAdmin(address to) public onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminGranted(to);
    }

    /**
     * @notice Revoke admin role
     * @param to Address to revoke admin role from
     */
    function revokeAdmin(address to) public onlyAdmin {
        require(hasRole(DEFAULT_ADMIN_ROLE, to), "Bridge: not an admin");
        revokeRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminRevoked(to);
    }

    /**
     * @notice Set fee payout address and rate
     * @param addr Payout address
     * @param feeR Fee rate in wei (e.g., 10 * 10^15 = 1%)
     */
    function setPayoutAddress(address addr, uint256 feeR) public onlyAdmin {
        payoutAddr = addr;
        feeRate = feeR;
    }

    /**
     * @notice Add MPC Oracle address
     * @param _key MPC Oracle address
     */
    function addMPCMapping(address _key) internal {
        MPCOracleAddrMap[_key].exists = true;
    }

    /**
     * @notice Set new MPC Oracle address (admin only)
     * @param MPCO MPC Oracle address
     */
    function setMPCOracle(address MPCO) public onlyAdmin {
        addMPCMapping(MPCO);
        emit NewMPCOracleSet(MPCO);
    }

    /**
     * @notice Check if address is MPC Oracle
     * @param _key Address to check
     * @return exists True if MPC Oracle
     */
    function getMPCMapDataTx(address _key) public view returns (bool) {
        return MPCOracleAddrMap[_key].exists;
    }

    /**
     * @notice Add transaction to replay protection mapping
     * @param _key Signed transaction info
     */
    function addMappingStealth(bytes memory _key) internal {
        require(!transactionMap[_key].exists, "Bridge: duplicate tx");
        transactionMap[_key].exists = true;
        emit SigMappingAdded(_key);
    }

    /**
     * @notice Check if transaction exists
     * @param _key Signed transaction info
     * @return exists True if transaction exists
     */
    function keyExistsTx(bytes memory _key) public view returns (bool) {
        return transactionMap[_key].exists;
    }

    /**
     * @notice Burn tokens for bridge transfer
     * @param amount Amount to burn
     * @param tokenAddr Token address
     */
    function bridgeBurn(uint256 amount, address tokenAddr) public {
        ILRC20B token = ILRC20B(tokenAddr);
        require(token.balanceOf(msg.sender) > 0, "Bridge: zero balance");
        token.burnIt(msg.sender, amount);
        emit BridgeBurned(msg.sender, amount);
    }

    /**
     * @notice Concatenate data for signing
     */
    function append(
        string memory amt,
        string memory toTargetAddrStr,
        string memory txid,
        string memory tokenAddrStrHash,
        string memory chainIdStr,
        string memory vault
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(amt, toTargetAddrStr, txid, tokenAddrStrHash, chainIdStr, vault));
    }

    /**
     * @notice Mint tokens via MPC signature verification
     * @param amt Amount to mint
     * @param hashedId Hashed transaction ID
     * @param toTargetAddrStr Recipient address
     * @param signedTXInfo Signed transaction info
     * @param tokenAddrStr Token address
     * @param chainId Chain ID
     * @param vault Vault identifier
     * @return signer Recovered signer address
     */
    function bridgeMintStealth(
        uint256 amt,
        string memory hashedId,
        address toTargetAddrStr,
        bytes memory signedTXInfo,
        address tokenAddrStr,
        string memory chainId,
        string memory vault
    ) public returns (address) {
        VarStruct memory varStruct;

        varStruct.tokenAddrHash = keccak256(abi.encodePacked(tokenAddrStr));
        varStruct.token = ILRC20B(tokenAddrStr);
        varStruct.toTargetAddr = toTargetAddrStr;
        varStruct.toTargetAddrStrHash = keccak256(abi.encodePacked(toTargetAddrStr));
        varStruct.amtStr = Strings.toString(amt);
        varStruct.toChainIdHash = keccak256(abi.encodePacked(chainId));

        // Concat message
        string memory msg1 = append(
            varStruct.amtStr,
            Strings.toHexString(uint256(varStruct.toTargetAddrStrHash), 32),
            hashedId,
            Strings.toHexString(uint256(varStruct.tokenAddrHash), 32),
            Strings.toHexString(uint256(varStruct.toChainIdHash), 32),
            vault
        );

        // Check signedTXInfo doesn't already exist
        require(!transactionMap[signedTXInfo].exists, "Bridge: duplicate tx");

        address signer = recoverSigner(prefixed(keccak256(abi.encodePacked(msg1))), signedTXInfo);

        // Check signer is MPC Oracle
        require(MPCOracleAddrMap[signer].exists, "Bridge: invalid signature");

        // Calculate fee (using native 0.8.x math instead of SafeMath)
        uint256 feeAmount = (amt * feeRate) / (10 ** 18);
        uint256 netAmount = amt - feeAmount;

        varStruct.token.mint(payoutAddr, feeAmount);
        varStruct.token.mint(varStruct.toTargetAddr, netAmount);

        // Add to replay protection
        addMappingStealth(signedTXInfo);

        emit BridgeMinted(varStruct.toTargetAddr, tokenAddrStr, netAmount);

        return signer;
    }

    /**
     * @notice Split ECDSA signature into components
     * @param sig 65-byte signature
     * @return v Recovery byte
     * @return r First 32 bytes
     * @return s Second 32 bytes
     */
    function splitSignature(bytes memory sig) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "Bridge: invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /**
     * @notice Recover signer from message and signature
     * @param message Message hash
     * @param sig Signature
     * @return Signer address
     */
    function recoverSigner(bytes32 message, bytes memory sig) internal pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig);
        return ecrecover(message, v, r, s);
    }

    /**
     * @notice Prefix hash for eth_sign compatibility
     * @param hash Original hash
     * @return Prefixed hash
     */
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}
