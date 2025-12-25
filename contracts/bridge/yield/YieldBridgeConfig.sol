// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title YieldBridgeConfig
 * @notice Configuration contract for yield-bearing bridge tokens
 * @dev Allows governance to configure strategies for each bridged asset
 * 
 * Users can select their preferred yield strategy when bridging:
 * - Lido (stETH) - ~4.5% APY, most liquid
 * - Rocket Pool (rETH) - ~4.5% APY, more decentralized
 * - Aave - Variable APY, lending-based
 * - Curve - LP yield, stablecoin focused
 * - Custom strategies via governance
 */

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract YieldBridgeConfig is Ownable {

    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Strategy types
    enum StrategyType {
        NONE,       // No yield (just hold)
        LIDO,       // Lido stETH
        ROCKET,     // Rocket Pool rETH
        AAVE,       // Aave lending
        COMPOUND,   // Compound lending
        CURVE,      // Curve LP
        YEARN,      // Yearn vaults
        CUSTOM      // Custom strategy
    }

    /// @notice Strategy configuration
    struct StrategyConfig {
        StrategyType strategyType;
        address strategyAddress;    // Strategy contract on source chain
        uint256 allocation;         // Allocation in basis points (10000 = 100%)
        uint256 minDeposit;         // Minimum deposit amount
        uint256 maxDeposit;         // Maximum deposit (0 = unlimited)
        bool isActive;              // Whether strategy accepts deposits
        string name;                // Human-readable name
        string description;         // Strategy description
    }

    /// @notice Asset configuration
    struct AssetConfig {
        address yieldToken;         // Yield-bearing token on Lux (yLETH, etc.)
        address bridgeToken;        // Regular bridge token (LETH, etc.)
        uint32 sourceChainId;       // Source chain ID
        address sourceVault;        // Vault on source chain
        bool isConfigured;          // Whether asset is configured
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Asset configurations by underlying symbol
    mapping(bytes32 => AssetConfig) public assetConfigs;

    /// @notice Strategies per asset (assetSymbol => strategyType => config)
    mapping(bytes32 => mapping(StrategyType => StrategyConfig)) public strategies;

    /// @notice Default strategy per asset
    mapping(bytes32 => StrategyType) public defaultStrategy;

    /// @notice Supported assets list
    bytes32[] public supportedAssets;

    /// @notice Protocol fee (basis points)
    uint256 public protocolFee = 1000; // 10%

    /// @notice Fee receiver
    address public feeReceiver;

    /// @notice Basis points
    uint256 public constant BASIS_POINTS = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event AssetConfigured(bytes32 indexed assetSymbol, address yieldToken, address bridgeToken);
    event StrategyConfigured(bytes32 indexed assetSymbol, StrategyType strategyType, address strategyAddress);
    event DefaultStrategySet(bytes32 indexed assetSymbol, StrategyType strategyType);
    event ProtocolFeeUpdated(uint256 newFee);

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _feeReceiver) Ownable(msg.sender) {
        feeReceiver = _feeReceiver;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ASSET CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Configure a new asset for yield bridging
     * @param assetSymbol Asset symbol (e.g., "ETH", "BTC", "USD")
     * @param yieldToken Yield-bearing token address on Lux
     * @param bridgeToken Regular bridge token address on Lux
     * @param sourceChainId Source chain ID
     * @param sourceVault Vault address on source chain
     */
    function configureAsset(
        string calldata assetSymbol,
        address yieldToken,
        address bridgeToken,
        uint32 sourceChainId,
        address sourceVault
    ) external onlyOwner {
        bytes32 symbolHash = keccak256(abi.encodePacked(assetSymbol));
        
        require(!assetConfigs[symbolHash].isConfigured, "YieldBridgeConfig: already configured");

        assetConfigs[symbolHash] = AssetConfig({
            yieldToken: yieldToken,
            bridgeToken: bridgeToken,
            sourceChainId: sourceChainId,
            sourceVault: sourceVault,
            isConfigured: true
        });

        supportedAssets.push(symbolHash);

        emit AssetConfigured(symbolHash, yieldToken, bridgeToken);
    }

    /**
     * @notice Configure a yield strategy for an asset
     * @param assetSymbol Asset symbol
     * @param strategyType Strategy type
     * @param strategyAddress Strategy contract on source chain
     * @param allocation Allocation percentage (basis points)
     * @param name Strategy name
     * @param description Strategy description
     */
    function configureStrategy(
        string calldata assetSymbol,
        StrategyType strategyType,
        address strategyAddress,
        uint256 allocation,
        string calldata name,
        string calldata description
    ) external onlyOwner {
        bytes32 symbolHash = keccak256(abi.encodePacked(assetSymbol));
        require(assetConfigs[symbolHash].isConfigured, "YieldBridgeConfig: asset not configured");
        require(allocation <= BASIS_POINTS, "YieldBridgeConfig: invalid allocation");

        strategies[symbolHash][strategyType] = StrategyConfig({
            strategyType: strategyType,
            strategyAddress: strategyAddress,
            allocation: allocation,
            minDeposit: 0,
            maxDeposit: 0,
            isActive: true,
            name: name,
            description: description
        });

        emit StrategyConfigured(symbolHash, strategyType, strategyAddress);
    }

    /**
     * @notice Set default strategy for an asset
     * @param assetSymbol Asset symbol
     * @param strategyType Default strategy type
     */
    function setDefaultStrategy(
        string calldata assetSymbol,
        StrategyType strategyType
    ) external onlyOwner {
        bytes32 symbolHash = keccak256(abi.encodePacked(assetSymbol));
        require(assetConfigs[symbolHash].isConfigured, "YieldBridgeConfig: asset not configured");
        require(strategies[symbolHash][strategyType].isActive, "YieldBridgeConfig: strategy not active");

        defaultStrategy[symbolHash] = strategyType;

        emit DefaultStrategySet(symbolHash, strategyType);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get asset configuration
     * @param assetSymbol Asset symbol
     * @return config Asset configuration
     */
    function getAssetConfig(string calldata assetSymbol) external view returns (AssetConfig memory) {
        return assetConfigs[keccak256(abi.encodePacked(assetSymbol))];
    }

    /**
     * @notice Get strategy configuration
     * @param assetSymbol Asset symbol
     * @param strategyType Strategy type
     * @return config Strategy configuration
     */
    function getStrategyConfig(
        string calldata assetSymbol,
        StrategyType strategyType
    ) external view returns (StrategyConfig memory) {
        return strategies[keccak256(abi.encodePacked(assetSymbol))][strategyType];
    }

    /**
     * @notice Get all supported assets
     * @return Array of asset symbol hashes
     */
    function getSupportedAssets() external view returns (bytes32[] memory) {
        return supportedAssets;
    }

    /**
     * @notice Check if asset supports a strategy type
     * @param assetSymbol Asset symbol
     * @param strategyType Strategy type
     * @return True if strategy is active for asset
     */
    function supportsStrategy(
        string calldata assetSymbol,
        StrategyType strategyType
    ) external view returns (bool) {
        return strategies[keccak256(abi.encodePacked(assetSymbol))][strategyType].isActive;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setProtocolFee(uint256 _fee) external onlyOwner {
        require(_fee <= 2000, "YieldBridgeConfig: fee too high"); // Max 20%
        protocolFee = _fee;
        emit ProtocolFeeUpdated(_fee);
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
    }

    function setStrategyActive(
        string calldata assetSymbol,
        StrategyType strategyType,
        bool isActive
    ) external onlyOwner {
        bytes32 symbolHash = keccak256(abi.encodePacked(assetSymbol));
        strategies[symbolHash][strategyType].isActive = isActive;
    }

    function updateSourceVault(
        string calldata assetSymbol,
        address sourceVault
    ) external onlyOwner {
        bytes32 symbolHash = keccak256(abi.encodePacked(assetSymbol));
        require(assetConfigs[symbolHash].isConfigured, "YieldBridgeConfig: asset not configured");
        assetConfigs[symbolHash].sourceVault = sourceVault;
    }
}
