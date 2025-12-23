// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

/**
    ███████╗ ██████╗  ██████╗     ██╗   ██╗ █████╗ ██╗   ██╗██╗     ████████╗
    ╚══███╔╝██╔═══██╗██╔═══██╗    ██║   ██║██╔══██╗██║   ██║██║     ╚══██╔══╝
      ███╔╝ ██║   ██║██║   ██║    ██║   ██║███████║██║   ██║██║        ██║   
     ███╔╝  ██║   ██║██║   ██║    ╚██╗ ██╔╝██╔══██║██║   ██║██║        ██║   
    ███████╗╚██████╔╝╚██████╔╝     ╚████╔╝ ██║  ██║╚██████╔╝███████╗   ██║   
    ╚══════╝ ╚═════╝  ╚═════╝       ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   
 */

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {LERC4626} from "./LERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ETHVault} from "./ETHVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ZooVault is Ownable {
    mapping(address => address) public erc20Vault;
    address payable public ethVaultAddress;
    uint256 public totalVaultLength;
    address[] public assets;

    event ERC20VaultCreated(
        address indexed asset,
        address indexed vaultAddress
    );

    constructor() Ownable(msg.sender) {
        ethVaultAddress = payable(0); // Setting to zero address
    }

    function concat(
        string memory a,
        string memory b
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    /**
     * @dev add new ERC20 vault
     * @param asset_ ERC20 token address
     */
    function addNewVault(address asset_) external onlyOwner {
        _addNewVault(asset_);
    }

    /**
     * @dev add new ERC20 or ETH vault
     * @param asset_ asset address
     */
    function _addNewVault(address asset_) private {
        if(asset_ == address(0)) {
            _addETHVault();
        } else {
            _addNewERC20Vault(asset_);
        }
    }

    /**
     * @dev add new ERC20 vault
     * @param asset_ ERC20 token address
     */
    function _addNewERC20Vault(address asset_) private {
        require(erc20Vault[asset_] == address(0), "Vault already exists.");
        LERC4626 newERC20Vault = new LERC4626(
            IERC20(asset_),
            concat(ERC20(asset_).name(), " Vault"),
            concat("v", ERC20(asset_).symbol())
        );
        address newVaultAddress = address(newERC20Vault);
        erc20Vault[asset_] = newVaultAddress;
        IERC20(asset_).approve(newVaultAddress, type(uint256).max);
        totalVaultLength++;
        assets.push(asset_);
        emit ERC20VaultCreated(asset_, newVaultAddress);
    }

    /**
     * @dev add ETH vault
     */
    function _addETHVault() private {
        require(ethVaultAddress == payable(0), "ethVaultAddress already exists!");
        ETHVault _newETHVault = new ETHVault("Native Vault", "ethVault");
        ethVaultAddress = payable(address(_newETHVault));
    }

    /**
     * @dev deposit asset
     * @param asset_ ERC20 token address
     * @param amount_ token amount
     */
    function deposit(
        address asset_,
        uint256 amount_
    ) external payable onlyOwner {
        if (asset_ == address(0)) {
            if(ethVaultAddress == payable(0)) {
                _addNewVault(address(0));
            }
            require(msg.value >= amount_, "Insufficient ETH amount");
            ETHVault(ethVaultAddress).deposit{value: amount_}(amount_, owner());
        } else {
        if(erc20Vault[asset_] == address(0)) {
                _addNewVault(asset_);
            }
            ERC4626(erc20Vault[asset_]).deposit(amount_, owner());
        }
    }

    /**
     * @dev withdraw asset
     * @param asset_ ERC20 token address
     * @param receiver_ receiver's address
     * @param amount_ token amount
     */
    function withdraw(
        address asset_,
        address receiver_,
        uint256 amount_
    ) external onlyOwner {
        if (asset_ == address(0)) {
            require(ethVaultAddress != payable(0), "Ethvault does not exist!");
            ETHVault(ethVaultAddress).withdraw(amount_, receiver_, owner());
        } else {
            require(erc20Vault[asset_] != payable(0), "Ethvault does not exist!");
            ERC4626(erc20Vault[asset_]).withdraw(amount_, receiver_, owner());
        }
    }

    /**
     * @dev preview withdraw
     * @param asset_ asset address
     * @return value token amount available for withdrawal
     */
    function previewWithdraw(
        address asset_
    ) public view returns (uint256) {
        if (asset_ == address(0)) {
            if(ethVaultAddress == payable(0)) {
                return 0;
            } else {
                return ETHVault(ethVaultAddress).balanceOf(owner());
            }
        } else {
            if(erc20Vault[asset_] == address(0)) {
                return 0;
            } else {
                return ERC4626(erc20Vault[asset_]).maxWithdraw(owner());
            }
        }
    }

    /**
     * @dev get vault info according to asset address
     * @param asset_ ERC20 token address
     * @return info vault info
     */
    function getVaultInfo(
        address asset_
    )
        external
        view
        returns (
            string memory,
            string memory,
            string memory,
            string memory,
            address,
            uint256
        )
    {
        if (asset_ == address(0)) {
            return (
                "Native Token",
                "ETH",
                ETHVault(ethVaultAddress).name(),
                ETHVault(ethVaultAddress).symbol(),
                ethVaultAddress,
                ETHVault(ethVaultAddress).totalSupply()
            );
        } else {
            return (
                ERC20(asset_).name(),
                ERC20(asset_).symbol(),
                LERC4626(erc20Vault[asset_]).name(),
                LERC4626(erc20Vault[asset_]).symbol(), // Add parentheses here
                erc20Vault[asset_],
                LERC4626(erc20Vault[asset_]).totalAssets()
            );
        }
    }

    receive() external payable {}
}
