// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title ERC20 Re-exports
 * @author Lux Industries Inc
 * @notice OpenZeppelin ERC20 re-exports for @luxfi/standard
 * @dev Import from here - no need for @openzeppelin imports
 *
 * Usage:
 *   import {ERC20} from "@luxfi/standard/tokens/ERC20.sol";
 *   import {IERC20} from "@luxfi/standard/tokens/ERC20.sol";
 */

// Core ERC20
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Extensions
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {ERC20FlashMint} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
// TODO: Re-enable when draft-ERC20Bridgeable.sol is in OZ mainline
// import {ERC20Bridgeable} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Bridgeable.sol";

// Utils
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Governance (IVotes for ERC20Votes)
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
