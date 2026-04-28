// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "./IYieldStrategy.sol";

/**
 * @title ShariaFilter
 * @notice Shariah compliance filter for Teleport yield strategies
 * @dev Islamic finance (Shariah law) prohibits:
 *      - Riba (interest/usury) — lending/borrowing interest
 *      - Gharar (excessive uncertainty) — some derivatives
 *      - Maysir (gambling) — pure speculation without underlying
 *
 *      PERMITTED (Halal) yield sources:
 *      ✅ Trading fees (DEX, AMM) — service fee for facilitating exchange
 *      ✅ Bridge fees — service fee for cross-chain transfer
 *      ✅ Validator staking rewards — compensation for securing network
 *      ✅ LP provision fees — compensation for providing liquidity
 *      ✅ Protocol revenue sharing (xLUX) — profit sharing (Mudarabah)
 *      ✅ Babylon BTC staking — fee-based security provision
 *      ✅ Options writing premiums — risk transfer (Takaful-like)
 *
 *      PROHIBITED (Haram) yield sources:
 *      ❌ Lending interest (Aave, Compound, Morpho) — Riba
 *      ❌ MakerDAO DSR — interest on savings
 *      ❌ Interest-bearing stablecoins (sDAI, USDY) — Riba
 *      ❌ Leveraged yield farming with borrowed funds — Riba
 *
 *      CONDITIONAL (requires Shariah board review):
 *      ⚠️ Liquid staking (Lido, Rocket Pool) — depends on structure
 *      ⚠️ Restaking (EigenLayer, Symbiotic) — depends on what's secured
 *      ⚠️ Perpetual funding rates — depends on structure
 *
 *      Usage:
 *      - Set `shariahCompliant = true` on the YieldBridgeConfig
 *      - ShariaFilter automatically excludes non-compliant strategies
 *      - Muslim users opt into "Halal Mode" in bridge UI
 *      - All yield accounting separated: halal yield vs mixed yield
 *
 *      Governance:
 *      - Shariah Advisory Board (SAB) reviews each strategy
 *      - SAB can approve/revoke strategy compliance status
 *      - Transparent on-chain compliance registry
 */

contract ShariaFilter {
    // ================================================================
    //  Compliance classification
    // ================================================================

    enum ComplianceStatus {
        HALAL, // Approved by Shariah board
        HARAM, // Prohibited — interest-based
        UNDER_REVIEW, // Pending Shariah board review
        CONDITIONAL // Halal with specific conditions
    }

    struct StrategyCompliance {
        ComplianceStatus status;
        string rationale; // Why this classification
        address reviewer; // Shariah board member who reviewed
        uint256 reviewedAt; // Timestamp of last review
        string conditions; // For CONDITIONAL: what conditions apply
    }

    // ================================================================
    //  State
    // ================================================================

    address public shariahBoard; // Shariah Advisory Board multisig

    /// strategy address -> compliance status
    mapping(address => StrategyCompliance) public compliance;

    /// Protocol-level classification (for strategies not individually reviewed)
    mapping(string => ComplianceStatus) public protocolCompliance;

    // ================================================================
    //  Events
    // ================================================================

    event ComplianceUpdated(address indexed strategy, ComplianceStatus status, string rationale);
    event ProtocolClassified(string protocol, ComplianceStatus status, string rationale);
    event ShariahBoardUpdated(address oldBoard, address newBoard);

    // ================================================================
    //  Constructor
    // ================================================================

    constructor(address _shariahBoard) {
        shariahBoard = _shariahBoard;

        // Default protocol classifications (can be overridden by Shariah board)
        // HALAL: Fee-based protocols
        protocolCompliance["dex_fees"] = ComplianceStatus.HALAL;
        protocolCompliance["bridge_fees"] = ComplianceStatus.HALAL;
        protocolCompliance["validator_staking"] = ComplianceStatus.HALAL;
        protocolCompliance["lp_provision"] = ComplianceStatus.HALAL;
        protocolCompliance["babylon_staking"] = ComplianceStatus.HALAL;
        protocolCompliance["core_staking"] = ComplianceStatus.HALAL;
        protocolCompliance["perps_fees"] = ComplianceStatus.HALAL; // Trading fees, not interest

        // HARAM: Interest-based protocols
        protocolCompliance["aave"] = ComplianceStatus.HARAM;
        protocolCompliance["compound"] = ComplianceStatus.HARAM;
        protocolCompliance["morpho_lending"] = ComplianceStatus.HARAM;
        protocolCompliance["makerdao_dsr"] = ComplianceStatus.HARAM;
        protocolCompliance["spark_lending"] = ComplianceStatus.HARAM;
        protocolCompliance["euler"] = ComplianceStatus.HARAM;
        protocolCompliance["fluid_lending"] = ComplianceStatus.HARAM;
        protocolCompliance["maple"] = ComplianceStatus.HARAM;

        // CONDITIONAL: Requires specific structure review
        protocolCompliance["lido"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["rocket_pool"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["eigenlayer"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["symbiotic"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["karak"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["pendle"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["ethena"] = ComplianceStatus.HARAM; // Delta-neutral with lending
        protocolCompliance["frax"] = ComplianceStatus.HARAM; // Interest-based
        protocolCompliance["yearn"] = ComplianceStatus.CONDITIONAL; // Depends on vault strategy
        protocolCompliance["convex"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["curve"] = ComplianceStatus.HALAL; // LP fees only

        // Bitcoin-native
        protocolCompliance["lombard"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["solv"] = ComplianceStatus.CONDITIONAL;
        protocolCompliance["bouncebit"] = ComplianceStatus.CONDITIONAL;
    }

    // ================================================================
    //  Core functions
    // ================================================================

    /// @notice Check if a strategy is Shariah compliant
    function isCompliant(address strategy) external view returns (bool) {
        ComplianceStatus status = compliance[strategy].status;
        return status == ComplianceStatus.HALAL;
    }

    /// @notice Check if a protocol category is Shariah compliant
    function isProtocolCompliant(string calldata protocol) external view returns (bool) {
        return protocolCompliance[protocol] == ComplianceStatus.HALAL;
    }

    /// @notice Filter an array of strategies to only compliant ones
    function filterCompliant(address[] calldata strategies) external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (compliance[strategies[i]].status == ComplianceStatus.HALAL) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (compliance[strategies[i]].status == ComplianceStatus.HALAL) {
                result[idx++] = strategies[i];
            }
        }
        return result;
    }

    // ================================================================
    //  Shariah Board functions
    // ================================================================

    /// @notice Classify a specific strategy (Shariah board only)
    function classifyStrategy(
        address strategy,
        ComplianceStatus status,
        string calldata rationale,
        string calldata conditions
    ) external {
        require(msg.sender == shariahBoard, "Only Shariah board");
        compliance[strategy] = StrategyCompliance({
            status: status,
            rationale: rationale,
            reviewer: msg.sender,
            reviewedAt: block.timestamp,
            conditions: conditions
        });
        emit ComplianceUpdated(strategy, status, rationale);
    }

    /// @notice Classify a protocol category (Shariah board only)
    function classifyProtocol(string calldata protocol, ComplianceStatus status, string calldata rationale) external {
        require(msg.sender == shariahBoard, "Only Shariah board");
        protocolCompliance[protocol] = status;
        emit ProtocolClassified(protocol, status, rationale);
    }

    /// @notice Update Shariah board address (only current SAB can transfer authority)
    function setShariahBoard(address newBoard) external {
        require(msg.sender == shariahBoard, "Only Shariah board");
        require(newBoard != address(0), "Zero address");
        emit ShariahBoardUpdated(shariahBoard, newBoard);
        shariahBoard = newBoard;
    }

    // ================================================================
    //  View helpers
    // ================================================================

    /// @notice Get full compliance info for a strategy
    function getCompliance(address strategy) external view returns (StrategyCompliance memory) {
        return compliance[strategy];
    }

    /// @notice Get compliance status string for display
    function getStatusString(address strategy) external view returns (string memory) {
        ComplianceStatus status = compliance[strategy].status;
        if (status == ComplianceStatus.HALAL) return "Halal";
        if (status == ComplianceStatus.HARAM) return "Haram";
        if (status == ComplianceStatus.UNDER_REVIEW) return "Under Review";
        if (status == ComplianceStatus.CONDITIONAL) return "Conditional";
        return "Unclassified";
    }
}
