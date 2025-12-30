// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IProposerAdapter} from "../interfaces/IProposerAdapter.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title ProposerAdapterLRC20
 * @author Lux Industries Inc
 * @notice Proposer eligibility based on LRC20 voting power
 * @dev Determines who can create proposals based on delegated token voting power.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - Uses getVotes() for current voting power
 * - Requires delegation (users must delegate to themselves)
 * - Zero threshold allows anyone to propose
 *
 * @custom:security-contact security@lux.network
 */
contract ProposerAdapterLRC20 is IProposerAdapter, ERC165, Initializable {
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.proposer.lrc20
     */
    struct ProposerStorage {
        /// @notice The IVotes token used for voting power checks
        IVotes token;
        /// @notice Minimum voting power required to create proposals
        uint256 proposerThreshold;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant PROPOSER_STORAGE_LOCATION =
        0xd0ff3bfab69583661d8803345254b7701c2125007ad7e3ef64473e569aca5400;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (ProposerStorage storage $) {
        assembly {
            $.slot := PROPOSER_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the proposer adapter
     * @param token_ The IVotes token address
     * @param proposerThreshold_ Minimum voting power to propose (0 = anyone)
     */
    function initialize(
        address token_,
        uint256 proposerThreshold_
    ) public virtual initializer {
        ProposerStorage storage $ = _getStorage();
        $.token = IVotes(token_);
        $.proposerThreshold = proposerThreshold_;
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function token() public view virtual returns (address) {
        return address(_getStorage().token);
    }

    function proposerThreshold() public view virtual returns (uint256) {
        return _getStorage().proposerThreshold;
    }

    // ======================================================================
    // IProposerAdapter
    // ======================================================================

    /**
     * @notice Check if address can create proposals
     * @dev Uses getVotes() for current delegated voting power (not token balance)
     * @param proposer The address to check
     * @param data Ignored for LRC20 adapters
     * @return True if proposer has sufficient voting power
     */
    function isProposer(
        address proposer,
        bytes calldata data
    ) public view virtual override returns (bool) {
        ProposerStorage storage $ = _getStorage();
        return $.token.getVotes(proposer) >= $.proposerThreshold;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IProposerAdapter).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
