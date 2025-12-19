// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {
    IFunctionValidator
} from "../../interfaces/dao/services/IFunctionValidator.sol";
import {IStrategyV1} from "../../interfaces/dao/deployables/IStrategyV1.sol";
import {
    IVotingTypes
} from "../../interfaces/dao/deployables/IVotingTypes.sol";
import {IVersion} from "../../interfaces/dao/deployables/IVersion.sol";
import {IDeploymentBlock} from "../../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockNonInitializable
} from "../../DeploymentBlockNonInitializable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title StrategyV1ValidatorV1
 * @author Lux Industriesn Inc
 * @notice Validator for gasless voting through ERC-4337 and Light Accounts
 * @dev This contract implements IFunctionValidator, enabling gas-sponsored voting
 * operations through the DAOPaymasterV1 and ERC-4337 infrastructure.
 *
 * Gasless voting flow:
 * 1. User signs a vote operation off-chain (no gas needed)
 * 2. ERC-4337 bundler submits the operation through user's Light Account
 * 3. DAOPaymasterV1 receives the operation for validation
 * 4. Paymaster calls this validator to check if gas should be sponsored
 * 5. This validator calls StrategyV1.validStrategyVote for eligibility check
 * 6. StrategyV1 uses getVotingWeightForPaymaster to avoid banned opcodes
 * 7. If valid, paymaster sponsors the gas and vote is executed
 *
 * Key features:
 * - Only validates castVote operations on StrategyV1 contracts
 * - Ensures voters have sufficient voting weight before sponsoring gas
 * - Works around ERC-4337 banned opcodes (block.timestamp, block.number)
 * - Stateless singleton service contract per chain
 *
 * @custom:security-contact security@lux.network
 */
contract StrategyV1ValidatorV1 is
    IFunctionValidator,
    IVersion,
    DeploymentBlockNonInitializable,
    ERC165
{
    // ======================================================================
    // IFunctionValidator
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc IFunctionValidator
     * @dev Validates castVote operations for gas sponsorship eligibility.
     * This function is called by DAOPaymasterV1 during the ERC-4337 validation phase
     * to determine if a vote should receive free gas sponsorship.
     *
     * The validation delegates to StrategyV1.validStrategyVote which uses
     * getVotingWeightForPaymaster() to calculate voting weight without triggering
     * ERC-4337 banned opcodes (block.timestamp, block.number).
     */
    function validateOperation(
        address,
        address lightAccountOwner_,
        address strategy_,
        bytes calldata callData_
    ) public view virtual override returns (bool) {
        // confirm here that the calldata selector is correct: `castVote(uint32,uint8,(address,bytes)[],uint256)`
        if (bytes4(callData_) != IStrategyV1.castVote.selector) {
            return false;
        }

        // Decode vote parameters from callData
        // castVote(uint32 proposalId_, uint8 voteType_, (tuple(uint256,bytes))[] votingConfigsData_, uint256 lightAccountIndex_)
        (
            uint32 proposalId,
            uint8 voteType,
            IVotingTypes.VotingConfigVoteData[] memory votingConfigsData,

        ) = abi.decode(
                callData_[4:], // skip selector
                (uint32, uint8, IVotingTypes.VotingConfigVoteData[], uint256)
            );

        return
            IStrategyV1(strategy_).validStrategyVote(
                lightAccountOwner_,
                proposalId,
                voteType,
                votingConfigsData
            );
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
     * @dev Supports IFunctionValidator, IVersion, IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IFunctionValidator).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
