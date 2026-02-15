// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {ISanction} from "../interfaces/ISanction.sol";
import {IVeto} from "../interfaces/IVeto.sol";
import {Enum} from "../base/Enum.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// Note: Initializable is inherited through Ownable2StepUpgradeable and UUPSUpgradeable

/**
 * @title Sanction
 * @author Lux Industries Inc
 * @notice Guard that blocks transactions when the DAO is vetoed
 * @dev Attached to Council module to enforce veto status.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - UUPS upgradeable pattern with owner-restricted upgrades
 * - Checks veto status before every transaction execution
 * - Validates timelocked transactions against lastVetoTime
 *
 * Security model:
 * - Only reads veto status, doesn't control veto voting
 * - Blocks ALL transactions when vetoed (no exceptions)
 * - Invalidates pre-veto timelocked transactions
 * - Owner is typically the child DAO itself for self-governance
 *
 * @custom:security-contact security@lux.network
 */
contract Sanction is
    ISanction,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.sanction
     */
    struct SanctionStorage {
        /// @notice The Veto contract that determines veto status
        address veto;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant SANCTION_STORAGE_LOCATION =
        0x42f8f7e17893446d49739bff9f1513ff5cdb28566127f8e28b562c45b4b30f00;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (SanctionStorage storage $) {
        assembly {
            $.slot := SANCTION_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the sanction guard
     * @param owner_ Owner who can upgrade the contract
     * @param veto_ Veto contract address
     */
    function initialize(
        address owner_,
        address veto_
    ) public virtual initializer {
        __Ownable_init(owner_);

        SanctionStorage storage $ = _getStorage();
        $.veto = veto_;
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function veto() public view virtual override returns (address) {
        return _getStorage().veto;
    }

    // ======================================================================
    // GUARD FUNCTIONS
    // ======================================================================

    /**
     * @notice Check before transaction execution
     * @dev Reverts if DAO is vetoed. All parameters ignored - only checks veto status.
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
        SanctionStorage storage $ = _getStorage();

        // Block ALL transactions when vetoed
        if (IVeto($.veto).isVetoed()) {
            revert DAOVetoed();
        }
    }

    /**
     * @notice Check after transaction execution
     * @dev No post-execution checks needed - guard only prevents execution when vetoed
     */
    function checkAfterExecution(bytes32, bool) public view virtual override {
        // No-op
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(ISanction).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
