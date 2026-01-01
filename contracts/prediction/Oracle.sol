// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

import {IFinder} from "../oracle/registry/interfaces/IFinder.sol";
import {IStore} from "../oracle/registry/interfaces/IStore.sol";
import {IIdentifierWhitelist} from "../oracle/registry/interfaces/IIdentifierWhitelist.sol";
import {
    IOracle,
    IOracleCallbacks,
    IEscalationManager,
    IOracleAncillary,
    IAddressWhitelist
} from "./interfaces/IOracle.sol";

/**
 * @title AncillaryData
 * @notice Library for encoding ancillary data for DVM price requests.
 */
library AncillaryData {
    /**
     * @notice Converts bytes32 to UTF-8 hex string (lowercase, no 0x prefix).
     */
    function toUtf8Bytes(bytes32 bytesIn) internal pure returns (bytes memory) {
        return abi.encodePacked(_toUtf8Bytes32Bottom(bytesIn >> 128), _toUtf8Bytes32Bottom(bytesIn));
    }

    /**
     * @notice Converts address to UTF-8 hex string (lowercase, no 0x prefix).
     */
    function toUtf8BytesAddress(address x) internal pure returns (bytes memory) {
        return abi.encodePacked(
            _toUtf8Bytes32Bottom(bytes32(bytes20(x)) >> 128),
            bytes8(_toUtf8Bytes32Bottom(bytes20(x)))
        );
    }

    /**
     * @notice Appends key:value pair where value is bytes32.
     */
    function appendKeyValueBytes32(
        bytes memory currentAncillaryData,
        bytes memory key,
        bytes32 value
    ) internal pure returns (bytes memory) {
        bytes memory prefix = _constructPrefix(currentAncillaryData, key);
        return abi.encodePacked(currentAncillaryData, prefix, toUtf8Bytes(value));
    }

    /**
     * @notice Appends key:value pair where value is address.
     */
    function appendKeyValueAddress(
        bytes memory currentAncillaryData,
        bytes memory key,
        address value
    ) internal pure returns (bytes memory) {
        bytes memory prefix = _constructPrefix(currentAncillaryData, key);
        return abi.encodePacked(currentAncillaryData, prefix, toUtf8BytesAddress(value));
    }

    function _constructPrefix(bytes memory currentAncillaryData, bytes memory key) private pure returns (bytes memory) {
        if (currentAncillaryData.length > 0) {
            return abi.encodePacked(",", key, ":");
        } else {
            return abi.encodePacked(key, ":");
        }
    }

    function _toUtf8Bytes32Bottom(bytes32 bytesIn) private pure returns (bytes32) {
        unchecked {
            uint256 x = uint256(bytesIn);

            // Nibble interleave
            x = x & 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
            x = (x | (x * 2 ** 64)) & 0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;
            x = (x | (x * 2 ** 32)) & 0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff;
            x = (x | (x * 2 ** 16)) & 0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff;
            x = (x | (x * 2 ** 8)) & 0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff;
            x = (x | (x * 2 ** 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;

            // Hex encode
            uint256 h = (x & 0x0808080808080808080808080808080808080808080808080808080808080808) / 8;
            uint256 i = (x & 0x0404040404040404040404040404040404040404040404040404040404040404) / 4;
            uint256 j = (x & 0x0202020202020202020202020202020202020202020202020202020202020202) / 2;
            x = x + (h & (i | j)) * 0x27 + 0x3030303030303030303030303030303030303030303030303030303030303030;

            return bytes32(x);
        }
    }
}

/**
 * @title OracleInterfaces
 * @notice Common interface names used throughout the DVM by registration in the Finder.
 */
library OracleInterfaces {
    bytes32 public constant Oracle = "Oracle";
    bytes32 public constant IdentifierWhitelist = "IdentifierWhitelist";
    bytes32 public constant Store = "Store";
    bytes32 public constant CollateralWhitelist = "CollateralWhitelist";
}

/**
 * @title OptimisticOracle
 * @notice The Optimistic Oracle is used to assert truths about the world which are verified using an optimistic escalation game.
 * @dev Core idea: an asserter makes a statement about a truth, calling "assertTruth". If this statement is not
 * challenged, it is taken as the state of the world. If challenged, it is arbitrated using the DVM, or if
 * configured, an escalation manager. Escalation managers enable integrations to define their own security properties
 * and tradeoffs, enabling the notion of "sovereign security".
 */
contract Oracle is IOracle, ReentrancyGuard, Ownable, Multicall {
    using SafeERC20 for IERC20;

    /// @notice Finder used to discover other ecosystem contracts.
    IFinder public immutable finder;

    /// @notice Cached oracle address.
    address public cachedOracle;

    /// @notice Cached currency whitelist info.
    mapping(address => WhitelistedCurrency) public cachedCurrencies;

    /// @notice Cached identifier whitelist status.
    mapping(bytes32 => bool) public cachedIdentifiers;

    /// @notice All assertions made by the Optimistic Oracle.
    mapping(bytes32 => Assertion) public assertions;

    /// @notice Percentage of the bond that is paid to the Store if the assertion is disputed (18 decimals).
    uint256 public burnedBondPercentage;

    /// @notice Default identifier for assertions.
    bytes32 public constant defaultIdentifier = "ASSERT_TRUTH";

    /// @notice Numerical representation of true (1e18).
    int256 public constant numericalTrue = 1e18;

    /// @notice Default currency for assertions.
    IERC20 public defaultCurrency;

    /// @notice Default liveness period for assertions.
    uint64 public defaultLiveness;

    /**
     * @notice Construct the OptimisticOracle contract.
     * @param _finder keeps track of all contracts within the system based on their interfaceName.
     * @param _defaultCurrency the default currency to bond asserters in assertTruthWithDefaults.
     * @param _defaultLiveness the default liveness for assertions in assertTruthWithDefaults.
     * @param _initialOwner the initial owner of this contract.
     */
    constructor(
        IFinder _finder,
        IERC20 _defaultCurrency,
        uint64 _defaultLiveness,
        address _initialOwner
    ) Ownable(_initialOwner) {
        finder = _finder;
        setAdminProperties(_defaultCurrency, _defaultLiveness, 0.5e18);
    }

    /**
     * @notice Sets the default currency, liveness, and burned bond percentage.
     * @dev Only callable by the contract owner.
     * @param _defaultCurrency the default currency to bond asserters in assertTruthWithDefaults.
     * @param _defaultLiveness the default liveness for assertions in assertTruthWithDefaults.
     * @param _burnedBondPercentage the percentage of the bond that is sent as fee to Store on disputes.
     */
    function setAdminProperties(
        IERC20 _defaultCurrency,
        uint64 _defaultLiveness,
        uint256 _burnedBondPercentage
    ) public onlyOwner {
        require(_burnedBondPercentage <= 1e18, "Burned bond percentage > 100");
        require(_burnedBondPercentage > 0, "Burned bond percentage is 0");
        burnedBondPercentage = _burnedBondPercentage;
        defaultCurrency = _defaultCurrency;
        defaultLiveness = _defaultLiveness;
        syncParams(defaultIdentifier, address(_defaultCurrency));

        emit AdminPropertiesSet(_defaultCurrency, _defaultLiveness, _burnedBondPercentage);
    }

    /**
     * @notice Asserts a truth about the world, using the default currency and liveness.
     * @dev The caller must approve this contract to spend at least the result of getMinimumBond(defaultCurrency).
     * @param claim the truth claim being asserted.
     * @param asserter account that receives bonds back at settlement.
     * @return assertionId unique identifier for this assertion.
     */
    function assertTruthWithDefaults(bytes calldata claim, address asserter) external returns (bytes32) {
        return assertTruth(
            claim,
            asserter,
            address(0), // callbackRecipient
            address(0), // escalationManager
            defaultLiveness,
            defaultCurrency,
            getMinimumBond(address(defaultCurrency)),
            defaultIdentifier,
            bytes32(0)
        );
    }

    /**
     * @notice Asserts a truth about the world, using a fully custom configuration.
     * @dev The caller must approve this contract to spend at least bond amount of currency.
     * @param claim the truth claim being asserted.
     * @param asserter account that receives bonds back at settlement.
     * @param callbackRecipient if configured, receives callbacks at resolution or dispute.
     * @param escalationManager if configured, controls escalation properties of the assertion.
     * @param liveness time to wait before the assertion can be resolved.
     * @param currency bond currency pulled from the caller and held in escrow.
     * @param bond amount of currency to pull from the caller and hold in escrow.
     * @param identifier DVM identifier to use for price requests in the event of a dispute.
     * @param domainId optional domain for grouping assertions.
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
    ) public nonReentrant returns (bytes32 assertionId) {
        uint64 time = uint64(getCurrentTime());
        assertionId = _getId(claim, bond, time, liveness, currency, callbackRecipient, escalationManager, identifier);

        require(asserter != address(0), "Asserter cant be 0");
        require(assertions[assertionId].asserter == address(0), "Assertion already exists");
        require(_validateAndCacheIdentifier(identifier), "Unsupported identifier");
        require(_validateAndCacheCurrency(address(currency)), "Unsupported currency");
        require(bond >= getMinimumBond(address(currency)), "Bond amount too low");

        assertions[assertionId] = Assertion({
            escalationManagerSettings: EscalationManagerSettings({
                arbitrateViaEscalationManager: false,
                discardOracle: false,
                validateDisputers: false,
                escalationManager: escalationManager,
                assertingCaller: msg.sender
            }),
            asserter: asserter,
            disputer: address(0),
            callbackRecipient: callbackRecipient,
            currency: currency,
            domainId: domainId,
            identifier: identifier,
            bond: bond,
            settled: false,
            settlementResolution: false,
            assertionTime: time,
            expirationTime: time + liveness
        });

        {
            IEscalationManager.AssertionPolicy memory assertionPolicy = _getAssertionPolicy(assertionId);
            require(!assertionPolicy.blockAssertion, "Assertion not allowed");
            EscalationManagerSettings storage emSettings = assertions[assertionId].escalationManagerSettings;
            (emSettings.arbitrateViaEscalationManager, emSettings.discardOracle, emSettings.validateDisputers) = (
                assertionPolicy.arbitrateViaEscalationManager,
                assertionPolicy.discardOracle,
                assertionPolicy.validateDisputers
            );
        }

        currency.safeTransferFrom(msg.sender, address(this), bond);

        emit AssertionMade(
            assertionId,
            domainId,
            claim,
            asserter,
            callbackRecipient,
            escalationManager,
            msg.sender,
            time + liveness,
            currency,
            bond,
            identifier
        );
    }

    /**
     * @notice Disputes an assertion.
     * @dev The caller must approve this contract to spend at least bond amount of currency.
     * @param assertionId unique identifier for the assertion to dispute.
     * @param disputer receives bonds back at settlement.
     */
    function disputeAssertion(bytes32 assertionId, address disputer) external nonReentrant {
        require(disputer != address(0), "Disputer can't be 0");
        Assertion storage assertion = assertions[assertionId];
        require(assertion.asserter != address(0), "Assertion does not exist");
        require(assertion.disputer == address(0), "Assertion already disputed");
        require(assertion.expirationTime > getCurrentTime(), "Assertion is expired");
        require(_isDisputeAllowed(assertionId), "Dispute not allowed");

        assertion.disputer = disputer;

        assertion.currency.safeTransferFrom(msg.sender, address(this), assertion.bond);

        _oracleRequestPrice(assertionId, assertion.identifier, assertion.assertionTime);

        _callbackOnAssertionDispute(assertionId);

        // Send resolve callback if dispute resolution is discarded
        if (assertion.escalationManagerSettings.discardOracle) {
            _callbackOnAssertionResolve(assertionId, false);
        }

        emit AssertionDisputed(assertionId, msg.sender, disputer);
    }

    /**
     * @notice Resolves an assertion.
     * @param assertionId unique identifier for the assertion to resolve.
     */
    function settleAssertion(bytes32 assertionId) public nonReentrant {
        Assertion storage assertion = assertions[assertionId];
        require(assertion.asserter != address(0), "Assertion does not exist");
        require(!assertion.settled, "Assertion already settled");
        assertion.settled = true;

        if (assertion.disputer == address(0)) {
            // No dispute, settle with the asserter
            require(assertion.expirationTime <= getCurrentTime(), "Assertion not expired");
            assertion.settlementResolution = true;
            assertion.currency.safeTransfer(assertion.asserter, assertion.bond);
            _callbackOnAssertionResolve(assertionId, true);

            emit AssertionSettled(assertionId, assertion.asserter, false, true, msg.sender);
        } else {
            // Dispute exists, settle based on oracle result
            int256 resolvedPrice = _oracleGetPrice(assertionId, assertion.identifier, assertion.assertionTime);

            // If set to discard settlement resolution then false, else use oracle value
            if (assertion.escalationManagerSettings.discardOracle) {
                assertion.settlementResolution = false;
            } else {
                assertion.settlementResolution = resolvedPrice == numericalTrue;
            }

            address bondRecipient = resolvedPrice == numericalTrue ? assertion.asserter : assertion.disputer;

            // Calculate oracle fee and remaining bonds
            uint256 oracleFee = (burnedBondPercentage * assertion.bond) / 1e18;
            uint256 bondRecipientAmount = assertion.bond * 2 - oracleFee;

            // Pay out oracle fee and remaining bonds
            assertion.currency.safeTransfer(address(_getStore()), oracleFee);
            assertion.currency.safeTransfer(bondRecipient, bondRecipientAmount);

            if (!assertion.escalationManagerSettings.discardOracle) {
                _callbackOnAssertionResolve(assertionId, assertion.settlementResolution);
            }

            emit AssertionSettled(assertionId, bondRecipient, true, assertion.settlementResolution, msg.sender);
        }
    }

    /**
     * @notice Settles an assertion and returns the resolution.
     * @param assertionId unique identifier for the assertion.
     * @return resolution of the assertion.
     */
    function settleAndGetAssertionResult(bytes32 assertionId) external returns (bool) {
        if (!assertions[assertionId].settled) {
            settleAssertion(assertionId);
        }
        return getAssertionResult(assertionId);
    }

    /**
     * @notice Syncs cached parameters from the Finder.
     * @param identifier identifier to fetch information for.
     * @param currency currency to fetch information for.
     */
    function syncParams(bytes32 identifier, address currency) public {
        cachedOracle = finder.getImplementationAddress(OracleInterfaces.Oracle);
        cachedIdentifiers[identifier] = _getIdentifierWhitelist().isIdentifierSupported(identifier);
        cachedCurrencies[currency].isWhitelisted = _getCollateralWhitelist().isOnWhitelist(currency);
        cachedCurrencies[currency].finalFee = _getStore().computeFinalFee(currency);
    }

    /**
     * @notice Fetches information about a specific assertion.
     * @param assertionId unique identifier for the assertion.
     * @return assertion information about the assertion.
     */
    function getAssertion(bytes32 assertionId) external view returns (Assertion memory) {
        return assertions[assertionId];
    }

    /**
     * @notice Fetches the resolution of a specific assertion.
     * @param assertionId unique identifier for the assertion.
     * @return resolution of the assertion.
     */
    function getAssertionResult(bytes32 assertionId) public view returns (bool) {
        Assertion memory assertion = assertions[assertionId];
        // Return early if not using answer from resolved dispute
        if (assertion.disputer != address(0) && assertion.escalationManagerSettings.discardOracle) {
            return false;
        }
        require(assertion.settled, "Assertion not settled");
        return assertion.settlementResolution;
    }

    /**
     * @notice Returns the current block timestamp.
     * @dev Can be overridden to control contract time.
     * @return current block timestamp.
     */
    function getCurrentTime() public view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Appends information onto an assertionId to construct ancillary data.
     * @param assertionId unique identifier for the assertion.
     * @return ancillaryData stamped assertion information.
     */
    function stampAssertion(bytes32 assertionId) public view returns (bytes memory) {
        return _stampAssertion(assertionId);
    }

    /**
     * @notice Returns the minimum bond amount required to make an assertion.
     * @param currency currency to calculate the minimum bond for.
     * @return minimum bond amount.
     */
    function getMinimumBond(address currency) public view returns (uint256) {
        uint256 finalFee = cachedCurrencies[currency].finalFee;
        return (finalFee * 1e18) / burnedBondPercentage;
    }

    // ============ Internal Functions ============

    function _getId(
        bytes memory claim,
        uint256 bond,
        uint256 time,
        uint64 liveness,
        IERC20 currency,
        address callbackRecipient,
        address escalationManager,
        bytes32 identifier
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(claim, bond, time, liveness, currency, callbackRecipient, escalationManager, identifier, msg.sender)
        );
    }

    function _stampAssertion(bytes32 assertionId) internal view returns (bytes memory) {
        return AncillaryData.appendKeyValueAddress(
            AncillaryData.appendKeyValueBytes32("", "assertionId", assertionId),
            "ooAsserter",
            assertions[assertionId].asserter
        );
    }

    function _getCollateralWhitelist() internal view returns (IAddressWhitelist) {
        return IAddressWhitelist(finder.getImplementationAddress(OracleInterfaces.CollateralWhitelist));
    }

    function _getIdentifierWhitelist() internal view returns (IIdentifierWhitelist) {
        return IIdentifierWhitelist(finder.getImplementationAddress(OracleInterfaces.IdentifierWhitelist));
    }

    function _getStore() internal view returns (IStore) {
        return IStore(finder.getImplementationAddress(OracleInterfaces.Store));
    }

    function _getOracle(bytes32 assertionId) internal view returns (IOracleAncillary) {
        if (assertions[assertionId].escalationManagerSettings.arbitrateViaEscalationManager) {
            return IOracleAncillary(_getEscalationManager(assertionId));
        }
        return IOracleAncillary(cachedOracle);
    }

    function _oracleRequestPrice(bytes32 assertionId, bytes32 identifier, uint256 time) internal {
        _getOracle(assertionId).requestPrice(identifier, time, _stampAssertion(assertionId));
    }

    function _oracleGetPrice(bytes32 assertionId, bytes32 identifier, uint256 time) internal view returns (int256) {
        return _getOracle(assertionId).getPrice(identifier, time, _stampAssertion(assertionId));
    }

    function _getEscalationManager(bytes32 assertionId) internal view returns (address) {
        return assertions[assertionId].escalationManagerSettings.escalationManager;
    }

    function _getAssertionPolicy(bytes32 assertionId)
        internal
        view
        returns (IEscalationManager.AssertionPolicy memory)
    {
        address em = _getEscalationManager(assertionId);
        if (em == address(0)) {
            return IEscalationManager.AssertionPolicy(false, false, false, false);
        }
        return IEscalationManager(em).getAssertionPolicy(assertionId);
    }

    function _isDisputeAllowed(bytes32 assertionId) internal view returns (bool) {
        if (!assertions[assertionId].escalationManagerSettings.validateDisputers) {
            return true;
        }
        address em = assertions[assertionId].escalationManagerSettings.escalationManager;
        if (em == address(0)) {
            return true;
        }
        return IEscalationManager(em).isDisputeAllowed(assertionId, msg.sender);
    }

    function _validateAndCacheIdentifier(bytes32 identifier) internal returns (bool) {
        if (cachedIdentifiers[identifier]) {
            return true;
        }
        cachedIdentifiers[identifier] = _getIdentifierWhitelist().isIdentifierSupported(identifier);
        return cachedIdentifiers[identifier];
    }

    function _validateAndCacheCurrency(address currency) internal returns (bool) {
        if (cachedCurrencies[currency].isWhitelisted) {
            return true;
        }
        cachedCurrencies[currency].isWhitelisted = _getCollateralWhitelist().isOnWhitelist(currency);
        cachedCurrencies[currency].finalFee = _getStore().computeFinalFee(currency);
        return cachedCurrencies[currency].isWhitelisted;
    }

    function _callbackOnAssertionResolve(bytes32 assertionId, bool assertedTruthfully) internal {
        address cr = assertions[assertionId].callbackRecipient;
        address em = _getEscalationManager(assertionId);
        if (cr != address(0)) {
            IOracleCallbacks(cr).assertionResolvedCallback(assertionId, assertedTruthfully);
        }
        if (em != address(0)) {
            IEscalationManager(em).assertionResolvedCallback(assertionId, assertedTruthfully);
        }
    }

    function _callbackOnAssertionDispute(bytes32 assertionId) internal {
        address cr = assertions[assertionId].callbackRecipient;
        address em = _getEscalationManager(assertionId);
        if (cr != address(0)) {
            IOracleCallbacks(cr).assertionDisputedCallback(assertionId);
        }
        if (em != address(0)) {
            IEscalationManager(em).assertionDisputedCallback(assertionId);
        }
    }
}
