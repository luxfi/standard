// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "../IYieldStrategy.sol";

/**
 * @title KarakStrategy
 * @notice Yield strategy for Karak restaking protocol
 * @dev Karak provides universal restaking — any asset can be restaked to
 *      secure Distributed Secure Services (DSS). Supports stETH, wstETH,
 *      USDC, USDT, and other assets.
 *
 *      Teleport integration:
 *      - User bridges ETH/USDC to Lux → receives yLETH/yLUSD on Lux
 *      - Underlying restaked in Karak vaults on Ethereum
 *      - Earns: base staking yield + Karak DSS rewards + KARAK token rewards
 *      - yLETH/yLUSD usable as collateral across Lux DeFi
 *
 *      Key Karak contracts (Ethereum mainnet):
 *      - Core: central coordinator
 *      - Vault: per-asset restaking vault
 *      - DSSManager: manages distributed secure services
 */

interface IKarakCore {
    function depositIntoVault(address vault, uint256 amount, uint256 minSharesOut) external returns (uint256 shares);
    function startRedeem(address vault, uint256 shares) external returns (bytes32 withdrawalKey);
    function finishRedeem(bytes32 withdrawalKey) external;
}

interface IKarakVault {
    function totalAssets() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function asset() external view returns (address);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
}

contract KarakStrategy is IYieldStrategy {
    IKarakCore public immutable core;
    IKarakVault public immutable karakVault;
    address public immutable underlying;
    address public admin;
    bool public active;

    constructor(address _core, address _karakVault, address _underlying) {
        core = IKarakCore(_core);
        karakVault = IKarakVault(_karakVault);
        underlying = _underlying;
        admin = msg.sender;
        active = true;
    }

    function deposit(uint256 amount) external payable override returns (uint256 shares) {
        require(active, "Inactive");
        IERC20(underlying).transferFrom(msg.sender, address(this), amount);
        IERC20(underlying).approve(address(core), amount);
        shares = core.depositIntoVault(address(karakVault), amount, 0);
    }

    function withdraw(uint256 shares) external override returns (uint256 assets) {
        assets = karakVault.convertToAssets(shares);
        bytes32 key = core.startRedeem(address(karakVault), shares);
        // Note: Karak has a withdrawal delay — finishRedeem called after cooldown
        // For bridge: MPC relayer calls finishRedeem after delay
        return assets;
    }

    function totalAssets() external view override returns (uint256) {
        return karakVault.convertToAssets(karakVault.balanceOf(address(this)));
    }

    function currentAPY() external pure override returns (uint256) {
        return 350; // ~3.5% (base + DSS rewards, variable)
    }

    function asset() external view override returns (address) { return underlying; }
    function harvest() external override returns (uint256) { return 0; }
    function isActive() external view override returns (bool) { return active; }
    function name() external pure override returns (string memory) { return "Karak Restaking"; }
    function totalDeposited() external view override returns (uint256) { return 0; }
}

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
