// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "../IYieldStrategy.sol";

/**
 * @title SymbioticStrategy
 * @notice Yield strategy for Symbiotic restaking protocol
 * @dev Symbiotic provides shared security via restaking — deposit collateral
 *      (stETH, wstETH, cbETH, rETH, etc.) into Symbiotic vaults that secure
 *      external networks and earn operator/network rewards.
 *
 *      Teleport integration:
 *      - User bridges ETH/stETH to Lux → receives yLETH on Lux
 *      - Underlying stETH restaked in Symbiotic on Ethereum
 *      - Earns: Lido staking yield + Symbiotic restaking rewards
 *      - yLETH usable as collateral in LPX Perps, Markets, Alchemix
 *
 *      Key Symbiotic contracts (Ethereum mainnet):
 *      - DefaultCollateral: holds restaked assets
 *      - Vault: manages operator delegations
 *      - NetworkRegistry: registers secured networks
 */

interface ISymbioticVault {
    function deposit(address onBehalfOf, uint256 amount)
        external
        returns (uint256 depositedAmount, uint256 mintedShares);
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares);
    function activeBalanceOf(address account) external view returns (uint256);
    function totalStake() external view returns (uint256);
    function collateral() external view returns (address);
}

interface ISymbioticDefaultCollateral {
    function deposit(address recipient, uint256 amount) external returns (uint256);
    function withdraw(address recipient, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function asset() external view returns (address);
    function totalSupply() external view returns (uint256);
    function limit() external view returns (uint256);
}

contract SymbioticStrategy is IYieldStrategy {
    ISymbioticVault public immutable vault;
    ISymbioticDefaultCollateral public immutable collateral;
    address public immutable underlying; // stETH, wstETH, cbETH, rETH
    address public admin;
    bool public active;

    uint256 private _totalDeposited;

    constructor(address _vault, address _collateral, address _underlying) {
        vault = ISymbioticVault(_vault);
        collateral = ISymbioticDefaultCollateral(_collateral);
        underlying = _underlying;
        admin = msg.sender;
        active = true;
    }

    function deposit(uint256 amount) external payable override returns (uint256 shares) {
        require(active, "Inactive");
        IERC20(underlying).transferFrom(msg.sender, address(this), amount);
        IERC20(underlying).approve(address(collateral), amount);

        // Deposit into Symbiotic default collateral first
        uint256 collateralShares = collateral.deposit(address(this), amount);

        // Then deposit collateral into vault for restaking
        IERC20(address(collateral)).approve(address(vault), collateralShares);
        (uint256 deposited, uint256 vaultShares) = vault.deposit(address(this), collateralShares);

        _totalDeposited += amount;
        return vaultShares;
    }

    function withdraw(uint256 shares) external override returns (uint256 assets) {
        (uint256 burned,) = vault.withdraw(msg.sender, shares);
        collateral.withdraw(msg.sender, burned);
        return burned;
    }

    function totalAssets() external view override returns (uint256) {
        return vault.activeBalanceOf(address(this));
    }

    function currentAPY() external pure override returns (uint256) {
        return 400; // ~4% (Lido base + Symbiotic rewards, variable)
    }

    function asset() external view override returns (address) {
        return underlying;
    }

    function harvest() external override returns (uint256) {
        return 0; // auto-compounds
    }

    function isActive() external view override returns (bool) {
        return active;
    }

    function name() external pure override returns (string memory) {
        return "Symbiotic Restaking";
    }

    function totalDeposited() external view override returns (uint256) {
        return _totalDeposited;
    }
}

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
