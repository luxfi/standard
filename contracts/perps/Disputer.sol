// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    IOracle,
    IOracleCallbacks
} from "../prediction/interfaces/IOracle.sol";

import {
    DisputeBondConfig,
    PriceDispute,
    IDisputer
} from "./interfaces/IDisputer.sol";

import {IFastPriceFeed} from "./oracle/interfaces/IFastPriceFeed.sol";
import {IVaultPriceFeed} from "./core/interfaces/IVaultPriceFeed.sol";
import {ISecondaryPriceFeed} from "./oracle/interfaces/ISecondaryPriceFeed.sol";

/// @title Disputer
/// @notice Binds Oracle to perps integrity via price dispute resolution
/// @dev Provides economic security for perps by allowing bonded price disputes
///      that escalate to the DVM if needed. Uses assertTruth pattern.
contract Disputer is IDisputer, IOracleCallbacks {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Price identifier for DVM escalation
    bytes32 public constant PRICE_IDENTIFIER = "ASSERT_TRUTH";

    /// @notice Domain ID for perps disputes (grouping assertions)
    bytes32 public constant DOMAIN_ID = keccak256("PERPS_PRICE_DISPUTE");

    /// @notice Basis points divisor
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    /// @notice Maximum circuit breaker threshold (50%)
    uint256 public constant MAX_CIRCUIT_BREAKER_THRESHOLD = 5000;

    /// @notice Price precision (30 decimals, matching GMX)
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    // ============ Immutables ============

    /// @notice Oracle
    IOracle public immutable oracle;

    /// @notice Fast price feed (secondary/fast oracle)
    address public immutable override fastPriceFeed;

    /// @notice Vault price feed (primary oracle)
    address public immutable override vaultPriceFeed;

    /// @notice Token used for dispute bonds
    address public immutable override bondToken;

    /// @notice Dispute liveness period in seconds
    uint64 public immutable _livenessSeconds;

    // ============ State Variables ============

    /// @notice Admin mapping (1 = admin, 0 = not admin)
    mapping(address => uint256) public admins;

    /// @notice Default bond configuration
    DisputeBondConfig public defaultBondConfig;

    /// @notice Token-specific bond configurations
    mapping(address => DisputeBondConfig) public tokenBondConfigs;

    /// @notice Active disputes by ID
    mapping(bytes32 => PriceDispute) public disputes;

    /// @notice Circuit breaker threshold in basis points
    uint256 public override circuitBreakerThreshold;

    /// @notice Circuit breaker status per token
    mapping(address => bool) public override isCircuitBreakerActive;

    /// @notice Mapping from Oracle assertionId to dispute ID
    mapping(bytes32 => bytes32) internal _assertionToDispute;

    /// @notice Mapping from dispute ID to Oracle assertionId
    mapping(bytes32 => bytes32) internal _disputeToAssertion;

    // ============ Modifiers ============

    modifier onlyAdmin() {
        if (admins[msg.sender] != 1) revert NotAdmin();
        _;
    }

    modifier onlyOptimisticOracle() {
        if (msg.sender != address(oracle)) revert NotOracle();
        _;
    }

    // ============ Constructor ============

    /// @param _oracle Oracle address
    /// @param _fastPriceFeed FastPriceFeed contract address
    /// @param _vaultPriceFeed VaultPriceFeed contract address
    /// @param _bondToken Token used for dispute bonds (e.g., USDC)
    /// @param _liveness Dispute liveness period in seconds
    /// @param _defaultMinBond Default minimum bond amount
    /// @param _defaultMaxBond Default maximum bond amount (0 = no max)
    /// @param _circuitBreakerThreshold Initial circuit breaker threshold in bps
    constructor(
        address _oracle,
        address _fastPriceFeed,
        address _vaultPriceFeed,
        address _bondToken,
        uint64 _liveness,
        uint256 _defaultMinBond,
        uint256 _defaultMaxBond,
        uint256 _circuitBreakerThreshold
    ) {
        if (_oracle == address(0)) revert InvalidToken();
        if (_fastPriceFeed == address(0)) revert InvalidToken();
        if (_vaultPriceFeed == address(0)) revert InvalidToken();
        if (_bondToken == address(0)) revert InvalidToken();

        oracle = IOracle(_oracle);
        fastPriceFeed = _fastPriceFeed;
        vaultPriceFeed = _vaultPriceFeed;
        bondToken = _bondToken;
        _livenessSeconds = _liveness;

        // Set default bond config
        if (_defaultMaxBond != 0 && _defaultMaxBond < _defaultMinBond) {
            revert InvalidBondConfig();
        }
        defaultBondConfig = DisputeBondConfig({
            minBond: _defaultMinBond,
            maxBond: _defaultMaxBond,
            customBondEnabled: false
        });

        // Set circuit breaker threshold
        if (_circuitBreakerThreshold > MAX_CIRCUIT_BREAKER_THRESHOLD) {
            revert InvalidBondConfig();
        }
        circuitBreakerThreshold = _circuitBreakerThreshold;

        // Set deployer as admin
        admins[msg.sender] = 1;
        emit AdminAdded(msg.sender);
    }

    // ============ Dispute Functions ============

    /// @inheritdoc IDisputer
    function disputePrice(
        address token,
        uint256 claimedCorrectPrice,
        uint256 bond
    ) external returns (bytes32 disputeId) {
        if (token == address(0)) revert InvalidToken();
        if (claimedCorrectPrice == 0) revert InvalidPrice();

        // Validate bond amount
        _validateBond(token, bond);

        // Get current fast price
        uint256 currentFastPrice = _getFastPrice(token);
        if (currentFastPrice == 0) revert InvalidPrice();

        // Ensure claimed price differs from current
        if (claimedCorrectPrice == currentFastPrice) revert InvalidPrice();

        // Generate dispute ID
        disputeId = keccak256(
            abi.encodePacked(
                token,
                currentFastPrice,
                claimedCorrectPrice,
                block.timestamp,
                msg.sender
            )
        );

        // Ensure no duplicate dispute
        if (disputes[disputeId].timestamp != 0) revert DisputeAlreadyExists();

        // Store dispute data
        disputes[disputeId] = PriceDispute({
            token: token,
            disputedPrice: currentFastPrice,
            claimedPrice: claimedCorrectPrice,
            timestamp: block.timestamp,
            disputer: msg.sender,
            bond: bond,
            resolved: false,
            disputerWon: false
        });

        // Transfer bond from disputer
        IERC20(bondToken).safeTransferFrom(msg.sender, address(this), bond);

        // Construct claim for V3 assertTruth
        bytes memory claim = _constructClaim(
            token,
            currentFastPrice,
            claimedCorrectPrice,
            block.timestamp
        );

        // Assert truth via Optimistic Oracle
        bytes32 assertionId = _assertTruth(disputeId, claim, bond);

        // Store bidirectional mapping
        _assertionToDispute[assertionId] = disputeId;
        _disputeToAssertion[disputeId] = assertionId;

        emit PriceDisputeCreated(
            disputeId,
            token,
            msg.sender,
            currentFastPrice,
            claimedCorrectPrice,
            bond
        );
    }

    /// @inheritdoc IDisputer
    function settleDispute(bytes32 disputeId) external {
        PriceDispute storage dispute = disputes[disputeId];

        if (dispute.timestamp == 0) revert DisputeNotFound();
        if (dispute.resolved) revert DisputeAlreadyResolved();

        // Get the assertion ID for this dispute
        bytes32 assertionId = _disputeToAssertion[disputeId];
        if (assertionId == bytes32(0)) revert DisputeNotFound();

        // Settle assertion and get result via V3 API
        bool assertedTruthfully = oracle.settleAndGetAssertionResult(assertionId);

        // Convert boolean result to price resolution
        // If assertedTruthfully = true, the claimed price was correct (disputer wins)
        // If assertedTruthfully = false, the disputed price was correct (disputer loses)
        _resolveDisputeV3(disputeId, assertedTruthfully);
    }

    /// @inheritdoc IDisputer
    function getDispute(bytes32 disputeId) external view returns (PriceDispute memory) {
        return disputes[disputeId];
    }

    /// @inheritdoc IDisputer
    function isDisputeActive(bytes32 disputeId) external view returns (bool) {
        PriceDispute storage dispute = disputes[disputeId];
        return dispute.timestamp != 0 && !dispute.resolved;
    }

    // ============ Optimistic Oracle Callbacks ============

    /// @inheritdoc IOracleCallbacks
    /// @notice Called when an assertion is resolved (either by expiry or DVM)
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) external onlyOptimisticOracle {
        bytes32 disputeId = _assertionToDispute[assertionId];

        if (disputeId != bytes32(0) && !disputes[disputeId].resolved) {
            _resolveDisputeV3(disputeId, assertedTruthfully);
        }
    }

    /// @inheritdoc IOracleCallbacks
    /// @notice Called when an assertion is disputed (escalated to DVM)
    function assertionDisputedCallback(
        bytes32 assertionId
    ) external onlyOptimisticOracle {
        // Dispute escalated to DVM - emit event for monitoring
        // Resolution will happen via assertionResolvedCallback
        bytes32 disputeId = _assertionToDispute[assertionId];
        if (disputeId != bytes32(0)) {
            // Optional: emit an event for monitoring escalation
            // The actual resolution happens in assertionResolvedCallback
        }
    }

    // ============ Bond Configuration ============

    /// @inheritdoc IDisputer
    function setDefaultBondConfig(uint256 minBond, uint256 maxBond) external onlyAdmin {
        if (maxBond != 0 && maxBond < minBond) revert InvalidBondConfig();

        defaultBondConfig.minBond = minBond;
        defaultBondConfig.maxBond = maxBond;

        emit DefaultBondConfigUpdated(minBond, maxBond);
    }

    /// @inheritdoc IDisputer
    function setTokenBondConfig(
        address token,
        uint256 minBond,
        uint256 maxBond,
        bool enabled
    ) external onlyAdmin {
        if (enabled && maxBond != 0 && maxBond < minBond) revert InvalidBondConfig();

        tokenBondConfigs[token] = DisputeBondConfig({
            minBond: minBond,
            maxBond: maxBond,
            customBondEnabled: enabled
        });

        emit TokenBondConfigUpdated(token, minBond, maxBond, enabled);
    }

    /// @inheritdoc IDisputer
    function getEffectiveBondConfig(address token)
        external
        view
        returns (uint256 minBond, uint256 maxBond)
    {
        DisputeBondConfig storage tokenConfig = tokenBondConfigs[token];

        if (tokenConfig.customBondEnabled) {
            return (tokenConfig.minBond, tokenConfig.maxBond);
        }

        return (defaultBondConfig.minBond, defaultBondConfig.maxBond);
    }

    // ============ Circuit Breaker ============

    /// @inheritdoc IDisputer
    function setCircuitBreakerThreshold(uint256 thresholdBps) external onlyAdmin {
        if (thresholdBps > MAX_CIRCUIT_BREAKER_THRESHOLD) revert InvalidBondConfig();

        circuitBreakerThreshold = thresholdBps;

        emit CircuitBreakerThresholdUpdated(thresholdBps);
    }

    /// @inheritdoc IDisputer
    function resetCircuitBreaker(address token) external onlyAdmin {
        isCircuitBreakerActive[token] = false;
    }

    // ============ Admin Functions ============

    /// @inheritdoc IDisputer
    function addAdmin(address admin) external onlyAdmin {
        admins[admin] = 1;
        emit AdminAdded(admin);
    }

    /// @inheritdoc IDisputer
    function removeAdmin(address admin) external onlyAdmin {
        admins[admin] = 0;
        emit AdminRemoved(admin);
    }

    /// @inheritdoc IDisputer
    function isAdmin(address addr) external view returns (bool) {
        return admins[addr] == 1;
    }

    /// @inheritdoc IDisputer
    function optimisticOracle() external view override returns (address) {
        return address(oracle);
    }

    /// @inheritdoc IDisputer
    function liveness() external view override returns (uint256) {
        return uint256(_livenessSeconds);
    }

    // ============ Internal Functions ============

    /// @notice Validate bond amount against configuration
    function _validateBond(address token, uint256 bond) internal view {
        DisputeBondConfig storage tokenConfig = tokenBondConfigs[token];

        uint256 minBond;
        uint256 maxBond;

        if (tokenConfig.customBondEnabled) {
            minBond = tokenConfig.minBond;
            maxBond = tokenConfig.maxBond;
        } else {
            minBond = defaultBondConfig.minBond;
            maxBond = defaultBondConfig.maxBond;
        }

        if (bond < minBond) revert BondTooLow();
        if (maxBond != 0 && bond > maxBond) revert BondTooHigh();
    }

    /// @notice Get current fast price for a token
    function _getFastPrice(address token) internal view returns (uint256) {
        // Get the reference price from VaultPriceFeed
        uint256 refPrice = IVaultPriceFeed(vaultPriceFeed).getLatestPrimaryPrice(token);

        // Get the fast price (uses reference price internally)
        // FastPriceFeed.getPrice returns the fast price or applies spread based on conditions
        // We call with _maximise = false to get conservative price
        return ISecondaryPriceFeed(fastPriceFeed).getPrice(token, refPrice, false);
    }

    /// @notice Construct claim for assertTruth
    /// @dev The claim is a human-readable statement that DVM voters evaluate
    function _constructClaim(
        address token,
        uint256 disputedPrice,
        uint256 claimedPrice,
        uint256 timestamp
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "Price dispute for perps oracle. Token: ",
            _addressToHexString(token),
            ". The oracle reported price ",
            _uint256ToString(disputedPrice),
            " at timestamp ",
            _uint256ToString(timestamp),
            " is INCORRECT. The correct price should be ",
            _uint256ToString(claimedPrice),
            ". Vote TRUE if the claimed price is correct, FALSE if the original oracle price was correct."
        );
    }

    /// @notice Assert truth via Optimistic Oracle
    /// @param disputeId Internal dispute identifier
    /// @param claim The truth claim to assert
    /// @param bond The bond amount for the assertion
    /// @return assertionId The assertion identifier
    function _assertTruth(
        bytes32 disputeId,
        bytes memory claim,
        uint256 bond
    ) internal returns (bytes32 assertionId) {
        PriceDispute storage dispute = disputes[disputeId];

        // Approve bond token for Oracle         IERC20(bondToken).forceApprove(address(oracle), bond);

        // Use default identifier from V3 if available, otherwise use our constant
        bytes32 identifier = oracle.defaultIdentifier();
        if (identifier == bytes32(0)) {
            identifier = PRICE_IDENTIFIER;
        }

        // Assert truth via V3 API
        // - asserter: this contract (receives bond back on success)
        // - callbackRecipient: this contract (receives callbacks)
        // - escalationManager: address(0) - use default DVM escalation
        // - liveness: custom liveness period
        // - currency: bond token
        // - bond: assertion bond
        // - identifier: price identifier for DVM
        // - domainId: group assertions by perps disputes
        assertionId = oracle.assertTruth(
            claim,
            address(this),      // asserter
            address(this),      // callbackRecipient
            address(0),         // escalationManager (use default)
            _livenessSeconds,   // liveness
            IERC20(bondToken),  // currency
            bond,               // bond
            identifier,         // identifier
            DOMAIN_ID           // domainId
        );
    }

    /// @notice Resolve a dispute based on V3 assertion result
    /// @param disputeId The dispute identifier
    /// @param assertedTruthfully True if the assertion was confirmed (disputer wins)
    function _resolveDisputeV3(bytes32 disputeId, bool assertedTruthfully) internal {
        PriceDispute storage dispute = disputes[disputeId];

        dispute.resolved = true;

        // In V3 pattern:
        // - assertedTruthfully = true means the claim was correct (disputer wins)
        // - assertedTruthfully = false means the claim was incorrect (disputer loses)
        bool disputerWon = assertedTruthfully;
        dispute.disputerWon = disputerWon;

        if (disputerWon) {
            // Disputer was correct - V3 automatically handles bond return to asserter
            // We also return the original bond posted to this contract
            IERC20(bondToken).safeTransfer(dispute.disputer, dispute.bond);

            // Check if circuit breaker should trigger
            uint256 deviation = _calculateDeviation(
                dispute.disputedPrice,
                dispute.claimedPrice
            );

            if (deviation >= circuitBreakerThreshold) {
                isCircuitBreakerActive[dispute.token] = true;

                emit CircuitBreakerTriggered(
                    dispute.token,
                    dispute.disputedPrice,
                    dispute.claimedPrice
                );
            }
        }
        // If disputer lost, bond stays in contract (or could be distributed)

        emit PriceDisputeResolved(
            disputeId,
            dispute.token,
            disputerWon,
            disputerWon ? dispute.claimedPrice : dispute.disputedPrice
        );
    }

    /// @notice Check if two prices match within acceptable tolerance
    function _pricesMatch(uint256 price1, uint256 price2) internal pure returns (bool) {
        if (price1 == price2) return true;

        // Allow 0.01% tolerance for rounding
        uint256 tolerance = price1 / 10000;
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;

        return diff <= tolerance;
    }

    /// @notice Calculate price deviation in basis points
    function _calculateDeviation(
        uint256 price1,
        uint256 price2
    ) internal pure returns (uint256) {
        if (price1 == 0) return BASIS_POINTS_DIVISOR;

        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        return (diff * BASIS_POINTS_DIVISOR) / price1;
    }

    /// @notice Convert address to hex string
    function _addressToHexString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i)) >> 4)];
            str[3 + i * 2] = alphabet[uint8(uint160(addr) >> (8 * (19 - i))) & 0x0f];
        }
        return string(str);
    }

    /// @notice Convert uint256 to string
    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
