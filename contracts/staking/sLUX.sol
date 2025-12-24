// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title sLUX - Staked LUX
 * @notice Yield-bearing staked LUX token for Synths protocol
 * @dev Users stake LUX to receive sLUX which accrues staking rewards
 *
 * LUX FEE ARCHITECTURE (differs from Avalanche):
 * ┌─────────────────────────────────────────────────────────────┐
 * │  Tx Fees ──► Protocol Vault ──► DAO Governance              │
 * │                                      │                      │
 * │              ┌───────────────────────┼────────────┐         │
 * │              ▼           ▼           ▼            ▼         │
 * │           Burn %    Stakers %   Delegators %   Dev Fund     │
 * │          (optional)   (sLUX)    (validators)                │
 * └─────────────────────────────────────────────────────────────┘
 *
 * Key differences from Avalanche:
 * - No automatic fee burning (EIP-1559 burn disabled)
 * - All coinbase rewards → Protocol Vault (C-Chain)
 * - DAO governs allocation percentages
 * - sLUX receives yield via addRewards() from Protocol Vault
 *
 * sLUX can be used as collateral in SynthVault to mint xLUX
 */
contract sLUX is ERC20, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The underlying LUX token (WLUX)
    IERC20 public immutable lux;

    /// @notice Total LUX staked (includes rewards)
    uint256 public totalStaked;

    /// @notice Annual percentage yield (basis points, e.g., 1100 = 11%)
    /// @dev This is the TARGET APY - actual yield comes from Protocol Vault distributions
    uint256 public apy = 1100; // 11% default - DAO governed

    /// @notice Last time rewards were distributed
    uint256 public lastRewardTime;

    /// @notice Protocol Vault address (receives all tx fees, distributes to sLUX)
    address public protocolVault;

    /// @notice Pending rewards to be distributed (for simulated yield in testing)
    uint256 public pendingRewards;

    /// @notice Minimum stake amount
    uint256 public constant MIN_STAKE = 1e18; // 1 LUX

    /// @notice Cooldown period for unstaking (seconds)
    uint256 public cooldownPeriod = 7 days;

    /// @notice User cooldown timestamps
    mapping(address => uint256) public cooldownStart;
    mapping(address => uint256) public cooldownAmount;

    // Events
    event Staked(address indexed user, uint256 luxAmount, uint256 sLuxMinted);
    event Unstaked(address indexed user, uint256 sLuxBurned, uint256 luxReturned);
    event CooldownStarted(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 amount);
    event APYUpdated(uint256 newAPY);
    event ProtocolVaultUpdated(address indexed oldVault, address indexed newVault);

    // Errors
    error OnlyProtocolVault();
    error InvalidProtocolVault();

    constructor(address _lux) ERC20("Staked LUX", "sLUX") Ownable(msg.sender) {
        lux = IERC20(_lux);
        lastRewardTime = block.timestamp;
    }

    /// @notice Get the exchange rate of sLUX to LUX
    /// @return Exchange rate scaled by 1e18
    function exchangeRate() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalStaked * 1e18) / supply;
    }

    /// @notice Preview how much sLUX will be minted for a LUX deposit
    function previewDeposit(uint256 luxAmount) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return luxAmount;
        return (luxAmount * supply) / totalStaked;
    }

    /// @notice Preview how much LUX will be returned for sLUX redemption
    function previewRedeem(uint256 sLuxAmount) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return sLuxAmount;
        return (sLuxAmount * totalStaked) / supply;
    }

    /// @notice Stake LUX to receive sLUX
    /// @param luxAmount Amount of LUX to stake
    /// @return sLuxMinted Amount of sLUX minted
    function stake(uint256 luxAmount) external nonReentrant returns (uint256 sLuxMinted) {
        require(luxAmount >= MIN_STAKE, "sLUX: below minimum stake");
        
        // Accrue rewards first
        _accrueRewards();

        // Calculate sLUX to mint
        sLuxMinted = previewDeposit(luxAmount);
        require(sLuxMinted > 0, "sLUX: zero shares");

        // Transfer LUX from user
        lux.safeTransferFrom(msg.sender, address(this), luxAmount);

        // Update state
        totalStaked += luxAmount;
        _mint(msg.sender, sLuxMinted);

        emit Staked(msg.sender, luxAmount, sLuxMinted);
    }

    /// @notice Start cooldown to unstake
    /// @param sLuxAmount Amount of sLUX to unstake
    function startCooldown(uint256 sLuxAmount) external {
        require(balanceOf(msg.sender) >= sLuxAmount, "sLUX: insufficient balance");
        cooldownStart[msg.sender] = block.timestamp;
        cooldownAmount[msg.sender] = sLuxAmount;
        emit CooldownStarted(msg.sender, sLuxAmount);
    }

    /// @notice Unstake sLUX after cooldown to receive LUX
    /// @return luxReturned Amount of LUX returned
    function unstake() external nonReentrant returns (uint256 luxReturned) {
        uint256 sLuxAmount = cooldownAmount[msg.sender];
        require(sLuxAmount > 0, "sLUX: no cooldown active");
        require(block.timestamp >= cooldownStart[msg.sender] + cooldownPeriod, "sLUX: cooldown not complete");
        require(balanceOf(msg.sender) >= sLuxAmount, "sLUX: insufficient balance");

        // Accrue rewards first
        _accrueRewards();

        // Calculate LUX to return
        luxReturned = previewRedeem(sLuxAmount);
        require(luxReturned > 0, "sLUX: zero assets");
        require(luxReturned <= totalStaked, "sLUX: insufficient staked");

        // Clear cooldown
        cooldownStart[msg.sender] = 0;
        cooldownAmount[msg.sender] = 0;

        // Update state
        totalStaked -= luxReturned;
        _burn(msg.sender, sLuxAmount);

        // Transfer LUX to user
        lux.safeTransfer(msg.sender, luxReturned);

        emit Unstaked(msg.sender, sLuxAmount, luxReturned);
    }

    /// @notice Instant unstake with penalty (for testing/emergency)
    /// @param sLuxAmount Amount of sLUX to unstake
    /// @return luxReturned Amount of LUX returned (after 10% penalty)
    function instantUnstake(uint256 sLuxAmount) external nonReentrant returns (uint256 luxReturned) {
        require(balanceOf(msg.sender) >= sLuxAmount, "sLUX: insufficient balance");

        _accrueRewards();

        // Calculate LUX with 10% penalty
        uint256 luxAmount = previewRedeem(sLuxAmount);
        luxReturned = (luxAmount * 90) / 100; // 10% penalty
        require(luxReturned <= totalStaked, "sLUX: insufficient staked");

        // Update state
        totalStaked -= luxReturned;
        _burn(msg.sender, sLuxAmount);

        lux.safeTransfer(msg.sender, luxReturned);

        emit Unstaked(msg.sender, sLuxAmount, luxReturned);
    }

    /// @notice Distribute rewards (called by keeper or anyone)
    function distributeRewards() external {
        _accrueRewards();
    }

    /// @notice Add rewards to the pool (called by Protocol Vault)
    /// @dev In production, only protocolVault can call. For testing, owner can also call.
    /// @param amount Amount of LUX to add as rewards
    function addRewards(uint256 amount) external {
        // Allow protocolVault or owner (for testing/bootstrapping)
        require(
            msg.sender == protocolVault || msg.sender == owner(),
            "sLUX: not authorized"
        );
        lux.safeTransferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
        emit RewardsDistributed(amount);
    }

    /// @notice Set the Protocol Vault address (DAO controlled)
    /// @param newVault Address of the Protocol Vault contract
    function setProtocolVault(address newVault) external onlyOwner {
        if (newVault == address(0)) revert InvalidProtocolVault();
        address oldVault = protocolVault;
        protocolVault = newVault;
        emit ProtocolVaultUpdated(oldVault, newVault);
    }

    /// @notice Set the APY (owner only)
    /// @param newAPY New APY in basis points
    function setAPY(uint256 newAPY) external onlyOwner {
        require(newAPY <= 5000, "sLUX: APY too high"); // Max 50%
        _accrueRewards();
        apy = newAPY;
        emit APYUpdated(newAPY);
    }

    /// @notice Set cooldown period (owner only)
    function setCooldownPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod <= 30 days, "sLUX: cooldown too long");
        cooldownPeriod = newPeriod;
    }

    /// @dev Accrue pending rewards to totalStaked
    /// @notice In production, rewards are added via addRewards() from Protocol Vault.
    function _accrueRewards() internal {
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        // If there are pending rewards, add them to totalStaked
        if (pendingRewards > 0) {
            totalStaked += pendingRewards;
            emit RewardsDistributed(pendingRewards);
            pendingRewards = 0;
        }

        lastRewardTime = block.timestamp;
    }

    /// @notice Queue rewards for drip distribution (called by Protocol Vault)
    /// @param amount Amount of LUX to queue for next accrual
    function queueRewards(uint256 amount) external {
        require(
            msg.sender == protocolVault || msg.sender == owner(),
            "sLUX: not authorized"
        );
        lux.safeTransferFrom(msg.sender, address(this), amount);
        pendingRewards += amount;
    }

    /// @notice Simulate APY yield for testing
    /// @dev For testnet/development only - simulates Protocol Vault distributions
    function simulateYield() external onlyOwner {
        if (totalStaked == 0) return;
        
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        if (timeElapsed == 0) return;

        // Calculate simulated rewards based on target APY
        uint256 rewards = (totalStaked * apy * timeElapsed) / (365 days * 10000);
        
        if (rewards > 0) {
            totalStaked += rewards;
            lastRewardTime = block.timestamp;
            emit RewardsDistributed(rewards);
        }
    }
}
