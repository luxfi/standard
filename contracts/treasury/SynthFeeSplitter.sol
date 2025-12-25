// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SynthFeeSplitter
 * @notice Routes SynthVault protocol fees (liquidations, etc.)
 *
 * SYNTH VAULT FEE DISTRIBUTION (IMMUTABLE):
 * ┌────────────────────────────────────────┐
 * │   1%  → Protocol Owned Liquidity (POL) │
 * │   1%  → DAO Treasury                   │
 * │   1%  → sLUX Stakers                   │
 * │  97%  → Vault Reserve (bad debt cover) │
 * └────────────────────────────────────────┘
 *
 * Fees come from:
 * - Liquidation penalties
 * - Protocol fees on minting/repaying
 * - Flash loan fees
 */
contract SynthFeeSplitter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants (IMMUTABLE FOREVER) ============
    
    uint256 public constant BPS = 10000;
    
    /// @notice 1% to Protocol Owned Liquidity
    uint256 public constant POL_BPS = 100;
    
    /// @notice 1% to DAO
    uint256 public constant DAO_BPS = 100;
    
    /// @notice 1% to sLUX stakers
    uint256 public constant STAKER_BPS = 100;
    
    /// @notice 97% to vault reserve
    uint256 public constant RESERVE_BPS = 9700;

    // ============ State ============
    
    IERC20 public immutable lux;
    
    /// @notice Protocol Owned Liquidity
    address public pol;
    
    /// @notice DAO Treasury
    address public daoTreasury;
    
    /// @notice sLUX staking contract
    address public sLux;
    
    /// @notice Vault reserve (for bad debt coverage)
    address public vaultReserve;

    /// @notice Stats
    uint256 public totalReceived;
    uint256 public totalToPOL;
    uint256 public totalToDAO;
    uint256 public totalToStakers;
    uint256 public totalToReserve;

    // ============ Events ============
    
    event FeesReceived(address indexed from, uint256 amount);
    event FeesDistributed(
        uint256 toPOL,
        uint256 toDAO,
        uint256 toStakers,
        uint256 toReserve
    );
    event RecipientUpdated(string recipient, address newAddress);

    // ============ Errors ============
    
    error InvalidAddress();
    error NothingToDistribute();

    // ============ Constructor ============
    
    constructor(
        address _lux,
        address _pol,
        address _daoTreasury,
        address _sLux,
        address _vaultReserve
    ) Ownable(msg.sender) {
        lux = IERC20(_lux);
        pol = _pol;
        daoTreasury = _daoTreasury;
        sLux = _sLux;
        vaultReserve = _vaultReserve;
    }

    // ============ Receive ============
    
    receive() external payable {
        totalReceived += msg.value;
        emit FeesReceived(msg.sender, msg.value);
    }
    
    function depositFees(uint256 amount) external {
        lux.safeTransferFrom(msg.sender, address(this), amount);
        totalReceived += amount;
        emit FeesReceived(msg.sender, amount);
    }

    // ============ Distribution ============
    
    /// @notice Distribute fees according to immutable allocations
    function distribute() external nonReentrant {
        uint256 balance = lux.balanceOf(address(this));
        if (balance == 0) revert NothingToDistribute();
        
        // Calculate amounts
        uint256 toPOL = (balance * POL_BPS) / BPS;
        uint256 toDAO = (balance * DAO_BPS) / BPS;
        uint256 toStakers = (balance * STAKER_BPS) / BPS;
        uint256 toReserve = (balance * RESERVE_BPS) / BPS;
        
        // Execute distributions
        if (toPOL > 0 && pol != address(0)) {
            lux.safeTransfer(pol, toPOL);
            totalToPOL += toPOL;
        }
        
        if (toDAO > 0 && daoTreasury != address(0)) {
            lux.safeTransfer(daoTreasury, toDAO);
            totalToDAO += toDAO;
        }
        
        if (toStakers > 0 && sLux != address(0)) {
            // Send to sLUX for reward distribution
            lux.approve(sLux, toStakers);
            (bool success,) = sLux.call(
                abi.encodeWithSignature("addRewards(uint256)", toStakers)
            );
            if (success) {
                totalToStakers += toStakers;
            }
        }
        
        if (toReserve > 0 && vaultReserve != address(0)) {
            lux.safeTransfer(vaultReserve, toReserve);
            totalToReserve += toReserve;
        }
        
        emit FeesDistributed(toPOL, toDAO, toStakers, toReserve);
    }

    // ============ Admin ============
    
    function setPOL(address _pol) external onlyOwner {
        if (_pol == address(0)) revert InvalidAddress();
        pol = _pol;
        emit RecipientUpdated("pol", _pol);
    }
    
    function setDAOTreasury(address _daoTreasury) external onlyOwner {
        if (_daoTreasury == address(0)) revert InvalidAddress();
        daoTreasury = _daoTreasury;
        emit RecipientUpdated("daoTreasury", _daoTreasury);
    }
    
    function setSLux(address _sLux) external onlyOwner {
        if (_sLux == address(0)) revert InvalidAddress();
        sLux = _sLux;
        emit RecipientUpdated("sLux", _sLux);
    }
    
    function setVaultReserve(address _vaultReserve) external onlyOwner {
        if (_vaultReserve == address(0)) revert InvalidAddress();
        vaultReserve = _vaultReserve;
        emit RecipientUpdated("vaultReserve", _vaultReserve);
    }

    // ============ View ============
    
    function getPendingDistribution() external view returns (
        uint256 balance,
        uint256 toPOL,
        uint256 toDAO,
        uint256 toStakers,
        uint256 toReserve
    ) {
        balance = lux.balanceOf(address(this));
        toPOL = (balance * POL_BPS) / BPS;
        toDAO = (balance * DAO_BPS) / BPS;
        toStakers = (balance * STAKER_BPS) / BPS;
        toReserve = (balance * RESERVE_BPS) / BPS;
    }
}
