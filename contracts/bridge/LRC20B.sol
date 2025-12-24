// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
    ██╗     ██╗   ██╗██╗  ██╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
    ██║     ██║   ██║╚██╗██╔╝    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
    ██║     ██║   ██║ ╚███╔╝        ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
    ██║     ██║   ██║ ██╔██╗        ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████╗╚██████╔╝██╔╝ ██╗       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
 */

import {LRC20} from "../tokens/LRC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title LRC20B
 * @author Lux Network
 * @notice LRC20 Bridge Token - Base contract for bridged tokens
 * @dev Extends LRC20 with bridge mint/burn capabilities and role-based access
 */
contract LRC20B is LRC20, Ownable, AccessControl {
    event BridgeMint(address indexed account, uint amount);
    event BridgeBurn(address indexed account, uint amount);
    event AdminGranted(address to);
    event AdminRevoked(address to);

    constructor(
        string memory name_,
        string memory symbol_
    ) LRC20(name_, symbol_) Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev verify that the sender is an admin
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "LRC20B: caller is not admin"
        );
        _;
    }

    /**
     * @dev grant admin role to specific user
     */
    function grantAdmin(address to) public onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminGranted(to);
    }

    /**
     * @dev revoke admin role from specific user
     */
    function revokeAdmin(address to) public onlyAdmin {
        require(hasRole(DEFAULT_ADMIN_ROLE, to), "LRC20B: not an admin");
        revokeRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminRevoked(to);
    }

    /**
     * @dev mint token via bridge
     * @return amount If successful, returns true
     */
    function bridgeMint(
        address account,
        uint256 amount
    ) public onlyAdmin returns (bool) {
        _mint(account, amount);
        emit BridgeMint(account, amount);
        return true;
    }

    /**
     * @dev burn token via bridge
     * @return amount If successful, returns true
     */
    function bridgeBurn(
        address account,
        uint256 amount
    ) public onlyAdmin returns (bool) {
        _burn(account, amount);
        emit BridgeBurn(account, amount);
        return true;
    }

    /**
     * @dev Override _msgSender for OZ AccessControl/Ownable and LRC20 compatibility
     */
    function _msgSender() internal view override(Context, LRC20) returns (address) {
        return msg.sender;
    }
}
