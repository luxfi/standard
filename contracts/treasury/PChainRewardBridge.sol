// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IWarp, WarpLib} from "../crypto/precompiles/IWarp.sol";

interface IValidatorVault {
    function registerValidator(bytes32 validatorId, address rewardAddress, uint256 commissionBps) external;
    function updateValidatorStake(bytes32 validatorId, uint256 totalDelegated) external;
    function distributeRewards(uint256 amount) external;
}

interface IProtocolVault {
    function depositRewards(uint256 amount) external;
}

/**
 * @title PChainRewardBridge
 * @notice Bridges P-Chain validator rewards to C-Chain
 *
 * CROSS-CHAIN REWARD FLOW:
 * ┌──────────────────────────────────────────────────────────────────────────────┐
 * │  P-Chain (Validators)                                                        │
 * │  ┌─────────────┐                                                             │
 * │  │ Block       │ ─── Staking Rewards ──► Warp Message                       │
 * │  │ Production  │                              │                              │
 * │  └─────────────┘                              │                              │
 * └───────────────────────────────────────────────┼──────────────────────────────┘
 *                                                  │ Warp
 * ┌───────────────────────────────────────────────┼──────────────────────────────┐
 * │  C-Chain (DeFi)                               ▼                              │
 * │  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                    │
 * │  │ PChain      │ ──► │ Validator   │ ──► │ FeeSplitter │                    │
 * │  │ RewardBridge│     │ Vault       │     │             │                    │
 * │  └─────────────┘     └─────────────┘     └──────┬──────┘                    │
 * │                                                  │                           │
 * │                      ┌───────────────────────────┼────────────────┐          │
 * │                      ▼                           ▼                ▼          │
 * │                  Protocol Vault              DAO Treasury    ValidatorVault  │
 * │                      │                                                       │
 * │                      ▼                                                       │
 * │                  sLUX Stakers                                                │
 * └──────────────────────────────────────────────────────────────────────────────┘
 *
 * Message Types:
 * - VALIDATOR_REGISTERED: New validator registered on P-Chain
 * - STAKE_UPDATE: Validator's total delegated stake changed
 * - REWARD_DISTRIBUTION: Epoch rewards ready for distribution
 */
contract PChainRewardBridge is Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    bytes32 public constant VALIDATOR_REGISTERED = keccak256("VALIDATOR_REGISTERED");
    bytes32 public constant STAKE_UPDATE = keccak256("STAKE_UPDATE");
    bytes32 public constant REWARD_DISTRIBUTION = keccak256("REWARD_DISTRIBUTION");

    // ============ State ============

    /// @notice LUX token (WLUX on C-Chain)
    IERC20 public immutable lux;

    /// @notice ValidatorVault for P-Chain validator rewards
    IValidatorVault public validatorVault;

    /// @notice Protocol Vault Safe for sLUX staker rewards
    address public protocolVault;

    /// @notice P-Chain blockchain ID (for Warp verification)
    bytes32 public pChainId;

    /// @notice Trusted relayer addresses (can submit Warp messages)
    mapping(address => bool) public trustedRelayers;

    /// @notice Processed message IDs (prevent replay)
    mapping(bytes32 => bool) public processedMessages;

    /// @notice Stats
    uint256 public totalRewardsReceived;
    uint256 public totalRewardsDistributed;
    uint256 public lastRewardTime;

    // ============ Events ============

    event ValidatorSynced(bytes32 indexed validatorId, address rewardAddress, uint256 commissionBps);
    event StakeUpdated(bytes32 indexed validatorId, uint256 totalDelegated);
    event RewardsReceived(uint256 amount, uint256 epoch);
    event RewardsDistributed(uint256 toValidators, uint256 toProtocol);
    event RelayerUpdated(address indexed relayer, bool trusted);

    // ============ Errors ============

    error InvalidPChainId();
    error InvalidRelayer();
    error MessageAlreadyProcessed();
    error InvalidMessageType();

    // ============ Constructor ============

    constructor(
        address _lux,
        address _validatorVault,
        address _protocolVault,
        bytes32 _pChainId
    ) Ownable(msg.sender) {
        lux = IERC20(_lux);
        validatorVault = IValidatorVault(_validatorVault);
        protocolVault = _protocolVault;
        pChainId = _pChainId;
    }

    // ============ Admin Functions ============

    function setTrustedRelayer(address relayer, bool trusted) external onlyOwner {
        trustedRelayers[relayer] = trusted;
        emit RelayerUpdated(relayer, trusted);
    }

    function setValidatorVault(address _validatorVault) external onlyOwner {
        validatorVault = IValidatorVault(_validatorVault);
    }

    function setProtocolVault(address _protocolVault) external onlyOwner {
        protocolVault = _protocolVault;
    }

    function setPChainId(bytes32 _pChainId) external onlyOwner {
        pChainId = _pChainId;
    }

    // ============ Bridge Functions ============

    /**
     * @notice Process a Warp message from P-Chain
     * @param warpIndex Index of the Warp message in the transaction
     */
    function processWarpMessage(uint32 warpIndex) external {
        // Get verified Warp message
        IWarp.WarpMessage memory message = WarpLib.getVerifiedMessageOrRevert(warpIndex);

        // Verify source chain is P-Chain
        if (message.sourceChainID != pChainId) revert InvalidPChainId();

        // Decode message type and data
        (bytes32 messageType, bytes memory data) = abi.decode(message.payload, (bytes32, bytes));

        // Compute message ID for replay protection
        bytes32 messageId = keccak256(message.payload);
        if (processedMessages[messageId]) revert MessageAlreadyProcessed();
        processedMessages[messageId] = true;

        // Process based on message type
        if (messageType == VALIDATOR_REGISTERED) {
            _processValidatorRegistered(data);
        } else if (messageType == STAKE_UPDATE) {
            _processStakeUpdate(data);
        } else if (messageType == REWARD_DISTRIBUTION) {
            _processRewardDistribution(data);
        } else {
            revert InvalidMessageType();
        }
    }

    /**
     * @notice Manual reward distribution (for trusted relayers)
     * @dev Used when Warp is not available or for testing
     */
    function distributeRewards(
        uint256 validatorShare,
        uint256 protocolShare
    ) external {
        if (!trustedRelayers[msg.sender]) revert InvalidRelayer();

        uint256 total = validatorShare + protocolShare;

        // Transfer LUX from caller
        lux.safeTransferFrom(msg.sender, address(this), total);

        // Distribute to ValidatorVault
        if (validatorShare > 0) {
            lux.safeTransfer(address(validatorVault), validatorShare);
            validatorVault.distributeRewards(validatorShare);
        }

        // Distribute to Protocol Vault (for sLUX stakers)
        if (protocolShare > 0) {
            lux.safeTransfer(protocolVault, protocolShare);
        }

        totalRewardsReceived += total;
        totalRewardsDistributed += total;
        lastRewardTime = block.timestamp;

        emit RewardsDistributed(validatorShare, protocolShare);
    }

    /**
     * @notice Sync validator from P-Chain (for trusted relayers)
     */
    function syncValidator(
        bytes32 validatorId,
        address rewardAddress,
        uint256 commissionBps,
        uint256 totalDelegated
    ) external {
        if (!trustedRelayers[msg.sender]) revert InvalidRelayer();

        validatorVault.registerValidator(validatorId, rewardAddress, commissionBps);
        validatorVault.updateValidatorStake(validatorId, totalDelegated);

        emit ValidatorSynced(validatorId, rewardAddress, commissionBps);
        emit StakeUpdated(validatorId, totalDelegated);
    }

    // ============ Internal Functions ============

    function _processValidatorRegistered(bytes memory data) internal {
        (bytes32 validatorId, address rewardAddress, uint256 commissionBps) = 
            abi.decode(data, (bytes32, address, uint256));

        validatorVault.registerValidator(validatorId, rewardAddress, commissionBps);
        emit ValidatorSynced(validatorId, rewardAddress, commissionBps);
    }

    function _processStakeUpdate(bytes memory data) internal {
        (bytes32 validatorId, uint256 totalDelegated) = 
            abi.decode(data, (bytes32, uint256));

        validatorVault.updateValidatorStake(validatorId, totalDelegated);
        emit StakeUpdated(validatorId, totalDelegated);
    }

    function _processRewardDistribution(bytes memory data) internal {
        (uint256 epoch, uint256 validatorShare, uint256 protocolShare) = 
            abi.decode(data, (uint256, uint256, uint256));

        uint256 total = validatorShare + protocolShare;
        totalRewardsReceived += total;

        emit RewardsReceived(total, epoch);

        // Note: Actual LUX transfer happens via native bridge or mint
        // This just records the distribution intention
        // In production, rewards would be minted or bridged separately
    }
}
