// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.17;

/// @title IERC1404
/// @notice The Simple Restricted Token Standard. A regulated-token transfer
///         either succeeds (code 0) or fails with one of the canonical
///         restriction codes 1..11. Codes carry a structured, human-readable
///         message — the chain is the source of truth, not the UI.
/// @dev    Canonical code table (NEVER extend beyond 0..11):
///           0  Approved
///           1  Verification required           (sender not registered)
///           2  Additional verification required (sender missing required topic)
///           3  Identity verification expired   (sender claim expired)
///           4  Recipient not verified
///           5  Recipient missing required topic
///           6  Recipient verification expired
///           7  Region restricted
///           8  Locked
///           9  Holder cap reached
///           10 Limit reached
///           11 Cross-chain destination not allow-listed
interface IERC1404 {
    /// @notice Detects whether a transfer of `value` from `from` to `to`
    ///         would be restricted. Returns 0 if the transfer is approved or
    ///         a non-zero code 1..11 identifying the restriction.
    function detectTransferRestriction(address from, address to, uint256 value)
        external view returns (uint8 code);

    /// @notice Returns the canonical human-readable message for `code`.
    ///         Strings are stable and live on chain — UIs never reinvent the
    ///         text. Unknown codes return "Unknown restriction".
    function messageForTransferRestriction(uint8 code)
        external view returns (string memory message);
}

/// @title IERC1404Extended
/// @notice Extension that surfaces every failing module reason, not just the
///         first. Used by BD's pre-trade endpoint and any client that wants
///         to show the full remediation set (e.g. "you need KYC AND the
///         token is locked until tomorrow").
interface IERC1404Extended is IERC1404 {
    /// @notice Returns every non-zero restriction code that would block this
    ///         transfer, ordered by module evaluation order.
    function detectAllTransferRestrictions(address from, address to, uint256 value)
        external view returns (uint8[] memory codes);
}
