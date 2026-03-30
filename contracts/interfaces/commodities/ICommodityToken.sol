// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title ICommodityToken
 * @author Lux Industries
 * @notice Interface for tokenised commodity representations (gold, oil, etc.)
 * @dev ERC-20 with oracle-based NAV, compliance hooks, and optional physical redemption
 */
interface ICommodityToken {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Commodity metadata
    struct CommodityInfo {
        string name;
        string symbol;
        string unit; // e.g., "troy oz", "barrel", "bushel"
        uint256 unitSize; // Amount of commodity per token (18 decimals)
        address oracle; // Price oracle for this commodity
        bool physicalRedemptionEnabled;
    }

    /// @notice Redemption request for physical delivery
    struct RedemptionRequest {
        address requester;
        uint256 amount;
        uint256 requestedAt;
        uint256 processedAt;
        bool fulfilled;
        bool cancelled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Thrown when oracle address is invalid
    error InvalidOracle();

    /// @notice Thrown when oracle price is stale
    error StalePrice();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when physical redemption is not enabled
    error RedemptionNotEnabled();

    /// @notice Thrown when redemption request does not exist
    error RedemptionNotFound();

    /// @notice Thrown when redemption is already processed
    error RedemptionAlreadyProcessed();

    /// @notice Thrown when caller is not the custodian
    error NotCustodian();

    /// @notice Thrown when mint would exceed backing proof
    error ExceedsBacking();

    /// @notice Thrown when transfer is restricted by compliance
    error TransferRestricted();

    /// @notice Thrown when unit size is invalid
    error InvalidUnitSize();

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when tokens are minted against new backing
     * @param to Recipient address
     * @param amount Token amount minted
     * @param backingProof Off-chain proof reference (e.g., warehouse receipt hash)
     */
    event Minted(address indexed to, uint256 amount, bytes32 backingProof);

    /**
     * @notice Emitted when tokens are burned (redeemed or withdrawn)
     * @param from Burner address
     * @param amount Token amount burned
     */
    event Burned(address indexed from, uint256 amount);

    /**
     * @notice Emitted when a physical redemption is requested
     * @param requestId Unique request ID
     * @param requester Address requesting redemption
     * @param amount Token amount to redeem
     */
    event RedemptionRequested(uint256 indexed requestId, address indexed requester, uint256 amount);

    /**
     * @notice Emitted when a physical redemption is fulfilled by custodian
     * @param requestId Request ID
     * @param requester Requester address
     * @param amount Token amount redeemed
     */
    event RedemptionFulfilled(uint256 indexed requestId, address indexed requester, uint256 amount);

    /**
     * @notice Emitted when a redemption request is cancelled
     * @param requestId Request ID
     * @param requester Requester address
     */
    event RedemptionCancelled(uint256 indexed requestId, address indexed requester);

    /**
     * @notice Emitted when the custodian is changed
     * @param oldCustodian Previous custodian address
     * @param newCustodian New custodian address
     */
    event CustodianChanged(address indexed oldCustodian, address indexed newCustodian);

    /**
     * @notice Emitted when the oracle is updated
     * @param oldOracle Previous oracle address
     * @param newOracle New oracle address
     */
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /**
     * @notice Emitted when NAV is updated from oracle
     * @param nav New net asset value per token (18 decimals, USD)
     * @param timestamp Oracle price timestamp
     */
    event NAVUpdated(uint256 nav, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════
    // MINTING & BURNING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint tokens against commodity backing
     * @dev Only callable by custodian
     * @param to Recipient address
     * @param amount Token amount to mint
     * @param backingProof Hash of off-chain backing proof (warehouse receipt, etc.)
     */
    function mint(address to, uint256 amount, bytes32 backingProof) external;

    /**
     * @notice Burn tokens (reduce supply)
     * @param amount Token amount to burn
     */
    function burn(uint256 amount) external;

    // ═══════════════════════════════════════════════════════════════════════
    // PHYSICAL REDEMPTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Request physical delivery of commodity
     * @param amount Token amount to redeem
     * @return requestId Unique redemption request ID
     */
    function requestRedemption(uint256 amount) external returns (uint256 requestId);

    /**
     * @notice Fulfill a redemption request (custodian confirms physical delivery)
     * @dev Only callable by custodian
     * @param requestId Redemption request ID
     */
    function fulfillRedemption(uint256 requestId) external;

    /**
     * @notice Cancel a pending redemption request
     * @param requestId Redemption request ID
     */
    function cancelRedemption(uint256 requestId) external;

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get current net asset value per token in USD (18 decimals)
     * @return nav NAV per token
     * @return timestamp Oracle price timestamp
     */
    function getNav() external view returns (uint256 nav, uint256 timestamp);

    /**
     * @notice Get commodity info
     * @return Commodity metadata
     */
    function getCommodityInfo() external view returns (CommodityInfo memory);

    /**
     * @notice Get total value of all tokens in USD (18 decimals)
     * @return Total portfolio value
     */
    function getTotalValue() external view returns (uint256);

    /**
     * @notice Get a redemption request
     * @param requestId Request ID
     * @return Redemption request data
     */
    function getRedemption(uint256 requestId) external view returns (RedemptionRequest memory);

    /**
     * @notice Get custodian address
     * @return Custodian address
     */
    function custodian() external view returns (address);
}
