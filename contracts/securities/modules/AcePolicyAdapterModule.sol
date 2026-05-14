// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { AbstractModule } from "@luxfi/standard/securities/erc3643/compliance/modular/modules/AbstractModule.sol";
import { IModularCompliance } from "@luxfi/standard/securities/erc3643/compliance/modular/IModularCompliance.sol";
import { IToken } from "@luxfi/standard/securities/erc3643/token/IToken.sol";
import { IAcePolicy, IAcePolicyEngine } from "@luxfi/standard/integrations/ace/IAcePolicy.sol";

/// @title AcePolicyAdapterModule
/// @notice ERC-3643 compliance module that delegates evaluation to a
///         Chainlink ACE `IPolicy` contract. Lets an ERC-3643 SecurityToken
///         enforce an ACE policy (volume limits, allow-lists, jurisdiction
///         rules, anything the integrator has shipped as an ACE policy)
///         WITHOUT making the token itself ACE-protected.
///
///         Adapter is the canonical bridge: ACE policies become first-class
///         IModule instances and compose with our native Claim/Rule144/
///         Teleport/JurisdictionAllow/JurisdictionDeny/HolderCap modules
///         in any combination, per-token, via `ModularCompliance.addModule`.
/// @dev    Inverse direction (exposing our SecurityToken to ACE-native
///         integrators) is handled by a separate `AceSecurityTokenAdapter`
///         contract — wraps an ERC-3643 SecurityToken and presents the
///         `IPolicyProtected` surface that Chainlink ACE expects. Not in
///         this file (and not strictly required by aggregators that route
///         on raw ERC-3643 + ERC-1404 surface).
contract AcePolicyAdapterModule is AbstractModule {
    string private constant _NAME = "AcePolicyAdapterModule";

    /// ERC-1404 codes returned by {moduleReason}.
    uint8 internal constant CODE_OK = 0;
    uint8 internal constant CODE_ADDITIONAL_VERIFICATION = 2; // ACE PolicyResult.None
    uint8 internal constant CODE_REGION_RESTRICTED = 7;       // common ACE jurisdiction reject
    uint8 internal constant CODE_LIMIT_REACHED = 10;          // common ACE volume cap reject

    /// Canonical ERC-20 / ERC-3643 `transfer(address,uint256)` selector. ACE
    /// policies are typically configured per-(target, selector); the adapter
    /// passes this selector when calling `run`. Token-level mint/burn are
    /// out of scope for this adapter — handled by their own modules.
    bytes4 internal constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    /// ACE Parameter names the adapter encodes. Policies that need other
    /// names should be re-deployed; this is the canonical set Liquid passes.
    bytes32 internal constant PARAM_FROM = "from";
    bytes32 internal constant PARAM_TO = "to";
    bytes32 internal constant PARAM_AMOUNT = "amount";

    /// Per-compliance configuration. `policy` is the ACE IPolicy contract;
    /// `rejectCode` is the ERC-1404 code returned when the policy rejects
    /// (None/revert path) so the off-chain decoder gets meaningful state.
    struct Config {
        IAcePolicy policy;
        uint8 rejectCode;
        bool initialised;
    }

    mapping(address compliance => Config) public config;

    event AcePolicyConfigured(address indexed compliance, address indexed policy, uint8 rejectCode);

    error AlreadyInitialised();
    error PolicyZero();

    /// @notice One-shot init by the compliance owner. After init, the ACE
    ///         policy address cannot change — re-deploy the adapter with the
    ///         new policy or write a `setPolicy` setter behind governance.
    /// @param compliance The ModularCompliance instance binding this module.
    /// @param policy     ACE IPolicy contract to delegate to.
    /// @param rejectCode ERC-1404 code (0..11) the adapter returns when the
    ///        policy rejects. Pick the code that best matches the policy's
    ///        domain (7 for jurisdiction-policy, 10 for volume-cap, 2 default).
    function configure(address compliance, IAcePolicy policy, uint8 rejectCode) external {
        require(this.isComplianceBound(compliance), "compliance not bound");
        require(msg.sender == _complianceOwner(compliance), "only compliance owner");
        if (config[compliance].initialised) revert AlreadyInitialised();
        if (address(policy) == address(0)) revert PolicyZero();
        config[compliance] = Config({policy: policy, rejectCode: rejectCode, initialised: true});
        emit AcePolicyConfigured(compliance, address(policy), rejectCode);
    }

    /// @notice See {IModule-moduleCheck}.
    function moduleCheck(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (bool)
    {
        return this.moduleReason(_from, _to, _value, _compliance) == CODE_OK;
    }

    /// @notice See {IModule-moduleReason}. Calls the configured ACE policy
    ///         with the transfer parameters; maps PolicyResult to ERC-1404:
    ///           Allowed   → 0  (CODE_OK)
    ///           Continue  → 0  (abstain — let downstream modules decide)
    ///           None      → rejectCode (configured per-compliance)
    ///           revert    → rejectCode (defensive: treat any policy failure
    ///                       as a reject; off-chain inspectors can read the
    ///                       revert reason via cast call for diagnosis)
    function moduleReason(address _from, address _to, uint256 _value, address _compliance)
        external
        view
        override
        returns (uint8)
    {
        Config memory cfg = config[_compliance];
        // Unconfigured → no gate (module is a no-op). Mint/burn skipped — ACE
        // typically gates transfers; for mint/burn-side policies use a
        // dedicated module.
        if (!cfg.initialised) return CODE_OK;
        if (_from == address(0) || _to == address(0)) return CODE_OK;

        IToken securityToken = IToken(IModularCompliance(_compliance).getTokenBound());

        // Package transfer arguments as ACE-style named parameters. Policies
        // that inspect (from, to, amount) decode these by name; policies that
        // need a different schema get re-deployed with a different name set.
        bytes[] memory parameters = new bytes[](3);
        parameters[0] = abi.encode(PARAM_FROM, abi.encode(_from));
        parameters[1] = abi.encode(PARAM_TO, abi.encode(_to));
        parameters[2] = abi.encode(PARAM_AMOUNT, abi.encode(_value));

        // try/catch around the policy call: any revert (including ACE's
        // structured `PolicyRejected(string)` error) maps to the configured
        // rejectCode. Off-chain UIs can re-call the policy via cast to fetch
        // the human-readable reason for display; on-chain we only need a code.
        try cfg.policy.run(_from, address(securityToken), TRANSFER_SELECTOR, parameters, "") returns (
            IAcePolicyEngine.PolicyResult result
        ) {
            if (result == IAcePolicyEngine.PolicyResult.Allowed) return CODE_OK;
            if (result == IAcePolicyEngine.PolicyResult.Continue) return CODE_OK;
            // PolicyResult.None — explicit non-decision; engine treats as reject.
            return cfg.rejectCode;
        } catch {
            return cfg.rejectCode;
        }
    }

    function moduleTransferAction(address, address, uint256) external override onlyComplianceCall { }
    function moduleMintAction(address, uint256) external override onlyComplianceCall { }
    function moduleBurnAction(address, uint256) external override onlyComplianceCall { }

    function canComplianceBind(address) external pure override returns (bool) {
        return true;
    }

    function isPlugAndPlay() external pure override returns (bool) {
        return true;
    }

    function name() external pure override returns (string memory) {
        return _NAME;
    }

    function _complianceOwner(address compliance) internal view returns (address) {
        (bool ok, bytes memory ret) = compliance.staticcall(abi.encodeWithSignature("owner()"));
        require(ok && ret.length >= 32, "owner() unavailable");
        return abi.decode(ret, (address));
    }
}
