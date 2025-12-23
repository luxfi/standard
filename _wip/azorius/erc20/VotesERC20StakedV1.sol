// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IVersion} from "../../interfaces/dao/deployables/IVersion.sol";
import {
    IVotesERC20StakedV1
} from "../../interfaces/dao/deployables/IVotesERC20StakedV1.sol";
import {IDeploymentBlock} from "../../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ERC20VotesUpgradeable,
    VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title VotesERC20StakedV1
 * @author Lux Industriesn Inc
 * @notice Implementation of non-transferable staking token with rewards distribution
 * @dev This contract implements IVotesERC20StakedV1, providing a staking system
 * where users stake ERC20 tokens and earn multiple reward tokens.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability
 * - Implements UUPS upgradeable pattern with owner-restricted upgrades
 * - Staking tokens are non-transferable
 * - Supports multiple reward tokens including native ETH
 * - Proportional reward distribution based on stake
 * - Minimum staking period enforcement
 *
 * Reward mechanics:
 * - Rewards accumulate continuously based on stake size
 * - Distribution updates global reward rate
 * - Claims calculate pending rewards since last checkpoint
 * - Uses 18 decimal precision for calculations
 *
 * Security considerations:
 * - Reentrancy protection via checks-effects-interactions
 * - Safe math for reward calculations
 * - Owner-controlled reward token addition
 * - Transfer restrictions prevent secondary markets
 *
 * @custom:security-contact security@lux.network
 */
contract VotesERC20StakedV1 is
    IVotesERC20StakedV1,
    IVersion,
    ERC20VotesUpgradeable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    using SafeERC20 for IERC20;

    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for VotesERC20StakedV1 following EIP-7201
     * @dev Contains all staking and rewards state
     * @custom:storage-location erc7201:DAO.VotesERC20Staked.main
     */
    struct VotesERC20StakedStorage {
        /** @notice The ERC20 token that users stake */
        IERC20 stakedToken;
        /** @notice Minimum seconds before unstaking allowed */
        uint256 minimumStakingPeriod;
        /** @notice Total amount of tokens currently staked */
        uint256 totalStaked;
        /** @notice Staking data per address */
        mapping(address staker => StakerData stakerData) stakerData;
        /** @notice Array of all reward token addresses */
        address[] rewardsTokens;
        /** @notice Reward accounting data per token */
        mapping(address rewardsToken => RewardsTokenData rewardsTokenData) rewardsTokenDatas;
    }

    /**
     * @dev Storage slot for VotesERC20StakedStorage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.VotesERC20Staked.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant VOTES_ERC20_STAKED_STORAGE_LOCATION =
        0x83aa32448e81663c7ed9dd6086fc9a74efff7a034dc2ffef9e3a5d9c41ab2400;

    /**
     * @dev Returns the storage struct for VotesERC20StakedV1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for VotesERC20StakedV1
     */
    function _getVotesERC20StakedStorage()
        internal
        pure
        returns (VotesERC20StakedStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VOTES_ERC20_STAKED_STORAGE_LOCATION
        }
    }

    /** @notice Address used to represent native ETH in rewards */
    address internal constant NATIVE_ASSET =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /** @notice Precision for reward rate calculations (18 decimals) */
    uint256 internal constant PRECISION = 10 ** 18;

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    /** @notice Allows contract to receive native ETH for rewards */
    receive() external payable {}

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     * @dev Initializes all inherited contracts and sets up the staking system.
     * The staked token itself cannot be added as a reward token.
     */
    function initialize(
        address owner_,
        address stakedToken_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(abi.encode(owner_, stakedToken_));
        __ERC20_init(
            string(
                abi.encodePacked("Staked ", IERC20Metadata(stakedToken_).name())
            ),
            string(
                abi.encodePacked("st", IERC20Metadata(stakedToken_).symbol())
            )
        );
        __ERC20Votes_init();
        __UUPSUpgradeable_init();
        __Ownable_init(owner_);
        __DeploymentBlockInitializable_init();

        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        $.stakedToken = IERC20(stakedToken_);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function initialize2(
        uint256 minimumStakingPeriod_,
        address[] calldata rewardsTokens_
    ) public virtual override reinitializer(2) {
        _updateMinimumStakingPeriod(minimumStakingPeriod_);
        _addRewardsTokens(rewardsTokens_);
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev Restricts upgrades to owner
     */
    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyOwner {
        // solhint-disable-previous-line no-empty-blocks
        // Intentionally empty - authorization logic handled by onlyOwner modifier
    }

    // ======================================================================
    // IVotesERC20StakedV1
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function CLOCK_MODE()
        // solhint-disable-previous-line func-name-mixedcase
        public
        pure
        virtual
        override(IVotesERC20StakedV1, VotesUpgradeable)
        returns (string memory)
    {
        return "mode=timestamp";
    }

    // --- View Functions ---

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function clock()
        public
        view
        virtual
        override(IVotesERC20StakedV1, VotesUpgradeable)
        returns (uint48)
    {
        return uint48(block.timestamp);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function stakedToken() public view virtual override returns (address) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        return address($.stakedToken);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function minimumStakingPeriod()
        public
        view
        virtual
        override
        returns (uint256)
    {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        return $.minimumStakingPeriod;
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function totalStaked() public view virtual override returns (uint256) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        return $.totalStaked;
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function rewardsTokens()
        public
        view
        virtual
        override
        returns (address[] memory)
    {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        return $.rewardsTokens;
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function rewardsTokenData(
        address token_
    ) public view virtual override returns (uint256, uint256, uint256) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        RewardsTokenData storage _rewardsTokenData = $.rewardsTokenDatas[
            token_
        ];

        if (!_rewardsTokenData.enabled) revert InvalidRewardsToken(token_);

        return (
            _rewardsTokenData.rewardsRate,
            _rewardsTokenData.rewardsDistributed,
            _rewardsTokenData.rewardsClaimed
        );
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function distributableRewards()
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        uint256[] memory distributableRewards_ = new uint256[](
            $.rewardsTokens.length
        );

        for (uint256 i = 0; i < $.rewardsTokens.length; ) {
            distributableRewards_[i] = _distributableRewards(
                $.rewardsTokens[i]
            );

            unchecked {
                ++i;
            }
        }

        return distributableRewards_;
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function distributableRewards(
        address[] calldata rewardsTokens_
    ) public view virtual override returns (uint256[] memory) {
        uint256[] memory distributableRewards_ = new uint256[](
            rewardsTokens_.length
        );

        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        for (uint256 i = 0; i < rewardsTokens_.length; ) {
            address token = rewardsTokens_[i];
            if (!$.rewardsTokenDatas[token].enabled)
                revert InvalidRewardsToken(token);

            distributableRewards_[i] = _distributableRewards(token);

            unchecked {
                ++i;
            }
        }

        return distributableRewards_;
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function stakerData(
        address staker_
    ) public view virtual override returns (uint256, uint256) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        StakerData storage stakerData_ = $.stakerData[staker_];

        return (stakerData_.stakedAmount, stakerData_.lastStakeTimestamp);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function stakerRewardsData(
        address token_,
        address staker_
    ) public view virtual override returns (uint256, uint256) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        RewardsTokenData storage rewardsTokenData_ = $.rewardsTokenDatas[
            token_
        ];

        if (!rewardsTokenData_.enabled) revert InvalidRewardsToken(token_);

        return (
            rewardsTokenData_.stakerRewardsRates[staker_],
            rewardsTokenData_.stakerAccumulatedRewards[staker_]
        );
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function claimableRewards(
        address staker_
    ) public view virtual override returns (uint256[] memory) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        uint256[] memory claimableRewards_ = new uint256[](
            $.rewardsTokens.length
        );

        for (uint256 i = 0; i < $.rewardsTokens.length; ) {
            claimableRewards_[i] = _claimableRewards(
                staker_,
                $.rewardsTokens[i]
            );

            unchecked {
                ++i;
            }
        }

        return claimableRewards_;
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function claimableRewards(
        address staker_,
        address[] calldata tokens_
    ) public view virtual override returns (uint256[] memory) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        uint256[] memory claimableRewards_ = new uint256[](tokens_.length);

        for (uint256 i = 0; i < tokens_.length; ) {
            address token = tokens_[i];
            if (!$.rewardsTokenDatas[token].enabled)
                revert InvalidRewardsToken(token);

            claimableRewards_[i] = _claimableRewards(staker_, token);

            unchecked {
                ++i;
            }
        }

        return claimableRewards_;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function addRewardsTokens(
        address[] calldata rewardsTokens_
    ) public virtual override onlyOwner {
        _addRewardsTokens(rewardsTokens_);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function updateMinimumStakingPeriod(
        uint256 newMinimumStakingPeriod_
    ) public virtual override onlyOwner {
        _updateMinimumStakingPeriod(newMinimumStakingPeriod_);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     * @dev Mints staking tokens 1:1 with staked amount. Updates reward
     * checkpoints before state changes.
     */
    function stake(uint256 amount_) public virtual override {
        if (amount_ == 0) revert ZeroStake();

        // Update rewards before changing stake
        _accumulateRewards(msg.sender);

        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        StakerData storage stakerData_ = $.stakerData[msg.sender];

        // Update staking state
        stakerData_.stakedAmount += amount_;
        stakerData_.lastStakeTimestamp = block.timestamp;
        $.totalStaked += amount_;

        // Mint voting tokens
        _mint(msg.sender, amount_);

        // Transfer staked tokens (external call last)
        $.stakedToken.safeTransferFrom(msg.sender, address(this), amount_);

        emit Staked(msg.sender, amount_);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     * @dev Burns staking tokens and returns staked tokens. Enforces minimum
     * staking period from last stake timestamp.
     */
    function unstake(uint256 amount_) public virtual override {
        if (amount_ == 0) revert ZeroUnstake();

        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        StakerData storage stakerData_ = $.stakerData[msg.sender];

        // Check minimum staking period
        if (
            block.timestamp <
            stakerData_.lastStakeTimestamp + $.minimumStakingPeriod
        ) revert MinimumStakingPeriod();

        // Update rewards before changing stake
        _accumulateRewards(msg.sender);

        // Update staking state
        stakerData_.stakedAmount -= amount_;
        $.totalStaked -= amount_;

        // Burn voting tokens
        _burn(msg.sender, amount_);

        // Return staked tokens (external call last)
        $.stakedToken.safeTransfer(msg.sender, amount_);

        emit Unstaked(msg.sender, amount_);
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function distributeRewards() public virtual override {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        if ($.totalStaked == 0) revert ZeroStaked();

        for (uint256 i = 0; i < $.rewardsTokens.length; ) {
            _distributeRewards($.rewardsTokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function distributeRewards(
        address[] calldata tokens_
    ) public virtual override {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        if ($.totalStaked == 0) revert ZeroStaked();

        for (uint256 i = 0; i < tokens_.length; ) {
            address token = tokens_[i];
            if (!$.rewardsTokenDatas[token].enabled)
                revert InvalidRewardsToken(token);

            _distributeRewards(token);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function claimRewards(address recipient_) public virtual override {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        for (uint256 i = 0; i < $.rewardsTokens.length; ) {
            _claimRewards(msg.sender, recipient_, $.rewardsTokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IVotesERC20StakedV1
     */
    function claimRewards(
        address recipient_,
        address[] calldata tokens_
    ) public virtual override {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        for (uint256 i = 0; i < tokens_.length; ) {
            address token = tokens_[i];
            if (!$.rewardsTokenDatas[token].enabled)
                revert InvalidRewardsToken(token);

            _claimRewards(msg.sender, recipient_, token);

            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // ERC20VotesUpgradeable
    // ======================================================================

    // --- State-Changing Functions ---

    /**
     * @notice Disabled transfer function
     * @dev Staking tokens are non-transferable
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice Disabled transferFrom function
     * @dev Staking tokens are non-transferable
     */
    function transferFrom(
        address,
        address,
        uint256
    ) public virtual override returns (bool) {
        revert NonTransferable();
    }

    /**
     * @notice Disabled approve function
     * @dev Staking tokens are non-transferable
     */
    function approve(address, uint256) public virtual override returns (bool) {
        revert NonTransferable();
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
     * @dev Supports IVotesERC20StakedV1, IERC20, IVotes, IVersion,
     * IDeploymentBlock, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    ) public view virtual override returns (bool) {
        return
            interfaceId_ == type(IVotesERC20StakedV1).interfaceId ||
            interfaceId_ == type(IERC20).interfaceId ||
            interfaceId_ == type(IVotes).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            super.supportsInterface(interfaceId_);
    }

    // ======================================================================
    // INTERNAL HELPERS
    // ======================================================================

    /**
     * @notice Claims accumulated rewards for a staker
     * @dev Resets accumulated rewards and updates checkpoint.
     * Handles both ERC20 and native ETH rewards.
     * @param _claimer The address claiming rewards
     * @param _recipient The address to receive rewards
     * @param _token The reward token to claim
     */
    function _claimRewards(
        address _claimer,
        address _recipient,
        address _token
    ) internal virtual {
        // Calculate claimable amount
        uint256 amountToClaim = _claimableRewards(_claimer, _token);

        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        RewardsTokenData storage token = $.rewardsTokenDatas[_token];

        // Reset rewards and update checkpoint
        token.stakerAccumulatedRewards[_claimer] = 0;
        token.stakerRewardsRates[_claimer] = token.rewardsRate;

        if (amountToClaim == 0) return;

        // Update total claimed
        token.rewardsClaimed += amountToClaim;

        // Transfer rewards (external calls last)
        if (_token == NATIVE_ASSET) {
            // Native ETH transfer
            (bool success, ) = _recipient.call{value: amountToClaim}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 transfer
            IERC20(_token).safeTransfer(_recipient, amountToClaim);
        }

        emit RewardsClaimed(_claimer, _token, _recipient, amountToClaim);
    }

    /**
     * @notice Distributes pending rewards for a token
     * @dev Updates the global reward rate based on new rewards.
     * Rate increase = (new rewards * precision) / total staked
     * @param token_ The reward token to distribute
     */
    function _distributeRewards(address token_) internal virtual {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        RewardsTokenData storage token = $.rewardsTokenDatas[token_];

        // Calculate new rewards to distribute
        uint256 amountToDistribute = _distributableRewards(token_);

        if (amountToDistribute == 0) return;

        // Update global reward rate
        // New rate = old rate + (rewards * precision / total staked)
        uint256 newRewardsRate = token.rewardsRate +
            (amountToDistribute * PRECISION) /
            $.totalStaked;

        // Update accounting
        token.rewardsDistributed += amountToDistribute;
        token.rewardsRate = newRewardsRate;

        emit RewardsDistributed(token_, amountToDistribute, newRewardsRate);
    }

    /**
     * @notice Adds new reward tokens to the contract
     * @dev Validates that tokens aren't already enabled and adds them to the rewards list.
     * Each token starts with a zero reward rate until distributions occur.
     * @param rewardsTokens_ Array of reward token addresses to add
     */
    function _addRewardsTokens(
        address[] calldata rewardsTokens_
    ) internal virtual {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        for (uint256 i = 0; i < rewardsTokens_.length; ) {
            address token = rewardsTokens_[i];

            if ($.rewardsTokenDatas[token].enabled)
                revert DuplicateRewardsToken();

            $.rewardsTokens.push(token);
            $.rewardsTokenDatas[token].enabled = true;

            emit RewardsTokenAdded(token);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Accumulates pending rewards for a staker
     * @dev Called before any stake changes to checkpoint rewards.
     * Calculates rewards based on stake amount and rate differential.
     * @param staker_ The address to accumulate rewards for
     */
    function _accumulateRewards(address staker_) internal virtual {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        // Process each reward token
        for (uint256 i = 0; i < $.rewardsTokens.length; ) {
            RewardsTokenData storage token = $.rewardsTokenDatas[
                $.rewardsTokens[i]
            ];

            // Calculate rewards since last checkpoint
            // rewards = stakeAmount * (currentRate - lastRate) / precision
            token.stakerAccumulatedRewards[staker_] +=
                ($.stakerData[staker_].stakedAmount *
                    (token.rewardsRate - token.stakerRewardsRates[staker_])) /
                PRECISION;

            // Update checkpoint
            token.stakerRewardsRates[staker_] = token.rewardsRate;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Updates the minimum staking period
     * @dev Simply sets the new period and emits an event.
     * Does not affect existing stakes retroactively.
     * @param newMinimumStakingPeriod_ New minimum period in seconds
     */
    function _updateMinimumStakingPeriod(
        uint256 newMinimumStakingPeriod_
    ) internal virtual {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        $.minimumStakingPeriod = newMinimumStakingPeriod_;
        emit MinimumStakingPeriodUpdated(newMinimumStakingPeriod_);
    }

    /**
     * @notice Calculates rewards available for distribution
     * @dev Formula: balance + claimed - distributed
     * Special handling for staked token to exclude staked amount.
     * @param token_ The reward token to check
     * @return Amount available to distribute
     */
    function _distributableRewards(
        address token_
    ) internal view virtual returns (uint256) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();

        RewardsTokenData storage _rewardsTokenData = $.rewardsTokenDatas[
            token_
        ];

        if (!_rewardsTokenData.enabled) revert InvalidRewardsToken(token_);

        // Get current balance
        uint256 thisBalance;
        if (token_ == NATIVE_ASSET) {
            // Native ETH balance
            thisBalance = address(this).balance;
        } else if (token_ == address($.stakedToken)) {
            // For staked token, exclude the staked amount
            thisBalance =
                IERC20(token_).balanceOf(address(this)) -
                $.totalStaked;
        } else {
            // Regular ERC20 balance
            thisBalance = IERC20(token_).balanceOf(address(this));
        }

        // Available = balance + claimed - distributed
        return
            thisBalance +
            _rewardsTokenData.rewardsClaimed -
            _rewardsTokenData.rewardsDistributed;
    }

    /**
     * @notice Calculates claimable rewards for a staker and token
     * @dev Combines accumulated rewards with pending rewards since last checkpoint.
     * Uses the same formula as _accumulateRewards for pending calculation.
     * @param staker_ The address to check rewards for
     * @param token_ The reward token to check
     * @return Total claimable amount (accumulated + pending)
     */
    function _claimableRewards(
        address staker_,
        address token_
    ) internal view virtual returns (uint256) {
        VotesERC20StakedStorage storage $ = _getVotesERC20StakedStorage();
        RewardsTokenData storage token = $.rewardsTokenDatas[token_];

        return
            token.stakerAccumulatedRewards[staker_] +
            (($.stakerData[staker_].stakedAmount *
                (token.rewardsRate - token.stakerRewardsRates[staker_])) /
                PRECISION);
    }
}
