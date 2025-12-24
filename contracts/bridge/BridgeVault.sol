// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.20;

/**
    ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗    ██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗
    ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝    ██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝
    ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗      ██║   ██║███████║██║   ██║██║     ██║
    ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝      ╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║
    ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗     ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║
    ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝      ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝

    Unified Bridge Vault - Used by Lux, Zoo, and all ecosystem chains
 */

import {LRC4626} from "../tokens/LRC4626/LRC4626.sol";
import {ETHVault} from "./ETHVault.sol";
import {LRC20} from "../tokens/LRC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BridgeVault
 * @notice Unified vault for all Lux ecosystem bridge operations
 * @dev Manages ERC20 and ETH vaults for cross-chain bridging
 * Used by: Lux mainnet, Zoo, Hanzo, and all ecosystem chains
 */
contract BridgeVault is Ownable {
    mapping(address => address) public erc20Vault;
    address payable public ethVaultAddress;
    uint256 public totalVaultLength;
    address[] public assets;

    event ERC20VaultCreated(
        address indexed asset,
        address indexed vaultAddress
    );
    event ETHVaultCreated(address indexed vaultAddress);

    constructor() Ownable(msg.sender) {
        ethVaultAddress = payable(0);
    }

    function concat(
        string memory a,
        string memory b
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }

    /**
     * @dev Add new ERC20 vault
     * @param asset_ ERC20 token address
     */
    function addNewVault(address asset_) external onlyOwner {
        _addNewVault(asset_);
    }

    /**
     * @dev Add new ERC20 or ETH vault
     * @param asset_ asset address (address(0) for ETH)
     */
    function _addNewVault(address asset_) private {
        if (asset_ == address(0)) {
            _addETHVault();
        } else {
            _addNewERC20Vault(asset_);
        }
    }

    /**
     * @dev Add new ERC20 vault using LRC4626
     * @param asset_ ERC20 token address
     */
    function _addNewERC20Vault(address asset_) private {
        require(erc20Vault[asset_] == address(0), "Vault already exists.");
        LRC4626 newERC20Vault = new LRC4626(
            IERC20(asset_),
            concat(LRC20(asset_).name(), " Vault"),
            concat("v", LRC20(asset_).symbol())
        );
        address newVaultAddress = address(newERC20Vault);
        erc20Vault[asset_] = newVaultAddress;
        IERC20(asset_).approve(newVaultAddress, type(uint256).max);
        totalVaultLength++;
        assets.push(asset_);
        emit ERC20VaultCreated(asset_, newVaultAddress);
    }

    /**
     * @dev Add ETH vault
     */
    function _addETHVault() private {
        require(ethVaultAddress == payable(0), "ETH vault already exists!");
        ETHVault _newETHVault = new ETHVault("Native Vault", "vETH");
        ethVaultAddress = payable(address(_newETHVault));
        emit ETHVaultCreated(ethVaultAddress);
    }

    /**
     * @dev Deposit asset into vault
     * @param asset_ Token address (address(0) for ETH)
     * @param amount_ Amount to deposit
     */
    function deposit(
        address asset_,
        uint256 amount_
    ) external payable onlyOwner {
        if (asset_ == address(0)) {
            if (ethVaultAddress == payable(0)) {
                _addNewVault(address(0));
            }
            require(msg.value >= amount_, "Insufficient ETH amount");
            ETHVault(ethVaultAddress).deposit{value: amount_}(amount_, owner());
        } else {
            if (erc20Vault[asset_] == address(0)) {
                _addNewVault(asset_);
            }
            LRC4626(erc20Vault[asset_]).deposit(amount_, owner());
        }
    }

    /**
     * @dev Withdraw asset from vault
     * @param asset_ Token address (address(0) for ETH)
     * @param receiver_ Recipient address
     * @param amount_ Amount to withdraw
     */
    function withdraw(
        address asset_,
        address receiver_,
        uint256 amount_
    ) external onlyOwner {
        if (asset_ == address(0)) {
            require(ethVaultAddress != payable(0), "ETH vault does not exist!");
            ETHVault(ethVaultAddress).withdraw(amount_, receiver_, owner());
        } else {
            require(erc20Vault[asset_] != address(0), "ERC20 vault does not exist!");
            LRC4626(erc20Vault[asset_]).withdraw(amount_, receiver_, owner());
        }
    }

    /**
     * @dev Preview maximum withdrawal amount
     * @param asset_ Asset address
     * @return Maximum withdrawable amount
     */
    function previewWithdraw(
        address asset_
    ) public view returns (uint256) {
        if (asset_ == address(0)) {
            if (ethVaultAddress == payable(0)) {
                return 0;
            } else {
                return ETHVault(ethVaultAddress).balanceOf(owner());
            }
        } else {
            if (erc20Vault[asset_] == address(0)) {
                return 0;
            } else {
                return LRC4626(erc20Vault[asset_]).maxWithdraw(owner());
            }
        }
    }

    /**
     * @dev Get vault info for an asset
     * @param asset_ Asset address
     * @return assetName Asset name
     * @return assetSymbol Asset symbol
     * @return vaultName Vault name
     * @return vaultSymbol Vault symbol
     * @return vaultAddress Vault contract address
     * @return totalAssets Total assets in vault
     */
    function getVaultInfo(
        address asset_
    )
        external
        view
        returns (
            string memory assetName,
            string memory assetSymbol,
            string memory vaultName,
            string memory vaultSymbol,
            address vaultAddress,
            uint256 totalAssets
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
                LRC20(asset_).name(),
                LRC20(asset_).symbol(),
                LRC4626(erc20Vault[asset_]).name(),
                LRC4626(erc20Vault[asset_]).symbol(),
                erc20Vault[asset_],
                LRC4626(erc20Vault[asset_]).totalAssets()
            );
        }
    }

    /**
     * @dev Get all registered assets
     * @return Array of asset addresses
     */
    function getAssets() external view returns (address[] memory) {
        return assets;
    }

    receive() external payable {}
}
