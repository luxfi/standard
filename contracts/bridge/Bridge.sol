// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
    ██╗     ██╗   ██╗██╗  ██╗    ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗   
    ██║     ██║   ██║╚██╗██╔╝    ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝
    ██║     ██║   ██║ ╚███╔╝     ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗  
    ██║     ██║   ██║ ██╔██╗     ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝  
    ███████╗╚██████╔╝██╔╝ ██╗    ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝
 */

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./LRC20B.sol";
import "./BridgeVault.sol";

contract Bridge is Ownable, AccessControl, ReentrancyGuard {
    // Use the library functions from OpenZeppelin
    using Strings for uint256;

    uint256 public feeRate = 100; // Fee rate 1% decimals 4
    bool withdrawalEnabled = true;
    address internal payoutAddress = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714;
    BridgeVault public vault;
    
    /** Events */
    event BridgeBurned(address caller, uint256 amt, address token);
    event VaultDeposit(address depositor, uint256 amt, address token);
    event VaultWithdraw(address receiver, uint256 amt, address token);
    event BridgeMinted(address recipient, address token, uint256 amt);
    event BridgeWithdrawn(address recipient, address token, uint256 amt);
    event AdminGranted(address to);
    event AdminRevoked(address to);
    event SigMappingAdded(bytes _key);
    event NewMPCOracleSet(address MPCOracle);
    event WithdrawalEnabledUpdated(bool oldState, bool newState);
    event PayoutSettingsUpdated(address oldPayoutAddress, address newPayoutAddress, uint256 oldFeeRate, uint256 newFeeRate);
    event VaultUpdated(address oldVault, address newVault);
    event NewVaultAdded(address asset);

    constructor() Ownable(msg.sender) {
        payoutAddress = msg.sender; // by default, the payout address is set to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Sets admins
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Ownable");
        _;
    }

    /**
     * @dev Grants admins
     * @param to_ admin address
     */
    function grantAdmin(address to_) public onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, to_);
        emit AdminGranted(to_);
    }

    /**
     * @dev set Withdrawal enabled
     * @param state_ admin address
     */
    function setWithdrawalEnabled(bool state_) external onlyOwner {
        bool oldState = withdrawalEnabled;
        withdrawalEnabled = state_;
        emit WithdrawalEnabledUpdated(oldState, state_);
    }

    /**
     * @dev Revoke admins
     * @param to_ admin address
     */
    function revokeAdmin(address to_) public onlyAdmin {
        require(hasRole(DEFAULT_ADMIN_ROLE, to_), "Ownable");
        revokeRole(DEFAULT_ADMIN_ROLE, to_);
        emit AdminRevoked(to_);
    }

    /**
     * @dev Set fee payout addresses and fee - set at contract launch - in wei
     * @param payoutAddress_ payout address
     * @param feeRate_ fee rate for bridge fee
     */
    function setpayoutAddressess(
        address payoutAddress_,
        uint256 feeRate_
    ) public onlyAdmin {
        address oldPayoutAddress = payoutAddress;
        uint256 oldFeeRate = feeRate;
        payoutAddress = payoutAddress_;
        feeRate = feeRate_;
        emit PayoutSettingsUpdated(oldPayoutAddress, payoutAddress_, oldFeeRate, feeRate_);
    }

    /**
     * @dev Mappings
     */
    struct MPCOracleAddrInfo {
        bool exists;
    }

    /**
     * @dev Map MPCOracle address at blockHeight
     */
    mapping(address => MPCOracleAddrInfo) internal MPCOracleAddrMap;

    function addMPCMapping(address key_) internal {
        MPCOracleAddrMap[key_].exists = true;
    }

    /**
     * @dev Used to set a new MPC address at block height - only MPC signers can update
     * @param MPCO_ new mpc oracle signer address
     */
    function setMPCOracle(address MPCO_) public onlyAdmin {
        addMPCMapping(MPCO_); // store in mapping.
        emit NewMPCOracleSet(MPCO_);
    }

    /**
     * @dev Get MPC Data Transaction
     * @param key_ transaction hash
     * @return boolean true if mpc signer address exists
     */
    function getMPCMapDataTx(address key_) public view returns (bool) {
        return MPCOracleAddrMap[key_].exists;
    }

    /**
     * @dev Struct for mapping transaction history
     */
    struct TransactionInfo {
        string txid;
        bool exists;
        //bool isStealth;
    }

    mapping(bytes => TransactionInfo) internal transactionMap;

    /**
     * @dev add transaction id to mappding to prevent replay attack
     * @param key_ transaction hash
     */
    function addMappingStealth(bytes memory key_) internal {
        require(!transactionMap[key_].exists, "Tx Hash Already Exists");
        transactionMap[key_].exists = true;
        emit SigMappingAdded(key_);
    }

    /**
     * @dev check if transaction already exists
     * @param key_ transaction hash
     * @return boolean
     */
    function keyExistsTx(bytes memory key_) public view returns (bool) {
        return transactionMap[key_].exists;
    }

    /**
     * @dev Teleport bridge data structure
     */
    struct TeleportStruct {
        bytes32 networkIdHash;
        bytes32 tokenAddressHash;
        string tokenAmount;
        address receiverAddress;
        bytes32 receiverAddressHash;
        string decimals;
        LRC20B token;
    }

    /**
     * @dev set vault address for teleport bridge
     * @param vault_ new vault address
     */
    function setVault(address payable vault_) public onlyAdmin {
        require(vault_ != address(0), "Invalid address");
        address oldVault = address(vault);
        vault = BridgeVault(vault_);
        emit VaultUpdated(oldVault, vault_);
    }

    /**
     * @dev add new  vault
     * @param asset_ new vault address
     */
    function addNewVault(address asset_) public onlyAdmin {
        vault.addNewVault(asset_);
        emit NewVaultAdded(asset_);
    }

    /**
     * @dev Transfers the msg.senders coins to Lux vault
     * @param amount_ token amount to transfer
     * @param tokenAddr_ token address to transfer
     */
    function vaultDeposit(uint256 amount_, address tokenAddr_) public payable nonReentrant {
        if (tokenAddr_ != address(0)) {
            IERC20(tokenAddr_).transferFrom(
                msg.sender,
                address(vault),
                amount_
            );
        }
        vault.deposit{value: msg.value}(tokenAddr_, amount_);
        emit VaultDeposit(msg.sender, amount_, tokenAddr_);
    }

    /**
     * @dev Withdraw tokens from vault using MPC signed msg
     * @param amount_ token amount to withdraw
     * @param tokenAddr_ token address to withdraw
     * @param receiver_ receiver's address
     */
    function vaultWithdraw(
        uint256 amount_,
        address tokenAddr_,
        address receiver_
    ) private {
        address _shareAddress;
        if (tokenAddr_ == address(0)) {
            _shareAddress = vault.ethVaultAddress();
        } else {
            _shareAddress = vault.erc20Vault(tokenAddr_);
        }
        IERC20(_shareAddress).approve(address(vault), type(uint256).max);
        vault.withdraw(tokenAddr_, receiver_, amount_);
        emit VaultWithdraw(receiver_, amount_, tokenAddr_);
    }

    /**
     * @dev preview vault withdraw
     * @param tokenAddr_ token address to withdraw
     * @return amount token available amount for withdrawal
     */
    function previewVaultWithdraw(
        address tokenAddr_
    ) public view returns (uint256) {
        return vault.previewWithdraw(tokenAddr_);
    }

    /**
     * @dev Burns the msg.senders coins
     * @param amount_ token amount to burn
     * @param tokenAddr_ token address to burn
     */
    function bridgeBurn(uint256 amount_, address tokenAddr_) public {
        TeleportStruct memory teleport;
        teleport.token = LRC20B(tokenAddr_);
        require(
            (teleport.token.balanceOf(msg.sender) >= amount_),
            "Insufficient token balance"
        );
        teleport.token.bridgeBurn(msg.sender, amount_);
        emit BridgeBurned(msg.sender, amount_, tokenAddr_);
    }

    /**
     * @dev Concat data to sign
     * @param amt_ token amount
     * @param toTargetAddrStr_ target address to mint
     * @param txid_ tx hash
     * @param tokenAddrStrHash_ hashed token address
     * @param chainIdStr_ chain id
     * @param decimalStr_ decimal of source token
     * @param vault_ usage of valult
     */
    /**
     * @dev Concat data to sign using abi.encode to prevent hash collisions
     * @notice Uses abi.encode instead of abi.encodePacked to prevent collision attacks
     *         with multiple dynamic-length arguments
     */
    function append(
        string memory amt_,
        string memory toTargetAddrStr_,
        string memory txid_,
        string memory tokenAddrStrHash_,
        string memory chainIdStr_,
        string memory decimalStr_,
        string memory vault_
    ) internal pure returns (string memory) {
        return
            string(
                abi.encode(
                    amt_,
                    toTargetAddrStr_,
                    txid_,
                    tokenAddrStrHash_,
                    chainIdStr_,
                    decimalStr_,
                    vault_
                )
            );
    }

    /**
     * @dev split ECDSA signature to r, s, v
     * @param sig ECDSA signature
     * @return splitted_ v,s,r
     */
    function splitSignature(
        bytes memory sig
    ) internal pure returns (uint8, bytes32, bytes32) {
        require(sig.length == 65, "invalid Length");
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    /**
     * @dev recover signer from message and ECDSA signature
     * @param message_ message to be signed
     * @param sig_ ECDSA signature
     * @return signer signer of ECDSA
     */
    function recoverSigner(
        bytes32 message_,
        bytes memory sig_
    ) internal pure returns (address) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = splitSignature(sig_);
        return ECDSA.recover(message_, v, r, s);
    }

    /**
     * @dev Builds a prefixed hash to mimic the behavior of eth_sign
     * @return prefixed prefixed msg
     */
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    /**
     * @dev get signer from tx data
     * @notice Sets the vault address. Sig can only be claimed once.
     * @param hashedTxId_ hashed tx id in source chain
     * @param toTokenAddress_ token address in destination chain
     * @param tokenAmount_ token amount that is transfered to lux vault in source chain
     * @param fromTokenDecimals_ token decimal of source token
     * @param receiverAddress_ destinatoin address to mint in destination chain
     * @param signedTXInfo_ mpc signed msg from teleport oracle network
     * @param vault_ if usage of vault
     * @return signer return signer address of message
     */
    function previewBridgeStealth(
        string memory hashedTxId_,
        address toTokenAddress_,
        uint256 tokenAmount_,
        uint256 fromTokenDecimals_,
        address receiverAddress_,
        bytes memory signedTXInfo_,
        string memory vault_
    ) public view returns (address) {
        TeleportStruct memory teleport;
        // Hash calculations
        teleport.tokenAddressHash = keccak256(
            abi.encodePacked(toTokenAddress_)
        );
        teleport.token = LRC20B(toTokenAddress_);
        teleport.receiverAddress = receiverAddress_;
        teleport.receiverAddressHash = keccak256(
            abi.encodePacked(receiverAddress_)
        );
        teleport.tokenAmount = Strings.toString(tokenAmount_);
        teleport.decimals = Strings.toString(fromTokenDecimals_);
        teleport.networkIdHash = keccak256(
            abi.encodePacked(block.chainid.toString())
        );
        // Concatenate message
        string memory message = append(
            Strings.toHexString(uint256(teleport.networkIdHash), 32),
            hashedTxId_,
            Strings.toHexString(uint256(teleport.tokenAddressHash), 32),
            teleport.tokenAmount,
            teleport.decimals,
            Strings.toHexString(uint256(teleport.receiverAddressHash), 32),
            vault_
        );

        address signer = recoverSigner(
            prefixed(keccak256(abi.encodePacked(message))),
            signedTXInfo_
        );
        return signer;
    }
    /**
     * @dev stealth mint tokens using mpc signature
     * @notice Sets the vault address. Sig can only be claimed once.
     * @param hashedTxId_ hashed tx id in source chain
     * @param toTokenAddress_ token address in destination chain
     * @param tokenAmount_ token amount that is transfered to lux vault in source chain
     * @param fromTokenDecimals_ token decimal of source token
     * @param receiverAddress_ destinatoin address to mint in destination chain
     * @param signedTXInfo_ mpc signed msg from teleport oracle network
     * @param vault_ if usage of vault
     * @return signer return signer address of message
     */
    function bridgeMintStealth(
        string memory hashedTxId_,
        address toTokenAddress_,
        uint256 tokenAmount_,
        uint256 fromTokenDecimals_,
        address receiverAddress_,
        bytes memory signedTXInfo_,
        string memory vault_
    ) external nonReentrant returns (address) {
        TeleportStruct memory teleport;
        // Hash calculations
        teleport.tokenAddressHash = keccak256(
            abi.encodePacked(toTokenAddress_)
        );
        teleport.token = LRC20B(toTokenAddress_);
        teleport.receiverAddress = receiverAddress_;
        teleport.receiverAddressHash = keccak256(
            abi.encodePacked(receiverAddress_)
        );
        teleport.tokenAmount = Strings.toString(tokenAmount_);
        teleport.decimals = Strings.toString(fromTokenDecimals_);
        teleport.networkIdHash = keccak256(
            abi.encodePacked(block.chainid.toString())
        );
        // Concatenate message
        string memory message = append(
            Strings.toHexString(uint256(teleport.networkIdHash), 32),
            hashedTxId_,
            Strings.toHexString(uint256(teleport.tokenAddressHash), 32),
            teleport.tokenAmount,
            teleport.decimals,
            Strings.toHexString(uint256(teleport.receiverAddressHash), 32),
            vault_
        );
        // Check if signedTxInfo already exists
        require(
            !transactionMap[signedTXInfo_].exists,
            "Duplicated Transaction Hash"
        );
        address signer = recoverSigner(
            prefixed(keccak256(abi.encodePacked(message))),
            signedTXInfo_
        );

        // Check if signer is MPCOracle and corresponds to the correct LRC20B
        require(MPCOracleAddrMap[signer].exists, "Unauthorized Signature");

        // Calculate fee and adjust amount
        uint256 _toTokenDecimals = teleport.token.decimals();
        uint256 _amount = (tokenAmount_ * 10 ** _toTokenDecimals) /
            (10 ** fromTokenDecimals_);
        teleport.token.bridgeMint(teleport.receiverAddress, _amount);
        // Add new transaction ID mapping
        addMappingStealth(signedTXInfo_);

        emit BridgeMinted(
            teleport.receiverAddress,
            toTokenAddress_,
            _amount
        );
        return signer;
    }

    /**
     * @dev withdraw tokens using mpc signature
     * @notice Sets the vault address. Sig can only be claimed once.
     * @param hashedTxId_ hashed tx id in source chain
     * @param toTokenAddress_ token address in destination chain
     * @param tokenAmount_ token amount that is transfered to lux vault in source chain
     * @param fromTokenDecimals_ token decimal of source token
     * @param receiverAddress_ destinatoin address to mint in destination chain
     * @param signedTXInfo_ mpc signed msg from teleport oracle network
     * @param vault_ if usage of vault
     * @return signer return signer address of message
     */
    function bridgeWithdrawStealth(
        string memory hashedTxId_,
        address toTokenAddress_,
        uint256 tokenAmount_,
        uint256 fromTokenDecimals_,
        address receiverAddress_,
        bytes memory signedTXInfo_,
        string memory vault_
    ) external nonReentrant returns (address) {
        require(withdrawalEnabled == true, "Withdrawl not enabled!");

        TeleportStruct memory teleport;
        // Hash calculations
        teleport.tokenAddressHash = keccak256(
            abi.encodePacked(toTokenAddress_)
        );
        teleport.token = LRC20B(toTokenAddress_);
        teleport.receiverAddress = receiverAddress_;
        teleport.receiverAddressHash = keccak256(
            abi.encodePacked(receiverAddress_)
        );
        teleport.tokenAmount = Strings.toString(tokenAmount_);
        teleport.decimals = Strings.toString(fromTokenDecimals_);
        teleport.networkIdHash = keccak256(
            abi.encodePacked(block.chainid.toString())
        );
        // Concatenate message
        string memory message = append(
            Strings.toHexString(uint256(teleport.networkIdHash), 32),
            hashedTxId_,
            Strings.toHexString(uint256(teleport.tokenAddressHash), 32),
            teleport.tokenAmount,
            teleport.decimals,
            Strings.toHexString(uint256(teleport.receiverAddressHash), 32),
            vault_
        );
        // Check if signedTxInfo already exists
        require(
            !transactionMap[signedTXInfo_].exists,
            "Duplicated Transaction Hash"
        );
        address signer = recoverSigner(
            prefixed(keccak256(abi.encodePacked(message))),
            signedTXInfo_
        );

        // Check if signer is MPCOracle and corresponds to the correct LRC20B
        require(MPCOracleAddrMap[signer].exists, "Unauthorized Signature");

        uint256 _amount = 0;

        if (toTokenAddress_ == address(0)) {
            _amount = (tokenAmount_ * 10 ** 18) / (10 ** fromTokenDecimals_);
        } else {
            _amount =
                (tokenAmount_ * 10 ** teleport.token.decimals()) /
                (10 ** fromTokenDecimals_);
        }
        uint256 _bridgeFee = (_amount * feeRate) / 10 ** 4;
        uint256 _adjustedAmount = _amount - _bridgeFee; // Use a local variable
        // withdraw tokens
        vaultWithdraw(_bridgeFee, toTokenAddress_, payoutAddress);
        vaultWithdraw(
            _adjustedAmount,
            toTokenAddress_,
            teleport.receiverAddress
        );
        // Add new transaction ID mapping
        addMappingStealth(signedTXInfo_);

        emit BridgeWithdrawn(
            teleport.receiverAddress,
            toTokenAddress_,
            _amount
        );
        return signer;
    }

    /**
     * @dev send funds
     * @param amount_ token amount
     * @param tokenAddr_ token address
     * @param receiver_ receiver address
     */
    function pullWithdraw(
        uint256 amount_,
        address tokenAddr_,
        address receiver_
    ) external onlyOwner nonReentrant {
        address shareAddress;
        if (tokenAddr_ == address(0)) {
            shareAddress = vault.ethVaultAddress();
        } else {
            shareAddress = vault.erc20Vault(tokenAddr_);
        }
        IERC20(shareAddress).approve(address(vault), type(uint256).max);
        vault.withdraw(tokenAddr_, receiver_, amount_);
        emit VaultWithdraw(receiver_, amount_, tokenAddr_);
    }

    receive() external payable {}
}
