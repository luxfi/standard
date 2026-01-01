// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IOracle
 * @notice Interface for the Oracle - the core assertion/dispute engine for prediction markets.
 * @dev Callers use this to assert truths about the world which are verified using an optimistic escalation game.
 */
interface IOracle {
    // Struct grouping together the settings related to the escalation manager stored in the assertion.
    struct EscalationManagerSettings {
        bool arbitrateViaEscalationManager; // False if the DVM is used as an oracle (EscalationManager on True).
        bool discardOracle; // False if Oracle result is used for resolving assertion after dispute.
        bool validateDisputers; // True if the EM isDisputeAllowed should be checked on disputes.
        address assertingCaller; // Stores msg.sender when assertion was made.
        address escalationManager; // Address of the escalation manager (zero address if not configured).
    }

    // Struct for storing properties and lifecycle of an assertion.
    struct Assertion {
        EscalationManagerSettings escalationManagerSettings; // Settings related to the escalation manager.
        address asserter; // Address of the asserter.
        uint64 assertionTime; // Time of the assertion.
        bool settled; // True if the request is settled.
        IERC20 currency; // ERC20 token used to pay rewards and fees.
        uint64 expirationTime; // Unix timestamp marking threshold when the assertion can no longer be disputed.
        bool settlementResolution; // Resolution of the assertion (false till resolved).
        bytes32 domainId; // Optional domain that can be used to relate the assertion to others in the escalationManager.
        bytes32 identifier; // DVM identifier to use for price requests in the event of a dispute.
        uint256 bond; // Amount of currency that the asserter has bonded.
        address callbackRecipient; // Address that receives the callback.
        address disputer; // Address of the disputer.
    }

    // Struct for storing cached currency whitelist.
    struct WhitelistedCurrency {
        bool isWhitelisted; // True if the currency is whitelisted.
        uint256 finalFee; // Final fee of the currency.
    }

    /**
     * @notice Asserts a truth about the world, using the default currency and liveness.
     * @dev The caller must approve this contract to spend at least the result of getMinimumBond(defaultCurrency).
     * @param claim the truth claim being asserted.
     * @param asserter account that receives bonds back at settlement.
     * @return assertionId unique identifier for this assertion.
     */
    function assertTruthWithDefaults(bytes memory claim, address asserter) external returns (bytes32);

    /**
     * @notice Asserts a truth about the world, using a fully custom configuration.
     * @dev The caller must approve this contract to spend at least bond amount of currency.
     * @param claim the truth claim being asserted.
     * @param asserter account that receives bonds back at settlement.
     * @param callbackRecipient if configured, receives assertionResolvedCallback and assertionDisputedCallback.
     * @param escalationManager if configured, controls escalation properties of the assertion.
     * @param liveness time to wait before the assertion can be resolved.
     * @param currency bond currency pulled from the caller and held in escrow.
     * @param bond amount of currency to pull from the caller and hold in escrow.
     * @param identifier DVM identifier to use for price requests in the event of a dispute.
     * @param domainId optional domain for grouping assertions in the escalationManager.
     * @return assertionId unique identifier for this assertion.
     */
    function assertTruth(
        bytes memory claim,
        address asserter,
        address callbackRecipient,
        address escalationManager,
        uint64 liveness,
        IERC20 currency,
        uint256 bond,
        bytes32 identifier,
        bytes32 domainId
    ) external returns (bytes32);

    /**
     * @notice Disputes an assertion.
     * @dev The caller must approve this contract to spend at least bond amount of currency.
     * @param assertionId unique identifier for the assertion to dispute.
     * @param disputer receives bonds back at settlement.
     */
    function disputeAssertion(bytes32 assertionId, address disputer) external;

    /**
     * @notice Resolves an assertion.
     * @param assertionId unique identifier for the assertion to resolve.
     */
    function settleAssertion(bytes32 assertionId) external;

    /**
     * @notice Settles an assertion and returns the resolution.
     * @param assertionId unique identifier for the assertion to resolve.
     * @return resolution of the assertion.
     */
    function settleAndGetAssertionResult(bytes32 assertionId) external returns (bool);

    /**
     * @notice Fetches information about a specific assertion.
     * @param assertionId unique identifier for the assertion.
     * @return assertion information about the assertion.
     */
    function getAssertion(bytes32 assertionId) external view returns (Assertion memory);

    /**
     * @notice Fetches the resolution of a specific assertion.
     * @param assertionId unique identifier for the assertion.
     * @return resolution of the assertion.
     */
    function getAssertionResult(bytes32 assertionId) external view returns (bool);

    /**
     * @notice Returns the minimum bond amount required to make an assertion.
     * @param currency currency to calculate the minimum bond for.
     * @return minimum bond amount.
     */
    function getMinimumBond(address currency) external view returns (uint256);

    /**
     * @notice Returns the default identifier used by the Oracle.
     * @return The default identifier.
     */
    function defaultIdentifier() external view returns (bytes32);

    /**
     * @notice Syncs cached parameters from the Finder.
     * @param identifier identifier to fetch information for.
     * @param currency currency to fetch information for.
     */
    function syncParams(bytes32 identifier, address currency) external;

    /**
     * @notice Appends information onto an assertionId to construct ancillary data.
     * @param assertionId unique identifier for the assertion.
     * @return ancillaryData stamped assertion information.
     */
    function stampAssertion(bytes32 assertionId) external view returns (bytes memory);

    // Events
    event AssertionMade(
        bytes32 indexed assertionId,
        bytes32 domainId,
        bytes claim,
        address indexed asserter,
        address callbackRecipient,
        address escalationManager,
        address caller,
        uint64 expirationTime,
        IERC20 currency,
        uint256 bond,
        bytes32 indexed identifier
    );

    event AssertionDisputed(bytes32 indexed assertionId, address indexed caller, address indexed disputer);

    event AssertionSettled(
        bytes32 indexed assertionId,
        address indexed bondRecipient,
        bool disputed,
        bool settlementResolution,
        address settleCaller
    );

    event AdminPropertiesSet(IERC20 defaultCurrency, uint64 defaultLiveness, uint256 burnedBondPercentage);
}

/**
 * @title IOracleCallbacks
 * @notice Callback interface for contracts receiving notifications from Oracle.
 */
interface IOracleCallbacks {
    /**
     * @notice Callback when an assertion is resolved.
     * @param assertionId The identifier of the assertion that was resolved.
     * @param assertedTruthfully Whether the assertion was resolved as truthful.
     */
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external;

    /**
     * @notice Callback when an assertion is disputed.
     * @param assertionId The identifier of the assertion that was disputed.
     */
    function assertionDisputedCallback(bytes32 assertionId) external;
}

/**
 * @title IEscalationManager
 * @notice Interface for contracts that manage the escalation policy for assertions.
 */
interface IEscalationManager is IOracleCallbacks {
    // Assertion policy parameters as returned by the escalation manager.
    struct AssertionPolicy {
        bool blockAssertion; // If true, the assertion should be blocked.
        bool arbitrateViaEscalationManager; // If true, the escalation manager will arbitrate the assertion.
        bool discardOracle; // If true, the Oracle should discard the oracle price.
        bool validateDisputers; // If true, the escalation manager will validate the disputers.
    }

    /**
     * @notice Returns the assertion policy for the given assertion.
     * @param assertionId the assertion identifier.
     * @return the assertion policy.
     */
    function getAssertionPolicy(bytes32 assertionId) external view returns (AssertionPolicy memory);

    /**
     * @notice Validates if a dispute should be allowed.
     * @param assertionId the assertionId to validate.
     * @param disputeCaller the caller of the dispute function.
     * @return true if the dispute is allowed.
     */
    function isDisputeAllowed(bytes32 assertionId, address disputeCaller) external view returns (bool);

    /**
     * @notice Gets price from escalation manager (mimics DVM interface).
     * @param identifier price identifier.
     * @param time timestamp of the price.
     * @param ancillaryData ancillary data.
     * @return price from the escalation manager.
     */
    function getPrice(bytes32 identifier, uint256 time, bytes memory ancillaryData) external returns (int256);

    /**
     * @notice Requests price from escalation manager (mimics DVM interface).
     * @param identifier the identifier.
     * @param time the time.
     * @param ancillaryData ancillary data.
     */
    function requestPrice(bytes32 identifier, uint256 time, bytes memory ancillaryData) external;
}

/**
 * @title IOracleAncillary
 * @notice Interface for oracles that support ancillary data.
 */
interface IOracleAncillary {
    /**
     * @notice Requests a price.
     * @param identifier price identifier.
     * @param time timestamp.
     * @param ancillaryData ancillary data.
     */
    function requestPrice(bytes32 identifier, uint256 time, bytes memory ancillaryData) external;

    /**
     * @notice Gets a price.
     * @param identifier price identifier.
     * @param time timestamp.
     * @param ancillaryData ancillary data.
     * @return price.
     */
    function getPrice(bytes32 identifier, uint256 time, bytes memory ancillaryData) external view returns (int256);
}

/**
 * @title IAddressWhitelist
 * @notice Interface for address whitelist (collateral whitelist).
 */
interface IAddressWhitelist {
    /**
     * @notice Checks if an address is on the whitelist.
     * @param addr address to check.
     * @return true if whitelisted.
     */
    function isOnWhitelist(address addr) external view returns (bool);
}
