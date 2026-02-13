// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20, SafeERC20} from "@luxfi/standard/tokens/ERC20.sol";
import {Ownable} from "@luxfi/standard/access/Access.sol";
import {ReentrancyGuard} from "@luxfi/standard/utils/Utils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Bond
 * @author Lux Industries Inc
 * @notice Bond issuance for DAO treasury funding
 * @dev Allows DAOs to sell Identity tokens at a discount for capital
 *
 * How it works:
 * 1. DAO issues a bond: "Buy SECURITY tokens at 20% discount"
 * 2. User pays 100 USDC → DAO's Safe (marked as BONDED)
 * 3. User receives 125 SECURITY tokens (vesting over 6 months)
 * 4. User can now vote in DAO governance
 * 5. Bonded funds CANNOT be recalled by parent DAO
 *
 * Key principle: Community sovereignty - people who buy in keep their stake
 */
/// @notice Interface for minting Identity tokens
interface IMintable {
    function mint(address to, uint256 amount) external;
}

contract Bond is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Identity token being sold
    IERC20 public immutable identityToken;

    /// @notice Treasury Safe that receives bond payments
    address public immutable treasury;

    /// @notice Bond configuration
    struct BondConfig {
        address paymentToken;      // USDC, ETH wrapper, parent token, etc.
        uint256 targetRaise;       // Total amount to raise
        uint256 tokensToMint;      // Identity tokens to distribute
        uint256 discount;          // Discount in basis points (2000 = 20%)
        uint256 vestingPeriod;     // Vesting duration in seconds
        uint256 startTime;         // When bond opens
        uint256 endTime;           // When bond closes
        uint256 minPurchase;       // Minimum purchase amount
        uint256 maxPurchase;       // Maximum purchase per address
        bool active;               // Whether bond is active
    }

    /// @notice User's bond purchase
    struct Purchase {
        uint256 bondId;
        uint256 paymentAmount;
        uint256 tokensOwed;
        uint256 tokensClaimed;
        uint256 vestingStart;
        uint256 vestingEnd;
    }

    /// @notice Bond configurations
    mapping(uint256 => BondConfig) public bonds;

    /// @notice User purchases per bond
    mapping(uint256 => mapping(address => Purchase)) public purchases;

    /// @notice Total raised per bond
    mapping(uint256 => uint256) public totalRaised;

    /// @notice Next bond ID
    uint256 public nextBondId;

    /// @notice Events
    event BondCreated(uint256 indexed bondId, address paymentToken, uint256 targetRaise, uint256 tokensToMint);
    event BondPurchased(uint256 indexed bondId, address indexed buyer, uint256 paymentAmount, uint256 tokensOwed);
    event TokensClaimed(uint256 indexed bondId, address indexed buyer, uint256 amount);
    event BondClosed(uint256 indexed bondId);

    /// @notice Errors
    error BondNotActive();
    error BondExpired();
    error BondNotStarted();
    error AmountTooLow();
    error AmountTooHigh();
    error ExceedsTarget();
    error NothingToClaim();
    error AlreadyPurchased();

    constructor(address identityToken_, address treasury_, address owner_) Ownable(owner_) {
        identityToken = IERC20(identityToken_);
        treasury = treasury_;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BOND MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Create a new bond offering
     * @param config Bond configuration
     * @return bondId The ID of the created bond
     */
    function createBond(BondConfig calldata config) external onlyOwner returns (uint256 bondId) {
        bondId = nextBondId++;
        bonds[bondId] = config;
        bonds[bondId].active = true;

        emit BondCreated(bondId, config.paymentToken, config.targetRaise, config.tokensToMint);
    }

    /**
     * @notice Close a bond (stop accepting purchases)
     * @param bondId Bond to close
     */
    function closeBond(uint256 bondId) external onlyOwner {
        bonds[bondId].active = false;
        emit BondClosed(bondId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PURCHASING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Purchase bonds
     * @param bondId Bond to purchase
     * @param amount Payment token amount
     * @dev H-01 fix: Uses mulDiv to prevent overflow with large parameters
     *      H-07 fix: Allows multiple purchases up to maxPurchase total
     */
    function purchase(uint256 bondId, uint256 amount) external nonReentrant {
        BondConfig storage bond = bonds[bondId];

        if (!bond.active) revert BondNotActive();
        if (block.timestamp < bond.startTime) revert BondNotStarted();
        if (block.timestamp > bond.endTime) revert BondExpired();
        if (amount < bond.minPurchase) revert AmountTooLow();
        if (totalRaised[bondId] + amount > bond.targetRaise) revert ExceedsTarget();

        // H-07 fix: Allow multiple purchases up to maxPurchase total per address
        uint256 existingPurchase = purchases[bondId][msg.sender].paymentAmount;
        uint256 totalUserPurchase = existingPurchase + amount;
        if (totalUserPurchase > bond.maxPurchase) revert AmountTooHigh();

        // H-01 fix: Use mulDiv to prevent overflow with large parameters
        // Calculate tokens with discount: (amount * tokensToMint * (10000 + discount)) / (targetRaise * 10000)
        uint256 discountMultiplier = 10000 + bond.discount;
        uint256 tokensOwed = (amount * discountMultiplier).mulDiv(bond.tokensToMint, bond.targetRaise * 10000);

        // Transfer payment to treasury (marked as BONDED - non-recallable)
        IERC20(bond.paymentToken).safeTransferFrom(msg.sender, treasury, amount);

        // Update or create purchase record
        Purchase storage userPurchase = purchases[bondId][msg.sender];
        if (existingPurchase > 0) {
            // H-07: Append to existing purchase
            userPurchase.paymentAmount = totalUserPurchase;
            userPurchase.tokensOwed += tokensOwed;
            // Keep original vesting schedule
        } else {
            // First purchase - create new record
            userPurchase.bondId = bondId;
            userPurchase.paymentAmount = amount;
            userPurchase.tokensOwed = tokensOwed;
            userPurchase.tokensClaimed = 0;
            userPurchase.vestingStart = block.timestamp;
            userPurchase.vestingEnd = block.timestamp + bond.vestingPeriod;
        }

        totalRaised[bondId] += amount;

        emit BondPurchased(bondId, msg.sender, amount, tokensOwed);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIMING
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim vested tokens
     * @param bondId Bond to claim from
     */
    function claim(uint256 bondId) external nonReentrant {
        Purchase storage userPurchase = purchases[bondId][msg.sender];

        uint256 claimable = _claimable(userPurchase);
        if (claimable == 0) revert NothingToClaim();

        userPurchase.tokensClaimed += claimable;

        // Mint Identity tokens to user
        IMintable(address(identityToken)).mint(msg.sender, claimable);

        emit TokensClaimed(bondId, msg.sender, claimable);
    }

    /**
     * @notice Get claimable amount for a user
     * @param bondId Bond ID
     * @param user User address
     * @return Claimable token amount
     */
    function claimable(uint256 bondId, address user) external view returns (uint256) {
        return _claimable(purchases[bondId][user]);
    }

    function _claimable(Purchase storage userPurchase) internal view returns (uint256) {
        if (userPurchase.tokensOwed == 0) return 0;

        uint256 elapsed = block.timestamp - userPurchase.vestingStart;
        uint256 vestingDuration = userPurchase.vestingEnd - userPurchase.vestingStart;

        uint256 vested;
        if (elapsed >= vestingDuration) {
            vested = userPurchase.tokensOwed;
        } else {
            vested = (userPurchase.tokensOwed * elapsed) / vestingDuration;
        }

        return vested - userPurchase.tokensClaimed;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get bond info
     * @param bondId Bond ID
     * @return config Bond configuration
     */
    function getBond(uint256 bondId) external view returns (BondConfig memory) {
        return bonds[bondId];
    }

    /**
     * @notice Get active bond IDs
     * @return ids Array of active bond IDs
     */
    function getActiveBonds() external view returns (uint256[] memory ids) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextBondId; i++) {
            if (bonds[i].active) count++;
        }

        ids = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < nextBondId; i++) {
            if (bonds[i].active) {
                ids[j++] = i;
            }
        }
    }
}
