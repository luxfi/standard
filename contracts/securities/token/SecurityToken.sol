// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IIdentityRegistry } from "@luxfi/standard/securities/erc3643/registry/interface/IIdentityRegistry.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IIdentity } from "@luxfi/standard/securities/onchainid/interface/IIdentity.sol";
import { IERC1404, IERC1404Extended } from "@luxfi/standard/securities/erc1404/IERC1404.sol";

/// @title SecurityToken
/// @notice Lux's canonical ERC-3643 security token. Implements the T-REX `IToken`
///         interface so it interoperates with every ERC-3643 tool (DVA, DVD,
///         compliance modules, identity registry, factories) — but designed
///         our way: constructor-based, AccessControl-driven, no upgradeable
///         proxies, no `Ownable`/`AgentRole` split, no two-step `init()`.
///         Deploy once with a fully-formed compliance stack and trade.
/// @dev    Roles
///           DEFAULT_ADMIN_ROLE  governance: setName/Symbol/OnchainID,
///                               setIdentityRegistry, setCompliance.
///           AGENT_ROLE          operations: mint, burn, freeze, forced
///                               transfer, pause/unpause, recoveryAddress.
///         The deployer (`admin`) gets both roles. Add agents via
///         `grantRole(AGENT_ROLE, agent)` (the T-REX `addAgent` equivalent).
contract SecurityToken is IToken, IERC1404Extended, ERC20, AccessControl {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    string private constant _VERSION = "lux-1.0.0";

    /// ERC-1404 canonical codes — single source of truth for token-level
    /// restrictions. Module-level codes (1/2/3/5/6/7/9/10/11) come from
    /// `_compliance.firstTransferReason`; token-level conditions (paused,
    /// frozen wallet, insufficient free balance) map to code 8 (Locked), and
    /// recipient-not-registered maps to code 4.
    uint8 internal constant _CODE_OK = 0;
    uint8 internal constant _CODE_RECIPIENT_NOT_VERIFIED = 4;
    uint8 internal constant _CODE_LOCKED = 8;

    string private _tokenName;
    string private _tokenSymbol;
    uint8 private immutable _tokenDecimals;
    address private _tokenOnchainID;
    bool private _tokenPaused;

    IIdentityRegistry private _idRegistry;
    IModularCompliance private _compliance;

    mapping(address => bool) private _frozen;
    mapping(address => uint256) private _frozenTokens;

    error TokenIsPaused();
    error TokenNotPaused();
    error ZeroAddress();
    error EmptyString();
    error DecimalsTooHigh();
    error NotVerified(address account);
    error NotCompliant();
    error WalletFrozen(address account);
    error InsufficientFreeBalance(address account, uint256 requested, uint256 free);
    error FrozenAmountExceedsBalance();
    error UnfreezeAmountExceedsFrozen();
    error RecoveryFailed();
    /// @notice ERC-1404 structured revert. `code` is a canonical 0..11 code,
    ///         `reason` is the matching on-chain message. Decoded on the
    ///         off-chain side by the shared compliance package — never
    ///         re-derived per app.
    error TransferRestricted(uint8 code, string reason);

    modifier onlyAgent() {
        _checkRole(AGENT_ROLE);
        _;
    }

    modifier whenNotPaused() {
        if (_tokenPaused) revert TokenIsPaused();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        IIdentityRegistry idRegistry_,
        IModularCompliance compliance_,
        address onchainID_,
        address admin
    ) ERC20("", "") {
        if (admin == address(0)) revert ZeroAddress();
        if (address(idRegistry_) == address(0)) revert ZeroAddress();
        if (address(compliance_) == address(0)) revert ZeroAddress();
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert EmptyString();
        if (decimals_ > 18) revert DecimalsTooHigh();

        _tokenName = name_;
        _tokenSymbol = symbol_;
        _tokenDecimals = decimals_;
        _tokenOnchainID = onchainID_;
        _idRegistry = idRegistry_;
        _compliance = compliance_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AGENT_ROLE, admin);

        compliance_.bindToken(address(this));

        emit IdentityRegistryAdded(address(idRegistry_));
        emit ComplianceAdded(address(compliance_));
        emit UpdatedTokenInformation(name_, symbol_, decimals_, _VERSION, onchainID_);
    }

    // ── ERC20 metadata ──────────────────────────────────────────────────────

    function name() public view override(ERC20, IToken) returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override(ERC20, IToken) returns (string memory) {
        return _tokenSymbol;
    }

    function decimals() public view override(ERC20, IToken) returns (uint8) {
        return _tokenDecimals;
    }

    // ── ERC20 transfers (compliance-gated) ──────────────────────────────────

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) whenNotPaused returns (bool) {
        _enforceTransfer(_msgSender(), to, amount);
        bool ok = super.transfer(to, amount);
        _compliance.transferred(_msgSender(), to, amount);
        return ok;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override(ERC20, IERC20)
        whenNotPaused
        returns (bool)
    {
        _enforceTransfer(from, to, amount);
        bool ok = super.transferFrom(from, to, amount);
        _compliance.transferred(from, to, amount);
        return ok;
    }

    function batchTransfer(address[] calldata toList, uint256[] calldata amounts) external override {
        for (uint256 i = 0; i < toList.length; ++i) {
            transfer(toList[i], amounts[i]);
        }
    }

    // ── IToken: governance ──────────────────────────────────────────────────

    function setName(string calldata newName) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bytes(newName).length == 0) revert EmptyString();
        _tokenName = newName;
        emit UpdatedTokenInformation(newName, _tokenSymbol, _tokenDecimals, _VERSION, _tokenOnchainID);
    }

    function setSymbol(string calldata newSymbol) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bytes(newSymbol).length == 0) revert EmptyString();
        _tokenSymbol = newSymbol;
        emit UpdatedTokenInformation(_tokenName, newSymbol, _tokenDecimals, _VERSION, _tokenOnchainID);
    }

    function setOnchainID(address onchainID_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _tokenOnchainID = onchainID_;
        emit UpdatedTokenInformation(_tokenName, _tokenSymbol, _tokenDecimals, _VERSION, onchainID_);
    }

    function setIdentityRegistry(address idRegistry_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (idRegistry_ == address(0)) revert ZeroAddress();
        _idRegistry = IIdentityRegistry(idRegistry_);
        emit IdentityRegistryAdded(idRegistry_);
    }

    function setCompliance(address compliance_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (compliance_ == address(0)) revert ZeroAddress();
        _compliance.unbindToken(address(this));
        _compliance = IModularCompliance(compliance_);
        _compliance.bindToken(address(this));
        emit ComplianceAdded(compliance_);
    }

    function onchainID() external view override returns (address) {
        return _tokenOnchainID;
    }

    function version() external pure override returns (string memory) {
        return _VERSION;
    }

    function identityRegistry() external view override returns (IIdentityRegistry) {
        return _idRegistry;
    }

    function compliance() external view override returns (IModularCompliance) {
        return _compliance;
    }

    // ── IToken: pause ───────────────────────────────────────────────────────

    function pause() external override onlyAgent {
        if (_tokenPaused) revert TokenIsPaused();
        _tokenPaused = true;
        emit Paused(_msgSender());
    }

    function unpause() external override onlyAgent {
        if (!_tokenPaused) revert TokenNotPaused();
        _tokenPaused = false;
        emit Unpaused(_msgSender());
    }

    function paused() external view override returns (bool) {
        return _tokenPaused;
    }

    // ── IToken: mint / burn / forced transfer ───────────────────────────────

    function mint(address to, uint256 amount) public override onlyAgent {
        if (!_idRegistry.isVerified(to)) revert NotVerified(to);
        if (!_compliance.canTransfer(address(0), to, amount)) revert NotCompliant();
        _mint(to, amount);
        _compliance.created(to, amount);
    }

    function burn(address from, uint256 amount) public override onlyAgent {
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) {
            uint256 toUnfreeze = amount - free;
            _frozenTokens[from] -= toUnfreeze;
            emit TokensUnfrozen(from, toUnfreeze);
        }
        _burn(from, amount);
        _compliance.destroyed(from, amount);
    }

    function forcedTransfer(address from, address to, uint256 amount) public override onlyAgent returns (bool) {
        if (!_idRegistry.isVerified(to)) revert NotVerified(to);
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) {
            uint256 toUnfreeze = amount - free;
            _frozenTokens[from] -= toUnfreeze;
            emit TokensUnfrozen(from, toUnfreeze);
        }
        _transfer(from, to, amount);
        _compliance.transferred(from, to, amount);
        return true;
    }

    function batchMint(address[] calldata toList, uint256[] calldata amounts) external override {
        for (uint256 i = 0; i < toList.length; ++i) {
            mint(toList[i], amounts[i]);
        }
    }

    function batchBurn(address[] calldata fromList, uint256[] calldata amounts) external override {
        for (uint256 i = 0; i < fromList.length; ++i) {
            burn(fromList[i], amounts[i]);
        }
    }

    function batchForcedTransfer(address[] calldata fromList, address[] calldata toList, uint256[] calldata amounts)
        external
        override
    {
        for (uint256 i = 0; i < fromList.length; ++i) {
            forcedTransfer(fromList[i], toList[i], amounts[i]);
        }
    }

    // ── IToken: freezing ────────────────────────────────────────────────────

    function setAddressFrozen(address user, bool freeze) public override onlyAgent {
        _frozen[user] = freeze;
        emit AddressFrozen(user, freeze, _msgSender());
    }

    function freezePartialTokens(address user, uint256 amount) public override onlyAgent {
        if (balanceOf(user) < _frozenTokens[user] + amount) revert FrozenAmountExceedsBalance();
        _frozenTokens[user] += amount;
        emit TokensFrozen(user, amount);
    }

    function unfreezePartialTokens(address user, uint256 amount) public override onlyAgent {
        if (_frozenTokens[user] < amount) revert UnfreezeAmountExceedsFrozen();
        _frozenTokens[user] -= amount;
        emit TokensUnfrozen(user, amount);
    }

    function batchSetAddressFrozen(address[] calldata users, bool[] calldata freezes) external override {
        for (uint256 i = 0; i < users.length; ++i) {
            setAddressFrozen(users[i], freezes[i]);
        }
    }

    function batchFreezePartialTokens(address[] calldata users, uint256[] calldata amounts) external override {
        for (uint256 i = 0; i < users.length; ++i) {
            freezePartialTokens(users[i], amounts[i]);
        }
    }

    function batchUnfreezePartialTokens(address[] calldata users, uint256[] calldata amounts) external override {
        for (uint256 i = 0; i < users.length; ++i) {
            unfreezePartialTokens(users[i], amounts[i]);
        }
    }

    function isFrozen(address user) external view override returns (bool) {
        return _frozen[user];
    }

    function getFrozenTokens(address user) external view override returns (uint256) {
        return _frozenTokens[user];
    }

    // ── IToken: recovery (lost wallet → new wallet) ─────────────────────────

    function recoveryAddress(address lostWallet, address newWallet, address investorOnchainID)
        external
        override
        onlyAgent
        returns (bool)
    {
        if (balanceOf(lostWallet) == 0) revert RecoveryFailed();
        IIdentity id = IIdentity(investorOnchainID);
        bytes32 key = keccak256(abi.encode(newWallet));
        if (!id.keyHasPurpose(key, 1)) revert RecoveryFailed();

        uint256 bal = balanceOf(lostWallet);
        uint256 frozenAmount = _frozenTokens[lostWallet];
        bool wasFrozen = _frozen[lostWallet];

        _idRegistry.registerIdentity(newWallet, id, _idRegistry.investorCountry(lostWallet));
        forcedTransfer(lostWallet, newWallet, bal);
        if (frozenAmount > 0) freezePartialTokens(newWallet, frozenAmount);
        if (wasFrozen) setAddressFrozen(newWallet, true);
        _idRegistry.deleteIdentity(lostWallet);

        emit RecoverySuccess(lostWallet, newWallet, investorOnchainID);
        return true;
    }

    // ── ERC-165 ─────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 id) public view override(AccessControl) returns (bool) {
        return id == type(IToken).interfaceId
            || id == type(IERC1404).interfaceId
            || id == type(IERC1404Extended).interfaceId
            || super.supportsInterface(id);
    }

    // ── ERC-1404: detect + message ──────────────────────────────────────────

    /// @notice See {IERC1404-detectTransferRestriction}. Single canonical
    ///         entry point for off-chain pre-trade checks AND the on-chain
    ///         revert path. Token-level conditions are evaluated first
    ///         (cheapest checks, most common failures), then the compliance
    ///         stack supplies module codes 1..11.
    function detectTransferRestriction(address from, address to, uint256 amount)
        public
        view
        override
        returns (uint8)
    {
        if (_tokenPaused) return _CODE_LOCKED;
        if (_frozen[from]) return _CODE_LOCKED;
        if (_frozen[to]) return _CODE_LOCKED;
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) return _CODE_LOCKED;
        if (!_idRegistry.isVerified(to)) return _CODE_RECIPIENT_NOT_VERIFIED;
        return _compliance.firstTransferReason(from, to, amount);
    }

    /// @notice See {IERC1404Extended-detectAllTransferRestrictions}. Returns
    ///         every failing code (token-level first, then every failing
    ///         module). Empty array = approved.
    function detectAllTransferRestrictions(address from, address to, uint256 amount)
        external
        view
        override
        returns (uint8[] memory)
    {
        // Pass 1 — count failing checks (token-level + module-level).
        uint8 tokenCode = _tokenLevelCode(from, to, amount);
        uint8 recipientCode = _idRegistry.isVerified(to) ? _CODE_OK : _CODE_RECIPIENT_NOT_VERIFIED;
        (, uint8[] memory moduleCodes) = _compliance.canTransferReasons(from, to, amount);

        uint256 n = 0;
        if (tokenCode != _CODE_OK) n++;
        if (recipientCode != _CODE_OK) n++;
        n += moduleCodes.length;

        uint8[] memory out = new uint8[](n);
        uint256 i = 0;
        if (tokenCode != _CODE_OK) { out[i++] = tokenCode; }
        if (recipientCode != _CODE_OK) { out[i++] = recipientCode; }
        for (uint256 j = 0; j < moduleCodes.length; j++) { out[i++] = moduleCodes[j]; }
        return out;
    }

    /// @notice See {IERC1404-messageForTransferRestriction}. Canonical
    ///         human-readable messages keyed off the 0..11 table. Strings live
    ///         on chain so every front-end (and every external integrator)
    ///         renders identical text.
    function messageForTransferRestriction(uint8 code)
        public
        pure
        override
        returns (string memory)
    {
        if (code == 0) return "Approved";
        if (code == 1) return "Verification required";
        if (code == 2) return "Additional verification required";
        if (code == 3) return "Identity verification expired";
        if (code == 4) return "Recipient not verified";
        if (code == 5) return "Recipient missing required topic";
        if (code == 6) return "Recipient verification expired";
        if (code == 7) return "Region restricted";
        if (code == 8) return "Locked";
        if (code == 9) return "Holder cap reached";
        if (code == 10) return "Limit reached";
        if (code == 11) return "Cross-chain destination not allow-listed";
        return "Unknown restriction";
    }

    // ── Internal: enforce ERC-3643 transfer rules ───────────────────────────

    function _enforceTransfer(address from, address to, uint256 amount) internal view {
        uint8 code = detectTransferRestriction(from, to, amount);
        if (code != _CODE_OK) revert TransferRestricted(code, messageForTransferRestriction(code));
    }

    /// @dev Token-level restriction code, isolated for `detectAllTransferRestrictions`.
    function _tokenLevelCode(address from, address to, uint256 amount) internal view returns (uint8) {
        if (_tokenPaused) return _CODE_LOCKED;
        if (_frozen[from]) return _CODE_LOCKED;
        if (_frozen[to]) return _CODE_LOCKED;
        uint256 free = balanceOf(from) - _frozenTokens[from];
        if (amount > free) return _CODE_LOCKED;
        return _CODE_OK;
    }
}
