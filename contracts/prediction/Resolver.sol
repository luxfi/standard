// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PayoutHelperLib} from "./libraries/PayoutHelperLib.sol";
import {AncillaryDataLib} from "./libraries/AncillaryDataLib.sol";

import {
    IOracle,
    IOracleCallbacks
} from "./interfaces/IOracle.sol";

import {
    QuestionData,
    BondConfig,
    AncillaryDataUpdate,
    IResolver
} from "./interfaces/IResolver.sol";
import {IClaims} from "./claims/interfaces/IClaims.sol";

/// @title IAddressWhitelist
/// @notice Minimal interface for collateral whitelist
interface IAddressWhitelist {
    function isOnWhitelist(address) external view returns (bool);
}

/// @title IFinder
/// @notice Minimal interface for Finder contract
interface IFinder {
    function getImplementationAddress(bytes32 interfaceName) external view returns (address);
}

/// @title Resolver
/// @notice Binds Oracle results to Claims payouts for prediction market resolution
/// @dev Supports configurable bond amounts per market for flexible security requirements.
///      Uses assertTruth pattern for yes/no assertions.
contract Resolver is IResolver, IOracleCallbacks {
    using SafeERC20 for IERC20;

    // ============ Immutables ============

    /// @notice Claims contract
    IClaims public immutable claims;

    /// @notice Oracle
    IOracle public immutable oracle;

    /// @notice Collateral Whitelist
    IAddressWhitelist public immutable collateralWhitelist;

    // ============ Constants ============

    /// @notice Time period after which an admin can manually resolve a condition
    uint256 public constant SAFETY_PERIOD = 1 hours;

    /// @notice Domain ID for prediction market assertions
    bytes32 public constant DOMAIN_ID = keccak256("PREDICTION_MARKET");

    /// @notice Maximum claim length for assertions
    uint256 public constant MAX_CLAIM_LENGTH = 8139;

    // ============ State Variables ============

    /// @notice Mapping of questionID to QuestionData
    mapping(bytes32 => QuestionData) public questions;

    /// @notice Admin mapping (1 = admin, 0 = not admin)
    mapping(address => uint256) public admins;

    /// @notice Mapping of questionID+owner to array of AncillaryDataUpdate
    mapping(bytes32 => AncillaryDataUpdate[]) public updates;

    /// @notice Default bond configuration for all markets
    BondConfig public defaultBondConfig;

    /// @notice Market-specific bond configurations
    mapping(bytes32 => BondConfig) public marketBondConfigs;

    /// @notice Mapping from assertionId to questionID
    mapping(bytes32 => bytes32) internal _assertionToQuestion;

    /// @notice Mapping from questionID to current assertionId
    mapping(bytes32 => bytes32) internal _questionToAssertion;

    // ============ Modifiers ============

    modifier onlyOptimisticOracle() {
        if (msg.sender != address(oracle)) revert NotOracle();
        _;
    }

    modifier onlyAdmin() {
        if (admins[msg.sender] != 1) revert NotAdmin();
        _;
    }

    // ============ Constructor ============

    /// @param _claims The Claims contract address
    ///             For negative risk markets, this should be the NegRiskOperator contract address
    /// @param _finder The Finder contract address
    /// @param _oracle The Oracle contract address
    /// @param _defaultMinBond Default minimum bond amount
    /// @param _defaultMaxBond Default maximum bond amount (0 = no maximum)
    constructor(
        address _claims,
        address _finder,
        address _oracle,
        uint256 _defaultMinBond,
        uint256 _defaultMaxBond
    ) {
        claims = IClaims(_claims);
        IFinder finder = IFinder(_finder);
        oracle = IOracle(_oracle);
        collateralWhitelist = IAddressWhitelist(finder.getImplementationAddress("CollateralWhitelist"));

        admins[msg.sender] = 1;

        // Initialize default bond configuration
        if (_defaultMaxBond != 0 && _defaultMaxBond < _defaultMinBond) revert InvalidBondConfig();
        defaultBondConfig = BondConfig({
            minBond: _defaultMinBond,
            maxBond: _defaultMaxBond,
            customBondEnabled: false
        });
    }

    // ============ Public Functions ============

    /// @inheritdoc IResolver
    function initialize(
        bytes memory ancillaryData,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) external returns (bytes32 questionID) {
        if (!collateralWhitelist.isOnWhitelist(rewardToken)) revert UnsupportedToken();

        bytes memory data = AncillaryDataLib.appendAncillaryData(msg.sender, ancillaryData);
        if (ancillaryData.length == 0 || data.length > MAX_CLAIM_LENGTH) revert InvalidAncillaryData();

        questionID = keccak256(data);

        if (_isInitialized(questions[questionID])) revert Initialized();

        // Validate bond against configuration
        _validateBond(questionID, proposalBond);

        uint256 timestamp = block.timestamp;

        // Persist the question parameters in storage
        _saveQuestion(msg.sender, questionID, data, timestamp, rewardToken, reward, proposalBond, liveness);

        // Prepare the question on the CTF
        claims.prepareCondition(address(this), questionID, 2);

        // Assert truth via Optimistic Oracle
        bytes32 assertionId = _assertTruth(msg.sender, questionID, data, rewardToken, reward, proposalBond, liveness);

        // Store bidirectional mapping
        _assertionToQuestion[assertionId] = questionID;
        _questionToAssertion[questionID] = assertionId;

        emit QuestionInitialized(questionID, timestamp, msg.sender, data, rewardToken, reward, proposalBond);
    }

    /// @inheritdoc IResolver
    function ready(bytes32 questionID) public view returns (bool) {
        return _ready(questions[questionID]);
    }

    /// @inheritdoc IResolver
    function resolve(bytes32 questionID) external {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.paused) revert Paused();
        if (questionData.resolved) revert Resolved();
        if (!_hasPrice(questionData)) revert NotReadyToResolve();

        _resolve(questionID, questionData);
    }

    /// @inheritdoc IResolver
    function getExpectedPayouts(bytes32 questionID) public view returns (uint256[] memory) {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (_isFlagged(questionData)) revert Flagged();
        if (questionData.paused) revert Paused();
        if (!_hasPrice(questionData)) revert PriceNotAvailable();

        // Get assertion result
        bytes32 assertionId = _questionToAssertion[questionID];
        bool assertedTruthfully = oracle.getAssertionResult(assertionId);

        return _constructPayouts(assertedTruthfully);
    }

    // ============ Optimistic Oracle Callbacks ============

    /// @inheritdoc IOracleCallbacks
    /// @notice Called when an assertion is resolved (either by expiry or DVM)
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) external onlyOptimisticOracle {
        bytes32 questionID = _assertionToQuestion[assertionId];
        if (questionID == bytes32(0)) return;

        QuestionData storage questionData = questions[questionID];

        // If already resolved, nothing to do
        if (questionData.resolved) return;
        if (questionData.paused) return;

        // Resolve the question with assertion result
        _resolveWithAssertion(questionID, questionData, assertedTruthfully);
    }

    /// @inheritdoc IOracleCallbacks
    /// @notice Called when an assertion is disputed (escalated to DVM)
    function assertionDisputedCallback(
        bytes32 assertionId
    ) external onlyOptimisticOracle {
        bytes32 questionID = _assertionToQuestion[assertionId];
        if (questionID == bytes32(0)) return;

        QuestionData storage questionData = questions[questionID];

        // If already resolved (e.g., by resolveManually), refund reward to creator
        if (questionData.resolved) {
            IERC20(questionData.rewardToken).safeTransfer(questionData.creator, questionData.reward);
            return;
        }

        if (questionData.reset) {
            questionData.refund = true;
            return;
        }

        // Reset the question on dispute (ensures at most 2 assertions at a time)
        _reset(address(this), questionID, false, questionData);
    }

    /// @inheritdoc IResolver
    function isInitialized(bytes32 questionID) public view returns (bool) {
        return _isInitialized(questions[questionID]);
    }

    /// @inheritdoc IResolver
    function isFlagged(bytes32 questionID) public view returns (bool) {
        return _isFlagged(questions[questionID]);
    }

    /// @inheritdoc IResolver
    function getQuestion(bytes32 questionID) external view returns (QuestionData memory) {
        return questions[questionID];
    }

    // ============ Admin Functions ============

    /// @inheritdoc IResolver
    function flag(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (_isFlagged(questionData)) revert Flagged();
        if (questionData.resolved) revert Resolved();

        questionData.manualResolutionTimestamp = block.timestamp + SAFETY_PERIOD;
        questionData.paused = true;

        emit QuestionFlagged(questionID);
    }

    /// @inheritdoc IResolver
    function unflag(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (!_isFlagged(questionData)) revert NotFlagged();
        if (questionData.resolved) revert Resolved();
        if (block.timestamp > questionData.manualResolutionTimestamp) revert SafetyPeriodPassed();

        questionData.manualResolutionTimestamp = 0;
        questionData.paused = false;

        emit QuestionUnflagged(questionID);
    }

    /// @inheritdoc IResolver
    function reset(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.resolved) revert Resolved();

        if (questionData.refund) _refund(questionData);

        _reset(msg.sender, questionID, true, questionData);
    }

    /// @inheritdoc IResolver
    function resolveManually(bytes32 questionID, uint256[] calldata payouts) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isValidPayoutArray(payouts)) revert InvalidPayouts();
        if (!_isInitialized(questionData)) revert NotInitialized();
        if (!_isFlagged(questionData)) revert NotFlagged();
        if (block.timestamp < questionData.manualResolutionTimestamp) revert SafetyPeriodNotPassed();

        questionData.resolved = true;

        if (questionData.refund) _refund(questionData);

        claims.reportPayouts(questionID, payouts);
        emit QuestionManuallyResolved(questionID, payouts);
    }

    /// @inheritdoc IResolver
    function pause(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();
        if (questionData.resolved) revert Resolved();

        questionData.paused = true;
        emit QuestionPaused(questionID);
    }

    /// @inheritdoc IResolver
    function unpause(bytes32 questionID) external onlyAdmin {
        QuestionData storage questionData = questions[questionID];

        if (!_isInitialized(questionData)) revert NotInitialized();

        questionData.paused = false;
        emit QuestionUnpaused(questionID);
    }

    // ============ Bond Configuration Functions ============

    /// @inheritdoc IResolver
    function setDefaultBondConfig(uint256 minBond, uint256 maxBond) external onlyAdmin {
        if (maxBond != 0 && maxBond < minBond) revert InvalidBondConfig();

        defaultBondConfig.minBond = minBond;
        defaultBondConfig.maxBond = maxBond;

        emit DefaultBondConfigUpdated(minBond, maxBond);
    }

    /// @inheritdoc IResolver
    function setMarketBondConfig(
        bytes32 questionID,
        uint256 minBond,
        uint256 maxBond,
        bool enabled
    ) external onlyAdmin {
        if (enabled && maxBond != 0 && maxBond < minBond) revert InvalidBondConfig();

        marketBondConfigs[questionID] = BondConfig({
            minBond: minBond,
            maxBond: maxBond,
            customBondEnabled: enabled
        });

        emit MarketBondConfigUpdated(questionID, minBond, maxBond, enabled);
    }

    /// @inheritdoc IResolver
    function getEffectiveBondConfig(bytes32 questionID) external view returns (uint256 minBond, uint256 maxBond) {
        BondConfig storage marketConfig = marketBondConfigs[questionID];

        if (marketConfig.customBondEnabled) {
            return (marketConfig.minBond, marketConfig.maxBond);
        }

        return (defaultBondConfig.minBond, defaultBondConfig.maxBond);
    }

    /// @inheritdoc IResolver
    function getDefaultBondConfig() external view returns (BondConfig memory) {
        return defaultBondConfig;
    }

    /// @inheritdoc IResolver
    function getMarketBondConfig(bytes32 questionID) external view returns (BondConfig memory) {
        return marketBondConfigs[questionID];
    }

    // ============ Auth Functions ============

    /// @inheritdoc IResolver
    function addAdmin(address admin) external onlyAdmin {
        admins[admin] = 1;
        emit NewAdmin(msg.sender, admin);
    }

    /// @inheritdoc IResolver
    function removeAdmin(address admin) external onlyAdmin {
        admins[admin] = 0;
        emit RemovedAdmin(msg.sender, admin);
    }

    /// @inheritdoc IResolver
    function renounceAdmin() external onlyAdmin {
        admins[msg.sender] = 0;
        emit RemovedAdmin(msg.sender, msg.sender);
    }

    /// @inheritdoc IResolver
    function isAdmin(address addr) external view returns (bool) {
        return admins[addr] == 1;
    }

    // ============ Bulletin Board Functions ============

    /// @inheritdoc IResolver
    function postUpdate(bytes32 questionID, bytes memory update) external {
        bytes32 id = keccak256(abi.encode(questionID, msg.sender));
        updates[id].push(AncillaryDataUpdate({ timestamp: block.timestamp, update: update }));
        emit AncillaryDataUpdated(questionID, msg.sender, update);
    }

    /// @inheritdoc IResolver
    function getUpdates(bytes32 questionID, address owner) public view returns (AncillaryDataUpdate[] memory) {
        return updates[keccak256(abi.encode(questionID, owner))];
    }

    /// @inheritdoc IResolver
    function getLatestUpdate(bytes32 questionID, address owner) external view returns (AncillaryDataUpdate memory) {
        AncillaryDataUpdate[] memory currentUpdates = getUpdates(questionID, owner);
        if (currentUpdates.length == 0) {
            return AncillaryDataUpdate({ timestamp: 0, update: "" });
        }
        return currentUpdates[currentUpdates.length - 1];
    }

    // ============ Internal Functions ============

    function _ready(QuestionData storage questionData) internal view returns (bool) {
        if (!_isInitialized(questionData)) return false;
        if (questionData.paused) return false;
        if (questionData.resolved) return false;
        return _hasPrice(questionData);
    }

    function _saveQuestion(
        address creator,
        bytes32 questionID,
        bytes memory ancillaryData,
        uint256 requestTimestamp,
        address rewardToken,
        uint256 reward,
        uint256 proposalBond,
        uint256 liveness
    ) internal {
        questions[questionID] = QuestionData({
            requestTimestamp: requestTimestamp,
            reward: reward,
            proposalBond: proposalBond,
            liveness: liveness,
            manualResolutionTimestamp: 0,
            resolved: false,
            paused: false,
            reset: false,
            refund: false,
            rewardToken: rewardToken,
            creator: creator,
            ancillaryData: ancillaryData
        });
    }

    /// @notice Validates the bond amount against the effective configuration
    /// @param questionID The question ID (may not exist yet for new questions)
    /// @param bond The bond amount to validate
    function _validateBond(bytes32 questionID, uint256 bond) internal view {
        BondConfig storage marketConfig = marketBondConfigs[questionID];

        uint256 minBond;
        uint256 maxBond;

        if (marketConfig.customBondEnabled) {
            minBond = marketConfig.minBond;
            maxBond = marketConfig.maxBond;
        } else {
            minBond = defaultBondConfig.minBond;
            maxBond = defaultBondConfig.maxBond;
        }

        if (bond < minBond) revert BondTooLow();
        if (maxBond != 0 && bond > maxBond) revert BondTooHigh();
    }

    /// @notice Assert truth via Optimistic Oracle     /// @param requestor The address requesting the assertion
    /// @param questionID The question identifier
    /// @param claim The claim/question data to assert
    /// @param rewardToken The token used for bonds/rewards
    /// @param reward Reward for successful assertion (added to bond return)
    /// @param bond The bond amount
    /// @param liveness The liveness period in seconds
    /// @return assertionId The assertion identifier
    function _assertTruth(
        address requestor,
        bytes32 questionID,
        bytes memory claim,
        address rewardToken,
        uint256 reward,
        uint256 bond,
        uint256 liveness
    ) internal returns (bytes32 assertionId) {
        // Transfer reward + bond from requestor
        uint256 totalAmount = reward + bond;
        if (totalAmount > 0 && requestor != address(this)) {
            IERC20(rewardToken).safeTransferFrom(requestor, address(this), totalAmount);
        }

        // Approve Optimistic Oracle to spend bond
        if (bond > 0) {
            IERC20(rewardToken).forceApprove(address(oracle), bond);
        }

        // Use default identifier from Optimistic Oracle
        bytes32 identifier = oracle.defaultIdentifier();

        // Assert truth via Optimistic Oracle
        assertionId = oracle.assertTruth(
            claim,                       // claim (the question/assertion)
            address(this),               // asserter
            address(this),               // callbackRecipient
            address(0),                  // escalationManager (use default DVM)
            uint64(liveness),            // liveness
            IERC20(rewardToken),         // currency
            bond,                        // bond
            identifier,                  // identifier
            DOMAIN_ID                    // domainId
        );
    }

    /// @notice Reset the question by creating a new assertion
    function _reset(
        address requestor,
        bytes32 questionID,
        bool resetRefund,
        QuestionData storage questionData
    ) internal {
        uint256 requestTimestamp = block.timestamp;

        questionData.requestTimestamp = requestTimestamp;
        questionData.reset = true;
        if (resetRefund) questionData.refund = false;

        // Create new assertion for the reset question
        bytes32 assertionId = _assertTruth(
            requestor,
            questionID,
            questionData.ancillaryData,
            questionData.rewardToken,
            questionData.reward,
            questionData.proposalBond,
            questionData.liveness
        );

        // Update mappings
        _assertionToQuestion[assertionId] = questionID;
        _questionToAssertion[questionID] = assertionId;

        emit QuestionReset(questionID);
    }

    /// @notice Resolves the underlying CTF market using assertion settle
    function _resolve(bytes32 questionID, QuestionData storage questionData) internal {
        bytes32 assertionId = _questionToAssertion[questionID];

        // Settle and get assertion result
        bool assertedTruthfully = oracle.settleAndGetAssertionResult(assertionId);

        _resolveWithAssertion(questionID, questionData, assertedTruthfully);
    }

    /// @notice Resolves the CTF market with assertion result
    function _resolveWithAssertion(bytes32 questionID, QuestionData storage questionData, bool assertedTruthfully) internal {
        questionData.resolved = true;

        if (questionData.refund) _refund(questionData);

        uint256[] memory payouts = _constructPayouts(assertedTruthfully);

        claims.reportPayouts(questionID, payouts);

        // Convert bool to int256 for event compatibility (1 = YES, 0 = NO)
        int256 price = assertedTruthfully ? int256(1 ether) : int256(0);
        emit QuestionResolved(questionID, price, payouts);
    }

    /// @notice Check if an assertion has been settled
    function _hasPrice(QuestionData storage questionData) internal view returns (bool) {
        bytes32 assertionId = _questionToAssertion[keccak256(questionData.ancillaryData)];
        if (assertionId == bytes32(0)) return false;

        // Check if assertion is settled by checking the assertion data
        IOracle.Assertion memory assertion = oracle.getAssertion(assertionId);
        return assertion.settled;
    }

    function _refund(QuestionData storage questionData) internal {
        IERC20(questionData.rewardToken).safeTransfer(questionData.creator, questionData.reward);
    }

    function _isFlagged(QuestionData storage questionData) internal view returns (bool) {
        return questionData.manualResolutionTimestamp > 0;
    }

    function _isInitialized(QuestionData storage questionData) internal view returns (bool) {
        return questionData.ancillaryData.length > 0;
    }

    /// @notice Construct the payout array given assertion result
    /// @param assertedTruthfully True if the assertion was confirmed, false otherwise
    function _constructPayouts(bool assertedTruthfully) internal pure returns (uint256[] memory) {
        uint256[] memory payouts = new uint256[](2);

        if (assertedTruthfully) {
            // YES: Report [Yes, No] as [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        } else {
            // NO: Report [Yes, No] as [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        }

        return payouts;
    }

    /// @notice Construct the payout array given the price (V2 compatibility - kept for manual resolution)
    /// @param price The price (0 = NO, 0.5 ether = UNKNOWN, 1 ether = YES)
    function _constructPayouts(int256 price) internal pure returns (uint256[] memory) {
        uint256[] memory payouts = new uint256[](2);

        // Valid prices are 0, 0.5 ether (50%), and 1 ether (100%)
        if (price != 0 && price != 0.5 ether && price != 1 ether) revert InvalidOOPrice();

        if (price == 0) {
            // NO: Report [Yes, No] as [0, 1]
            payouts[0] = 0;
            payouts[1] = 1;
        } else if (price == 0.5 ether) {
            // UNKNOWN: Report [Yes, No] as [1, 1], 50/50
            // Note: tie is not valid with NegRiskOperator
            payouts[0] = 1;
            payouts[1] = 1;
        } else {
            // YES: Report [Yes, No] as [1, 0]
            payouts[0] = 1;
            payouts[1] = 0;
        }

        return payouts;
    }

    /// @notice Validates a payout array from the admin
    function _isValidPayoutArray(uint256[] calldata payouts) internal pure returns (bool) {
        return PayoutHelperLib.isValidPayoutArray(payouts);
    }

    function _ignorePrice() internal pure returns (int256) {
        return type(int256).min;
    }
}
