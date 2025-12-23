// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title Account
/// @notice Lux smart account - ERC-4337 compatible account abstraction
/// @dev Minimal smart contract wallet with session keys, batching, and recovery
contract Account is Initializable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    struct UserOperation {
        address sender;
        uint256 nonce;
        bytes initCode;
        bytes callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
        bytes signature;
    }

    struct SessionKey {
        address key;
        uint48 validAfter;
        uint48 validUntil;
        uint256 spendingLimit;
        uint256 spent;
        address[] allowedTargets;
        bool active;
    }

    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice ERC-4337 EntryPoint
    address public constant ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;

    /// @notice Account version
    string public constant VERSION = "1.0.0";

    /// @notice EIP-712 domain separator
    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Owner of this account
    address public owner;

    /// @notice Account nonce for replay protection
    uint256 public nonce;

    /// @notice Guardian for social recovery
    address public guardian;

    /// @notice Recovery delay in seconds
    uint256 public recoveryDelay = 2 days;

    /// @notice Pending recovery request
    address public pendingOwner;
    uint256 public recoveryInitiated;

    /// @notice Session keys
    mapping(address => SessionKey) public sessionKeys;

    /// @notice Whitelisted modules
    mapping(address => bool) public modules;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Executed(address indexed target, uint256 value, bytes data);
    event BatchExecuted(uint256 count);
    event SessionKeyAdded(address indexed key, uint48 validUntil, uint256 spendingLimit);
    event SessionKeyRevoked(address indexed key);
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event RecoveryInitiated(address indexed newOwner, uint256 executeAfter);
    event RecoveryCancelled();
    event RecoveryExecuted(address indexed oldOwner, address indexed newOwner);
    event ModuleEnabled(address indexed module);
    event ModuleDisabled(address indexed module);
    event Deposited(address indexed token, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error OnlyOwner();
    error OnlyEntryPoint();
    error OnlyGuardian();
    error OnlyModule();
    error InvalidSignature();
    error SessionKeyExpired();
    error SessionKeyInvalid();
    error SpendingLimitExceeded();
    error TargetNotAllowed();
    error RecoveryNotInitiated();
    error RecoveryDelayNotPassed();
    error RecoveryAlreadyInitiated();
    error ExecutionFailed();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyEntryPoint() {
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    modifier onlyModule() {
        if (!modules[msg.sender]) revert OnlyModule();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR / INITIALIZER
    // ═══════════════════════════════════════════════════════════════════════

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize account with owner
    /// @param _owner Account owner
    /// @param _guardian Recovery guardian
    function initialize(address _owner, address _guardian) external initializer {
        owner = _owner;
        guardian = _guardian;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Execute a call from this account
    /// @param target Target address
    /// @param value ETH value
    /// @param data Call data
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyOwner returns (bytes memory) {
        return _execute(target, value, data);
    }

    /// @notice Execute multiple calls
    /// @param calls Array of calls
    function executeBatch(Call[] calldata calls) external onlyOwner returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            results[i] = _execute(calls[i].target, calls[i].value, calls[i].data);
        }
        emit BatchExecuted(calls.length);
    }

    /// @notice Execute via session key
    /// @param target Target address
    /// @param value ETH value
    /// @param data Call data
    /// @param signature Session key signature
    function executeWithSession(
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata signature
    ) external returns (bytes memory) {
        // Recover signer
        bytes32 hash = keccak256(abi.encodePacked(target, value, data, nonce));
        address signer = hash.toEthSignedMessageHash().recover(signature);

        // Validate session key
        SessionKey storage session = sessionKeys[signer];
        if (!session.active) revert SessionKeyInvalid();
        if (block.timestamp < session.validAfter || block.timestamp > session.validUntil) {
            revert SessionKeyExpired();
        }
        if (value > session.spendingLimit - session.spent) {
            revert SpendingLimitExceeded();
        }

        // Check allowed targets
        if (session.allowedTargets.length > 0) {
            bool allowed = false;
            for (uint256 i = 0; i < session.allowedTargets.length; i++) {
                if (session.allowedTargets[i] == target) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) revert TargetNotAllowed();
        }

        // Update spent
        session.spent += value;
        nonce++;

        return _execute(target, value, data);
    }

    /// @notice Execute via module
    function executeFromModule(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyModule returns (bytes memory) {
        return _execute(target, value, data);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC-4337 INTERFACE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Validate user operation
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external onlyEntryPoint returns (uint256 validationData) {
        // Verify signature
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address signer = hash.recover(userOp.signature);

        if (signer == owner) {
            // Owner signature - always valid
            validationData = 0;
        } else if (sessionKeys[signer].active) {
            // Session key - check validity period
            SessionKey storage session = sessionKeys[signer];
            if (block.timestamp < session.validAfter) {
                validationData = _packValidationData(false, session.validUntil, session.validAfter);
            } else if (block.timestamp > session.validUntil) {
                validationData = 1; // Invalid
            } else {
                validationData = _packValidationData(true, session.validUntil, session.validAfter);
            }
        } else {
            validationData = 1; // Invalid signature
        }

        // Pay prefund
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            require(success, "Prefund failed");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SESSION KEYS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Add a session key
    /// @param key Session key address
    /// @param validAfter Start time
    /// @param validUntil End time
    /// @param spendingLimit Max ETH spend
    /// @param allowedTargets Allowed target addresses (empty = any)
    function addSessionKey(
        address key,
        uint48 validAfter,
        uint48 validUntil,
        uint256 spendingLimit,
        address[] calldata allowedTargets
    ) external onlyOwner {
        sessionKeys[key] = SessionKey({
            key: key,
            validAfter: validAfter,
            validUntil: validUntil,
            spendingLimit: spendingLimit,
            spent: 0,
            allowedTargets: allowedTargets,
            active: true
        });

        emit SessionKeyAdded(key, validUntil, spendingLimit);
    }

    /// @notice Revoke a session key
    function revokeSessionKey(address key) external onlyOwner {
        sessionKeys[key].active = false;
        emit SessionKeyRevoked(key);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECOVERY
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Set guardian
    function setGuardian(address newGuardian) external onlyOwner {
        emit GuardianUpdated(guardian, newGuardian);
        guardian = newGuardian;
    }

    /// @notice Initiate recovery (guardian only)
    function initiateRecovery(address newOwner) external onlyGuardian {
        if (pendingOwner != address(0)) revert RecoveryAlreadyInitiated();

        pendingOwner = newOwner;
        recoveryInitiated = block.timestamp;

        emit RecoveryInitiated(newOwner, block.timestamp + recoveryDelay);
    }

    /// @notice Cancel recovery (owner only)
    function cancelRecovery() external onlyOwner {
        pendingOwner = address(0);
        recoveryInitiated = 0;

        emit RecoveryCancelled();
    }

    /// @notice Execute recovery (anyone can call after delay)
    function executeRecovery() external {
        if (pendingOwner == address(0)) revert RecoveryNotInitiated();
        if (block.timestamp < recoveryInitiated + recoveryDelay) {
            revert RecoveryDelayNotPassed();
        }

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        recoveryInitiated = 0;

        emit RecoveryExecuted(oldOwner, owner);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODULES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Enable a module
    function enableModule(address module) external onlyOwner {
        modules[module] = true;
        emit ModuleEnabled(module);
    }

    /// @notice Disable a module
    function disableModule(address module) external onlyOwner {
        modules[module] = false;
        emit ModuleDisabled(module);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECEIVE
    // ═══════════════════════════════════════════════════════════════════════

    receive() external payable {
        emit Deposited(address(0), msg.value);
    }

    /// @notice Deposit ERC20 tokens
    function depositToken(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(token, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get session key info
    function getSessionKey(address key) external view returns (SessionKey memory) {
        return sessionKeys[key];
    }

    /// @notice Check if address is authorized
    function isAuthorized(address addr) external view returns (bool) {
        if (addr == owner) return true;
        if (sessionKeys[addr].active) {
            SessionKey storage session = sessionKeys[addr];
            return block.timestamp >= session.validAfter && block.timestamp <= session.validUntil;
        }
        return false;
    }

    /// @notice EIP-1271 signature validation
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        address signer = hash.toEthSignedMessageHash().recover(signature);
        if (signer == owner || sessionKeys[signer].active) {
            return 0x1626ba7e; // EIP-1271 magic value
        }
        return 0xffffffff;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function _execute(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory result) {
        bool success;
        (success, result) = target.call{value: value}(data);
        if (!success) {
            // Bubble up revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        emit Executed(target, value, data);
    }

    function _packValidationData(
        bool sigValid,
        uint48 validUntil,
        uint48 validAfter
    ) internal pure returns (uint256) {
        return (sigValid ? 0 : 1) | (uint256(validUntil) << 160) | (uint256(validAfter) << 208);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

/// @title AccountFactory
/// @notice Factory for deploying Account contracts
contract AccountFactory {
    /// @notice Account implementation
    address public immutable implementation;

    /// @notice Default guardian
    address public defaultGuardian;

    event AccountCreated(address indexed account, address indexed owner);

    constructor(address _guardian) {
        implementation = address(new Account());
        defaultGuardian = _guardian;
    }

    /// @notice Create a new account
    function createAccount(address owner, bytes32 salt) external returns (address account) {
        account = _deploy(owner, salt);
        emit AccountCreated(account, owner);
    }

    /// @notice Get deterministic account address
    function getAddress(address owner, bytes32 salt) external view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(_getInitCode(owner))
            )
        );
        return address(uint160(uint256(hash)));
    }

    function _deploy(address owner, bytes32 salt) internal returns (address account) {
        bytes memory initCode = _getInitCode(owner);
        assembly {
            account := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        require(account != address(0), "Create2 failed");
    }

    function _getInitCode(address owner) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                implementation,
                abi.encodeCall(Account.initialize, (owner, defaultGuardian))
            )
        );
    }
}

/// @notice Minimal ERC1967 Proxy
contract ERC1967Proxy {
    constructor(address implementation, bytes memory _data) payable {
        assembly {
            sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, implementation)
        }
        if (_data.length > 0) {
            (bool success,) = implementation.delegatecall(_data);
            require(success);
        }
    }

    fallback() external payable {
        assembly {
            let impl := sload(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
