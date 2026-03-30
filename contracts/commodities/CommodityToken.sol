// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Pausable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { ICommodityToken } from "../interfaces/commodities/ICommodityToken.sol";
import { IOracle } from "../oracle/IOracle.sol";

/**
 * @title CommodityToken
 * @author Lux Industries
 * @notice Tokenised commodity representation (gold, oil, agricultural, etc.)
 * @dev ERC-20 with oracle-based NAV, custodian-controlled minting, compliance hooks,
 *      and optional physical redemption workflow
 *
 * Key features:
 * - 1 token = unitSize units of the physical commodity
 * - Oracle-based NAV (net asset value) per token
 * - Custodian role: only custodian can mint against backing proof
 * - Physical redemption: token holders can request physical delivery
 * - Compliance hooks: transfers can be restricted via compliance module
 * - Works as underlying for Futures contracts
 *
 * Example: Gold token where 1 GOLD = 1 troy oz, oracle provides USD/oz price
 */
contract CommodityToken is ICommodityToken, ERC20, ERC20Burnable, ERC20Pausable, AccessControl, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CUSTODIAN_ROLE = keccak256("CUSTODIAN_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum oracle price age before considered stale (30 minutes)
    uint256 public constant MAX_PRICE_AGE = 30 minutes;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Commodity unit description (e.g., "troy oz", "barrel")
    string public unit;

    /// @notice Amount of physical commodity per token (18 decimals)
    uint256 public unitSize;

    /// @notice Price oracle for this commodity
    IOracle public oracle;

    /// @notice Custodian address (manages physical backing)
    address public override custodian;

    /// @notice Whether physical redemption is enabled
    bool public physicalRedemptionEnabled;

    /// @notice Total commodity units backed (tracked for audit, 18 decimals)
    uint256 public totalBacking;

    /// @notice Compliance module for transfer restrictions (address(0) = no restrictions)
    address public complianceModule;

    /// @notice Blocked addresses (sanctions, etc.)
    mapping(address => bool) public blocked;

    /// @notice Redemption requests
    mapping(uint256 => RedemptionRequest) internal _redemptions;

    /// @notice Next redemption request ID
    uint256 public nextRedemptionId = 1;

    /// @notice Backing proofs (hash => amount minted against it)
    mapping(bytes32 => uint256) public backingProofs;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @param _name Token name (e.g., "Lux Gold")
     * @param _symbol Token symbol (e.g., "GOLD")
     * @param _unit Commodity unit (e.g., "troy oz")
     * @param _unitSize Physical commodity per token (18 decimals, e.g., 1e18 = 1 oz per token)
     * @param _oracle Price oracle address
     * @param _custodian Custodian address
     * @param _admin Admin address
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _unit,
        uint256 _unitSize,
        address _oracle,
        address _custodian,
        address _admin
    ) ERC20(_name, _symbol) {
        if (_oracle == address(0)) revert InvalidOracle();
        if (_custodian == address(0)) revert ZeroAddress();
        if (_unitSize == 0) revert InvalidUnitSize();

        unit = _unit;
        unitSize = _unitSize;
        oracle = IOracle(_oracle);
        custodian = _custodian;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(CUSTODIAN_ROLE, _custodian);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINTING & BURNING
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICommodityToken
    function mint(address to, uint256 amount, bytes32 backingProof) external onlyRole(CUSTODIAN_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Track backing proof to prevent double-minting
        backingProofs[backingProof] += amount;
        totalBacking += (amount * unitSize) / PRECISION;

        _mint(to, amount);

        emit Minted(to, amount, backingProof);
    }

    /// @inheritdoc ICommodityToken
    function burn(uint256 amount) public override(ICommodityToken, ERC20Burnable) {
        if (amount == 0) revert ZeroAmount();

        totalBacking -= (amount * unitSize) / PRECISION;

        super.burn(amount);

        emit Burned(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHYSICAL REDEMPTION
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICommodityToken
    function requestRedemption(uint256 amount) external nonReentrant whenNotPaused returns (uint256 requestId) {
        if (!physicalRedemptionEnabled) revert RedemptionNotEnabled();
        if (amount == 0) revert ZeroAmount();

        // Lock tokens by transferring to this contract
        _transfer(msg.sender, address(this), amount);

        requestId = nextRedemptionId++;

        _redemptions[requestId] = RedemptionRequest({
            requester: msg.sender,
            amount: amount,
            requestedAt: block.timestamp,
            processedAt: 0,
            fulfilled: false,
            cancelled: false
        });

        emit RedemptionRequested(requestId, msg.sender, amount);
    }

    /// @inheritdoc ICommodityToken
    function fulfillRedemption(uint256 requestId) external onlyRole(CUSTODIAN_ROLE) nonReentrant {
        RedemptionRequest storage req = _redemptions[requestId];
        if (req.requester == address(0)) revert RedemptionNotFound();
        if (req.fulfilled || req.cancelled) revert RedemptionAlreadyProcessed();

        req.fulfilled = true;
        req.processedAt = block.timestamp;

        // Burn the locked tokens
        totalBacking -= (req.amount * unitSize) / PRECISION;
        _burn(address(this), req.amount);

        emit RedemptionFulfilled(requestId, req.requester, req.amount);
    }

    /// @inheritdoc ICommodityToken
    function cancelRedemption(uint256 requestId) external nonReentrant {
        RedemptionRequest storage req = _redemptions[requestId];
        if (req.requester == address(0)) revert RedemptionNotFound();
        if (req.fulfilled || req.cancelled) revert RedemptionAlreadyProcessed();
        if (msg.sender != req.requester && !hasRole(CUSTODIAN_ROLE, msg.sender)) revert NotCustodian();

        req.cancelled = true;
        req.processedAt = block.timestamp;

        // Return locked tokens
        _transfer(address(this), req.requester, req.amount);

        emit RedemptionCancelled(requestId, req.requester);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICommodityToken
    function getNav() external view returns (uint256 nav, uint256 timestamp) {
        (uint256 price, uint256 ts) = oracle.getPrice(address(this));
        nav = (price * unitSize) / PRECISION;
        timestamp = ts;
    }

    /// @inheritdoc ICommodityToken
    function getCommodityInfo() external view returns (CommodityInfo memory) {
        return CommodityInfo({
            name: name(),
            symbol: symbol(),
            unit: unit,
            unitSize: unitSize,
            oracle: address(oracle),
            physicalRedemptionEnabled: physicalRedemptionEnabled
        });
    }

    /// @inheritdoc ICommodityToken
    function getTotalValue() external view returns (uint256) {
        (uint256 price,) = oracle.getPrice(address(this));
        return (totalSupply() * price * unitSize) / (PRECISION * PRECISION);
    }

    /// @inheritdoc ICommodityToken
    function getRedemption(uint256 requestId) external view returns (RedemptionRequest memory) {
        return _redemptions[requestId];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function setOracle(address _oracle) external onlyRole(ADMIN_ROLE) {
        if (_oracle == address(0)) revert InvalidOracle();
        address old = address(oracle);
        oracle = IOracle(_oracle);
        emit OracleUpdated(old, _oracle);
    }

    function setCustodian(address _custodian) external onlyRole(ADMIN_ROLE) {
        if (_custodian == address(0)) revert ZeroAddress();
        address old = custodian;

        _revokeRole(CUSTODIAN_ROLE, old);
        _grantRole(CUSTODIAN_ROLE, _custodian);

        custodian = _custodian;
        emit CustodianChanged(old, _custodian);
    }

    function setPhysicalRedemption(bool enabled) external onlyRole(ADMIN_ROLE) {
        physicalRedemptionEnabled = enabled;
    }

    function setComplianceModule(address _module) external onlyRole(ADMIN_ROLE) {
        complianceModule = _module;
    }

    function blockAddress(address account) external onlyRole(COMPLIANCE_ROLE) {
        blocked[account] = true;
    }

    function unblockAddress(address account) external onlyRole(COMPLIANCE_ROLE) {
        blocked[account] = false;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @dev Hook called before every transfer. Enforces compliance restrictions.
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        // Compliance checks (skip on mint/burn)
        if (from != address(0) && to != address(0)) {
            if (blocked[from] || blocked[to]) revert TransferRestricted();

            // External compliance module check
            if (complianceModule != address(0)) {
                (bool success, bytes memory data) = complianceModule.staticcall(
                    abi.encodeWithSignature("canTransfer(address,address,uint256)", from, to, value)
                );
                if (success && data.length >= 32) {
                    bool allowed = abi.decode(data, (bool));
                    if (!allowed) revert TransferRestricted();
                }
            }
        }

        super._update(from, to, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
