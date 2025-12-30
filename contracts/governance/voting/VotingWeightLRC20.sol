// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.31;

import {IVotingWeight} from "../interfaces/IVotingWeight.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/**
 * @title VotingWeightLRC20
 * @author Lux Industries Inc
 * @notice Voting weight calculator for LRC20 tokens (Lux ERC20 standard)
 * @dev Calculates voting weight based on delegated token balance.
 *
 * Features:
 * - EIP-7201 namespaced storage for upgrade safety
 * - Uses getPastVotes for historical balance lookups
 * - Configurable weight multiplier
 * - EIP-4337 compatible getVotingWeightForPaymaster
 *
 * @custom:security-contact security@lux.network
 */
contract VotingWeightLRC20 is IVotingWeight, ERC165, Initializable {
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct following EIP-7201
     * @custom:storage-location erc7201:lux.governance.votingweight.lrc20
     */
    struct VotingWeightStorage {
        /// @notice The IVotes token used for weight calculation
        IVotes token;
        /// @notice Multiplier applied to token balances (1e18 = 1x)
        uint256 weightPerToken;
    }

    /**
     * @dev Storage slot calculated using EIP-7201 formula
     */
    bytes32 internal constant VOTING_WEIGHT_STORAGE_LOCATION =
        0x4a628306ba980ddb34c4192717ceb138b4220728372b52bc617057971ff9e400;

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    function _getStorage() internal pure returns (VotingWeightStorage storage $) {
        assembly {
            $.slot := VOTING_WEIGHT_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the voting weight calculator
     * @param token_ The IVotes token address
     * @param weightPerToken_ Multiplier for weight calculation (1e18 = 1x)
     */
    function initialize(
        address token_,
        uint256 weightPerToken_
    ) public virtual initializer {
        VotingWeightStorage storage $ = _getStorage();
        $.token = IVotes(token_);
        $.weightPerToken = weightPerToken_;
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function token() public view virtual returns (address) {
        return address(_getStorage().token);
    }

    function weightPerToken() public view virtual returns (uint256) {
        return _getStorage().weightPerToken;
    }

    // ======================================================================
    // IVotingWeight
    // ======================================================================

    /**
     * @notice Calculate voting weight for an address
     * @dev Returns delegated balance at timestamp multiplied by weightPerToken
     * @param voter The voter address
     * @param timestamp The timestamp to calculate weight at
     * @param voteData Ignored for LRC20 (no token IDs needed)
     * @return weight The voting weight
     * @return processedData Empty bytes (no processing needed)
     */
    function calculateWeight(
        address voter,
        uint256 timestamp,
        bytes calldata voteData
    ) external view virtual override returns (uint256 weight, bytes memory processedData) {
        VotingWeightStorage storage $ = _getStorage();

        weight = $.token.getPastVotes(voter, timestamp) * $.weightPerToken;
        processedData = "";
    }

    /**
     * @notice Get voting weight for EIP-4337 paymaster validation
     * @dev Avoids banned opcodes (block.timestamp, block.number) by manually
     * iterating through checkpoints instead of using getPastVotes
     * @param voter The voter address
     * @param timestamp The timestamp to calculate weight at
     * @param voteData Ignored for LRC20
     * @return weight The voting weight
     */
    function getVotingWeightForPaymaster(
        address voter,
        uint256 timestamp,
        bytes calldata voteData
    ) external view virtual override returns (uint256 weight) {
        VotingWeightStorage storage $ = _getStorage();

        // Cast to ERC20Votes to access checkpoints
        ERC20Votes governanceToken = ERC20Votes(address($.token));

        // Get checkpoint count
        uint32 numCheckpoints = governanceToken.numCheckpoints(voter);
        if (numCheckpoints == 0) return 0;

        // Find checkpoint at or before timestamp (iterate backwards)
        uint256 votingBalance = 0;
        for (uint256 i = numCheckpoints; i > 0;) {
            Checkpoints.Checkpoint208 memory checkpoint = governanceToken.checkpoints(voter, uint32(i - 1));

            if (checkpoint._key <= timestamp) {
                votingBalance = checkpoint._value;
                break;
            }

            unchecked { --i; }
        }

        return votingBalance * $.weightPerToken;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IVotingWeight).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
