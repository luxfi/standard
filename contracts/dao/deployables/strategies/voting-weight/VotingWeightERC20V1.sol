// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IVotingWeightERC20V1
} from "../../../interfaces/deployables/IVotingWeightERC20V1.sol";
import {
    IVotingWeightV1
} from "../../../interfaces/deployables/IVotingWeightV1.sol";
import {IVersion} from "../../../interfaces/deployables/IVersion.sol";
import {
    IDeploymentBlock
} from "../../../interfaces/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../../InitializerEventEmitter.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    Checkpoints
} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {
    ERC20Votes
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title VotingWeightERC20V1
 * @author Lux Industriesn Inc
 * @notice Implementation of voting weight calculation for ERC20 tokens
 * @dev This contract implements IVotingWeightV1 for ERC20Votes tokens.
 * It calculates voting weight based on delegated token balance at a specific timestamp.
 *
 * Key features:
 * - Uses getPastVotes for historical balance lookups
 * - Supports configurable weight multiplier
 * - No vote data needed (ERC20 is one vote per address)
 * - Returns empty processedData
 *
 * @custom:security-contact security@lux.network
 */
contract VotingWeightERC20V1 is
    IVotingWeightERC20V1,
    IVotingWeightV1,
    IVersion,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for VotingWeightERC20V1 following EIP-7201
     * @dev Contains token configuration for weight calculation
     * @custom:storage-location erc7201:DAO.VotingWeightERC20.main
     */
    struct VotingWeightERC20Storage {
        /** @notice The IVotes token used for voting weight calculation */
        IVotes token;
        /** @notice Multiplier applied to token balances for weight calculation */
        uint256 weightPerToken;
    }

    /**
     * @dev Storage slot for VotingWeightERC20Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.VotingWeightERC20.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant VOTING_WEIGHT_ERC20_STORAGE_LOCATION =
        0x4a628306ba980ddb34c4192717ceb138b4220728372b52bc617057971ff9e400;

    /**
     * @dev Returns the storage struct for VotingWeightERC20V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for VotingWeightERC20V1
     */
    function _getVotingWeightERC20Storage()
        internal
        pure
        returns (VotingWeightERC20Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VOTING_WEIGHT_ERC20_STORAGE_LOCATION
        }
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVotingWeightERC20V1
     */
    function initialize(
        address token_,
        uint256 weightPerToken_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(token_, weightPerToken_));
        __DeploymentBlockInitializable_init();

        VotingWeightERC20Storage storage $ = _getVotingWeightERC20Storage();
        $.token = IVotes(token_);
        $.weightPerToken = weightPerToken_;
    }

    // ======================================================================
    // IVotingWeightERC20V1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVotingWeightERC20V1
     */
    function token() public view virtual override returns (address) {
        VotingWeightERC20Storage storage $ = _getVotingWeightERC20Storage();
        return address($.token);
    }

    /**
     * @inheritdoc IVotingWeightERC20V1
     */
    function weightPerToken() public view virtual override returns (uint256) {
        VotingWeightERC20Storage storage $ = _getVotingWeightERC20Storage();
        return $.weightPerToken;
    }

    // ======================================================================
    // IVotingWeightV1
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IVotingWeightV1
     * @dev For ERC20 tokens:
     * - Ignores voteData_ parameter (no token IDs needed)
     * - Returns delegated balance at timestamp multiplied by weightPerToken
     * - Returns empty bytes for processedData
     */
    function calculateWeight(
        address voter_,
        uint256 timestamp_,
        bytes calldata /* voteData_ */
    ) external view virtual override returns (uint256, bytes memory) {
        VotingWeightERC20Storage storage $ = _getVotingWeightERC20Storage();

        // Get historical voting power (delegated balance)
        // Safe to cast timestamp to uint48 as it's within reasonable range
        // Calculate weight with multiplier
        // No processed data needed for ERC20
        return (
            $.token.getPastVotes(voter_, timestamp_) * $.weightPerToken,
            ""
        );
    }

    /**
     * @inheritdoc IVotingWeightV1
     * @dev Implementation for ERC-4337 paymaster validation that avoids banned opcodes.
     * This function manually iterates through ERC20Votes checkpoints to find the
     * voting weight at the specified timestamp without calling getPastVotes().
     * This is less efficient than calculateWeight() but necessary for gasless voting
     * validation where block.timestamp and block.number are prohibited.
     * Returns 0 if the voter has no checkpoints or no balance at the timestamp.
     */
    function getVotingWeightForPaymaster(
        address voter_,
        uint256 timestamp_,
        bytes calldata /* voteData_ */
    ) external view virtual override returns (uint256) {
        VotingWeightERC20Storage storage $ = _getVotingWeightERC20Storage();

        // Step 1: Get the token as ERC20Votes to access checkpoints
        // This cast is safe as we verify the token implements IVotes in initialize()
        ERC20Votes governanceToken = ERC20Votes(address($.token));

        // Step 2: Get checkpoint count for the voter
        // Checkpoints track historical balances at specific timestamps
        uint32 numCheckpoints = governanceToken.numCheckpoints(voter_);

        // If no checkpoints exist, voter has never had tokens
        if (numCheckpoints == 0) {
            return 0;
        }

        // Step 3: Find the checkpoint at or before the timestamp
        // We manually iterate instead of using getPastVotes() to avoid banned opcodes
        uint256 votingBalance = 0;

        // Iterate backwards through checkpoints (more efficient for recent timestamps)
        // This mimics the logic of getPastVotes() without using block.timestamp
        for (uint256 i = numCheckpoints; i > 0; ) {
            // Get checkpoint (indices are 0-based, loop counter is 1-based)
            Checkpoints.Checkpoint208 memory checkpoint = governanceToken
                .checkpoints(voter_, uint32(i - 1));

            // Check if this checkpoint was created at or before our target timestamp
            // checkpoint._key contains the timestamp when the balance changed
            if (checkpoint._key <= timestamp_) {
                votingBalance = checkpoint._value;
                break;
            }

            unchecked {
                --i;
            }
        }

        // Apply weight multiplier
        return votingBalance * $.weightPerToken;
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports IVotingWeightERC20V1, IVotingWeightV1, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IVotingWeightERC20V1).interfaceId ||
            interfaceId_ == type(IVotingWeightV1).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
