// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    ILightAccountValidator
} from "../../interfaces/dao/deployables/ILightAccountValidator.sol";
import {ILightAccount} from "../../interfaces/light-account/ILightAccount.sol";
import {
    ILightAccountFactory
} from "../../interfaces/light-account/ILightAccountFactory.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title LightAccountValidator
 * @author Lux Industriesn Inc
 * @notice Abstract contract for validating Light Account operations
 * @dev This abstract contract implements ILightAccountValidator, providing
 * validation logic for Light Accounts in ERC-4337 UserOperations.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability safety
 * - Validates Light Accounts against authorized factory
 * - Extracts and validates transaction data from UserOperations
 * - Supports multiple Light Account indices per owner
 * - Abstract - requires concrete implementation
 *
 * Validation process:
 * 1. Verify sender is a contract (not EOA)
 * 2. Verify sender implements Light Account owner() function
 * 3. Verify sender was created by authorized factory
 * 4. Extract and validate execute() call format
 * 5. Return owner and transaction details
 *
 * Security model:
 * - Only accepts Light Accounts from authorized factory
 * - Validates proper execute() encoding to prevent exploits
 * - Ensures inner calldata contains valid function selector
 *
 * @custom:security-contact security@lux.network
 */
abstract contract LightAccountValidator is
    ILightAccountValidator,
    Initializable
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for LightAccountValidator following EIP-7201
     * @dev Contains the Light Account Factory reference for validation
     * @custom:storage-location erc7201:DAO.LightAccountValidator.main
     */
    struct LightAccountValidatorStorage {
        /** @notice The authorized Light Account Factory for address verification */
        ILightAccountFactory lightAccountFactory;
    }

    /**
     * @dev Storage slot for LightAccountValidatorStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.LightAccountValidator.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant LIGHT_ACCOUNT_VALIDATOR_STORAGE_LOCATION =
        0xed41a089afe75bc52b13df3ad8919290164082b965c18c56b129dc0b8138e700;

    /**
     * @dev Returns the storage struct for LightAccountValidator
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for LightAccountValidator
     */
    function _getLightAccountValidatorStorage()
        internal
        pure
        returns (LightAccountValidatorStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := LIGHT_ACCOUNT_VALIDATOR_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Internal initializer for Light Account validation functionality
     * @dev Called by concrete implementations during initialization.
     * Sets up the Light Account Factory reference for validation.
     * @param lightAccountFactory_ The authorized Light Account Factory address
     */
    function __LightAccountValidator_init(
        // solhint-disable-previous-line func-name-mixedcase
        address lightAccountFactory_
    ) internal onlyInitializing {
        LightAccountValidatorStorage
            storage $ = _getLightAccountValidatorStorage();
        $.lightAccountFactory = ILightAccountFactory(lightAccountFactory_);
    }

    // ======================================================================
    // ILightAccountValidator
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ILightAccountValidator
     */
    function lightAccountFactory()
        public
        view
        virtual
        override
        returns (address)
    {
        LightAccountValidatorStorage
            storage $ = _getLightAccountValidatorStorage();
        return address($.lightAccountFactory);
    }

    /**
     * @inheritdoc ILightAccountValidator
     * @dev Useful for handling addresses that could be either EOAs or Light Accounts.
     * Returns the Light Account owner if valid, otherwise returns the input address.
     */
    function potentialLightAccountResolvedOwner(
        address potentialLightAccount_,
        uint256 lightAccountIndex_
    ) public view virtual override returns (address) {
        (bool _isValid, address _lightAccountOwner) = _validateLightAccount(
            potentialLightAccount_,
            lightAccountIndex_
        );

        // If not a valid Light Account, assume it's an EOA
        if (!_isValid) {
            return potentialLightAccount_;
        }

        // Return the Light Account owner
        return _lightAccountOwner;
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Validates if an address is a Light Account created by the authorized factory
     * @dev Performs multiple checks to ensure the address is a legitimate Light Account:
     * 1. Verifies the address is a contract (not EOA)
     * 2. Verifies the contract implements the owner() function
     * 3. Verifies the address matches factory-generated address for the owner
     * @param lightAccount_ The address to validate
     * @param lightAccountIndex_ The index used when creating the Light Account
     * @return isValid True if the address is a valid Light Account
     * @return owner The owner address of the Light Account (zero if invalid)
     */
    function _validateLightAccount(
        address lightAccount_,
        uint256 lightAccountIndex_
    ) internal view virtual returns (bool, address) {
        // Check 1: Verify the address has code (is a contract)
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(lightAccount_)
        }

        // If it's an EOA (no code), it's not a Light Account
        if (size == 0) {
            return (false, address(0));
        }

        // Check 2: Try to call owner() function
        try ILightAccount(lightAccount_).owner() returns (
            address lightAccountOwner_
        ) {
            LightAccountValidatorStorage
                storage $ = _getLightAccountValidatorStorage();

            // Check 3: Verify this Light Account was created by our factory
            // Regenerate the expected light account address
            address lightAccountAddress = $.lightAccountFactory.getAddress(
                lightAccountOwner_,
                lightAccountIndex_
            );

            // If the given address matches the factory-generated address,
            // we know it was created by the authorized factory and can be trusted
            return (lightAccountAddress == lightAccount_, lightAccountOwner_);
        } catch {
            // Contract doesn't implement owner() - not a Light Account
            return (false, address(0));
        }
    }

    /**
     * @notice Validates a UserOperation and extracts transaction details
     * @dev Validates the UserOperation comes from a legitimate Light Account and
     * extracts the actual transaction data from the execute() call encoding.
     * This prevents malicious contracts from impersonating Light Accounts.
     * @param userOp_ The packed UserOperation to validate
     * @return lightAccountOwner The owner of the Light Account
     * @return target The target contract address for the transaction
     * @return innerCallData The actual transaction calldata
     * @custom:throws InvalidLightAccount if sender is not a valid Light Account
     * @custom:throws InvalidUserOpCallDataLength if calldata too short for selector
     * @custom:throws InvalidCallData if not calling Light Account execute()
     * @custom:throws InvalidInnerCallDataLength if inner calldata too short
     */
    function _validateUserOp(
        PackedUserOperation calldata userOp_
    ) internal view virtual returns (address, address, bytes memory) {
        // Step 1: Extract the light account index from paymaster data
        uint256 lightAccountIndex = _extractLightAccountIndex(
            userOp_.paymasterAndData
        );

        // Step 2: Validate the sender is a legitimate Light Account
        (bool _isValid, address _lightAccountOwner) = _validateLightAccount(
            userOp_.sender,
            lightAccountIndex
        );

        if (!_isValid) {
            revert InvalidLightAccount();
        }

        // Security: At this point we've confirmed the sender is a real Light Account
        // created by our factory. This prevents exploits where malicious contracts
        // pretend to be Light Accounts but implement execute() differently.

        // Step 3: Validate we have enough data for a function selector
        if (userOp_.callData.length < 4) {
            revert InvalidUserOpCallDataLength();
        }

        // Step 4: Validate the outer call is to Light Account's execute()
        // 0xb61d27f6 = bytes4(keccak256("execute(address,uint256,bytes)"))
        if (bytes4(userOp_.callData) != 0xb61d27f6) {
            revert InvalidCallData();
        }

        // Step 5: Decode the execute() function parameters
        (address target, , bytes memory innerCallData) = abi.decode(
            userOp_.callData[4:],
            (address, uint256, bytes)
        );

        // Step 6: Validate inner calldata has a function selector
        if (innerCallData.length < 4) {
            revert InvalidInnerCallDataLength();
        }

        return (_lightAccountOwner, target, innerCallData);
    }

    /**
     * @notice Extracts the Light Account index from paymaster data
     * @dev The index is encoded in the paymaster data after standard fields:
     * - Bytes 0-20: Paymaster address
     * - Bytes 20-36: Validation gas limit
     * - Bytes 36-52: Post-op gas limit
     * - Bytes 52-84: Light Account index (if present)
     * @param paymasterAndData_ The paymaster and data from UserOperation
     * @return The Light Account index, or 0 if not present
     */
    function _extractLightAccountIndex(
        bytes calldata paymasterAndData_
    ) internal pure virtual returns (uint256) {
        // Check if we have paymaster data beyond the standard fields
        // Standard fields take up 52 bytes (20 + 16 + 16)
        // We need at least 84 bytes to have the index (52 + 32)
        if (paymasterAndData_.length >= 84) {
            // Extract the index from bytes 52-84
            return uint256(bytes32(paymasterAndData_[52:84]));
        }

        // Default to index 0 for backward compatibility
        return 0;
    }
}
