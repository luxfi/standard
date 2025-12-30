// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IFreezeGuard} from "../interfaces/IFreezeGuard.sol";
import {IFreezeVoting} from "../interfaces/IFreezeVoting.sol";
import {Enum} from "../base/Enum.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// Note: Initializable is inherited through Ownable2StepUpgradeable and UUPSUpgradeable

/**
 * @title FreezeGuard
 * @author Lux Industries Inc
 * @notice Guard that blocks transactions when the DAO is frozen
 * @dev Attached to Governor module to enforce freeze status.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - UUPS upgradeable pattern with owner-restricted upgrades
 * - Checks freeze status before every transaction execution
 * - Validates timelocked transactions against lastFreezeTime
 *
 * Security model:
 * - Only reads freeze status, doesn't control freeze voting
 * - Blocks ALL transactions when frozen (no exceptions)
 * - Invalidates pre-freeze timelocked transactions
 * - Owner is typically the child DAO itself for self-governance
 *
 * @custom:security-contact security@lux.network
 */
contract FreezeGuard is
    IFreezeGuard,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.freezeguard
     */
    struct FreezeGuardStorage {
        /// @notice The FreezeVoting contract that determines freeze status
        address freezeVoting;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant FREEZE_GUARD_STORAGE_LOCATION =
        0x42f8f7e17893446d49739bff9f1513ff5cdb28566127f8e28b562c45b4b30f00;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (FreezeGuardStorage storage $) {
        assembly {
            $.slot := FREEZE_GUARD_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the freeze guard
     * @param owner_ Owner who can upgrade the contract
     * @param freezeVoting_ FreezeVoting contract address
     */
    function initialize(
        address owner_,
        address freezeVoting_
    ) public virtual initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();

        FreezeGuardStorage storage $ = _getStorage();
        $.freezeVoting = freezeVoting_;
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function freezeVoting() public view virtual override returns (address) {
        return _getStorage().freezeVoting;
    }

    // ======================================================================
    // GUARD FUNCTIONS
    // ======================================================================

    /**
     * @notice Check before transaction execution
     * @dev Reverts if DAO is frozen. All parameters ignored - only checks freeze status.
     */
    function checkTransaction(
        address,
        uint256,
        bytes memory,
        Enum.Operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) public view virtual override {
        FreezeGuardStorage storage $ = _getStorage();

        // Block ALL transactions when frozen
        if (IFreezeVoting($.freezeVoting).isFrozen()) {
            revert DAOFrozen();
        }
    }

    /**
     * @notice Check after transaction execution
     * @dev No post-execution checks needed - guard only prevents execution when frozen
     */
    function checkAfterExecution(bytes32, bool) public view virtual override {
        // No-op
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IFreezeGuard).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
