// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Options } from "./Options.sol";
import { OptionsVault } from "./OptionsVault.sol";
import { IOptionsRouter } from "../interfaces/options/IOptionsRouter.sol";

/**
 * @title OptionsRouter
 * @author Lux Industries
 * @notice Atomic multi-leg options strategy execution
 * @dev Validates and executes 2-4 leg strategies against an Options contract.
 *      Computes aggregate margin using spread margin logic from OptionsVault.
 *      All legs execute atomically — if any leg fails, the entire tx reverts.
 *
 * Supported strategies:
 * - VERTICAL_SPREAD: 2 legs, same type, same expiry, different strikes
 * - IRON_CONDOR: 4 legs = bull put spread + bear call spread
 * - BUTTERFLY: 3-4 legs, 3 strikes (buy low, sell 2x middle, buy high)
 * - STRADDLE: 2 legs, same strike, one call + one put
 * - STRANGLE: 2 legs, different strikes, one call + one put
 * - COLLAR: 2 legs, long put + short call (or vice versa)
 * - CALENDAR_SPREAD: 2 legs, same strike, different expiries
 * - IRON_BUTTERFLY: 4 legs, straddle at middle + wings
 * - CUSTOM: 2-4 legs, no structural validation
 */
contract OptionsRouter is IOptionsRouter, ReentrancyGuard, AccessControl, Pausable {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant PRECISION = 1e18;

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Options contract this router interacts with
    Options public immutable options;

    /// @notice Optional vault for spread margin (can be address(0))
    OptionsVault public vault;

    /// @notice Strategy positions
    mapping(uint256 => StrategyPosition) private _positions;

    /// @notice Legs stored per position (positionId => index => Leg)
    mapping(uint256 => mapping(uint256 => Leg)) private _positionLegs;

    /// @notice Leg count per position
    mapping(uint256 => uint256) private _positionLegCount;

    /// @notice Next position ID
    uint256 public nextPositionId = 1;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _options, address _vault, address _admin) {
        if (_options == address(0) || _admin == address(0)) revert NoLegs(); // reuse error for zero check
        options = Options(_options);
        if (_vault != address(0)) {
            vault = OptionsVault(_vault);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STRATEGY EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOptionsRouter
    function executeStrategy(
        StrategyType strategyType,
        Leg[] calldata legs,
        uint256 netPremiumLimit
    ) external nonReentrant whenNotPaused returns (uint256 positionId) {
        // Validate structure
        if (legs.length == 0) revert NoLegs();
        if (legs.length > 4) revert TooManyLegs();

        if (strategyType != StrategyType.CUSTOM) {
            (bool valid,) = _validateStrategy(strategyType, legs);
            if (!valid) revert InvalidLegCount(); // generic revert for validation failure
        }

        positionId = nextPositionId++;

        // Validate packed leg storage limits (BUG 6: silent truncation prevention)
        for (uint256 i; i < legs.length; ++i) {
            require(legs[i].seriesId <= type(uint16).max, "seriesId exceeds uint16");
            require(legs[i].quantity <= 0x7FFFFFFFFFFF, "quantity exceeds 47-bit limit");
        }

        // Compute spread margin reduction if vault is configured and strategy is a spread
        uint256 spreadReduction;
        if (address(vault) != address(0) && _isSpreadStrategy(strategyType, legs)) {
            spreadReduction = _computeSpreadReduction(strategyType, legs);
        }

        // Execute each leg atomically
        uint256 totalCollateralLocked;
        for (uint256 i; i < legs.length; ++i) {
            Leg calldata leg = legs[i];
            if (leg.quantity == 0) revert ZeroQuantity();

            _positionLegs[positionId][i] = leg;

            if (leg.isBuy) {
                // Buy: transfer existing option tokens to this contract
                // Caller must hold or purchase option tokens
                // If caller has tokens, transfer them in. Otherwise write new ones.
                uint256 balance = options.balanceOf(msg.sender, leg.seriesId);
                if (balance >= leg.quantity) {
                    // Transfer existing tokens
                    options.safeTransferFrom(msg.sender, address(this), leg.seriesId, leg.quantity, "");
                }
                // If caller doesn't have tokens, they need to acquire them separately
                // The router focuses on collateral management and position tracking
            } else {
                // Sell (write): caller provides collateral, router writes options
                uint256 collateral = options.calculateCollateral(leg.seriesId, leg.quantity);

                Options.OptionSeries memory series = options.getSeries(leg.seriesId);
                address collateralToken = series.optionType == Options.OptionType.CALL
                    ? series.underlying
                    : series.quote;

                // Apply spread margin reduction: only require (collateral - reduction) from caller
                uint256 effectiveCollateral = collateral;
                if (spreadReduction > 0 && spreadReduction < collateral) {
                    effectiveCollateral = collateral - spreadReduction;
                    spreadReduction = 0; // Only apply once to the short leg
                }

                // Pull collateral from caller
                IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), effectiveCollateral);

                // Approve Options contract for full amount (we send what we have)
                IERC20(collateralToken).approve(address(options), effectiveCollateral);

                // Write options — tokens go to this contract (held for position)
                uint256 actualCollateral = options.write(leg.seriesId, leg.quantity, address(this));
                totalCollateralLocked += actualCollateral;
            }
        }

        _positionLegCount[positionId] = legs.length;

        // Pack legs into single uint256 for gas-efficient storage
        // Pack: each leg = 64 bits (16 bits seriesId + 1 bit direction + 47 bits quantity)
        uint256 packed;
        for (uint256 i; i < legs.length; ++i) {
            uint256 legBits = (legs[i].seriesId & 0xFFFF) << 48;
            legBits |= (legs[i].isBuy ? uint256(1) : uint256(0)) << 47;
            legBits |= legs[i].quantity & 0x7FFFFFFFFFFF;
            packed |= legBits << (i * 64);
        }

        _positions[positionId] = StrategyPosition({
            owner: msg.sender,
            strategyType: strategyType,
            packedLegs: packed,
            quantity: legs[0].quantity,
            collateralLocked: totalCollateralLocked,
            active: true
        });

        emit StrategyExecuted(positionId, msg.sender, strategyType, legs[0].quantity, totalCollateralLocked);
    }

    /// @inheritdoc IOptionsRouter
    function closeStrategy(uint256 positionId) external nonReentrant {
        StrategyPosition storage pos = _positions[positionId];
        if (!pos.active) revert PositionNotFound();
        if (pos.owner != msg.sender) revert NotPositionOwner();

        uint256 legCount = _positionLegCount[positionId];
        for (uint256 i; i < legCount; ++i) {
            Leg storage leg = _positionLegs[positionId][i];

            if (leg.isBuy) {
                // Return bought option tokens to owner
                uint256 balance = options.balanceOf(address(this), leg.seriesId);
                if (balance > 0) {
                    uint256 toReturn = balance > leg.quantity ? leg.quantity : balance;
                    options.safeTransferFrom(address(this), msg.sender, leg.seriesId, toReturn, "");
                }
            } else {
                // Burn written options to release collateral
                uint256 balance = options.balanceOf(address(this), leg.seriesId);
                if (balance > 0) {
                    uint256 toBurn = balance > leg.quantity ? leg.quantity : balance;
                    options.burn(leg.seriesId, toBurn);
                }
            }
        }

        pos.active = false;

        emit StrategyClosed(positionId, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @inheritdoc IOptionsRouter
    function validateStrategy(
        StrategyType strategyType,
        Leg[] calldata legs
    ) external view returns (bool valid, string memory reason) {
        return _validateStrategy(strategyType, legs);
    }

    /// @inheritdoc IOptionsRouter
    function computeMaxLoss(
        StrategyType strategyType,
        Leg[] calldata legs
    ) external view returns (uint256 maxLoss) {
        if (legs.length == 0) return 0;

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);

        if (strategyType == StrategyType.VERTICAL_SPREAD && legs.length == 2) {
            return _computeVerticalMaxLoss(legs, s0);
        }

        if (strategyType == StrategyType.IRON_CONDOR && legs.length == 4) {
            return _computeIronCondorMaxLoss(legs);
        }

        if (strategyType == StrategyType.STRADDLE || strategyType == StrategyType.STRANGLE) {
            // For long straddle/strangle, max loss = total premium paid
            // For short, max loss = unlimited (return max uint)
            bool isLong = legs[0].isBuy && legs[1].isBuy;
            if (isLong) {
                return legs[0].maxPremium + legs[1].maxPremium;
            }
            return type(uint256).max;
        }

        if (strategyType == StrategyType.BUTTERFLY && legs.length >= 3) {
            return _computeButterflyMaxLoss(legs);
        }

        // For CUSTOM and others, sum all collateral requirements for short legs
        for (uint256 i; i < legs.length; ++i) {
            if (!legs[i].isBuy) {
                maxLoss += options.calculateCollateral(legs[i].seriesId, legs[i].quantity);
            }
        }
    }

    /// @inheritdoc IOptionsRouter
    function computeMaxGain(
        StrategyType strategyType,
        Leg[] calldata legs
    ) external view returns (uint256 maxGain) {
        if (legs.length == 0) return 0;

        if (strategyType == StrategyType.VERTICAL_SPREAD && legs.length == 2) {
            Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
            Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);
            uint256 strikeDiff = s0.strikePrice > s1.strikePrice
                ? s0.strikePrice - s1.strikePrice
                : s1.strikePrice - s0.strikePrice;
            uint8 dec = options.tokenDecimals(s0.underlying);
            return (legs[0].quantity * strikeDiff) / (10 ** dec);
        }

        if (strategyType == StrategyType.STRADDLE || strategyType == StrategyType.STRANGLE) {
            bool isShort = !legs[0].isBuy && !legs[1].isBuy;
            if (isShort) {
                return legs[0].maxPremium + legs[1].maxPremium;
            }
            return type(uint256).max; // Long straddle/strangle: unlimited upside
        }

        // Default: sum of all premiums received on short legs
        for (uint256 i; i < legs.length; ++i) {
            if (!legs[i].isBuy) {
                maxGain += legs[i].maxPremium;
            }
        }
    }

    /// @inheritdoc IOptionsRouter
    function computeBreakeven(
        StrategyType strategyType,
        Leg[] calldata legs
    ) external view returns (uint256 breakevenLow, uint256 breakevenHigh) {
        if (legs.length < 2) return (0, 0);

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        if (strategyType == StrategyType.STRADDLE) {
            // Long straddle: breakeven = strike +/- total premium
            uint256 totalPremium = legs[0].maxPremium + legs[1].maxPremium;
            breakevenLow = s0.strikePrice > totalPremium ? s0.strikePrice - totalPremium : 0;
            breakevenHigh = s0.strikePrice + totalPremium;
        } else if (strategyType == StrategyType.STRANGLE) {
            // Long strangle: low breakeven = put strike - premium, high = call strike + premium
            uint256 putStrike;
            uint256 callStrike;
            uint256 totalPremium = legs[0].maxPremium + legs[1].maxPremium;

            if (s0.optionType == Options.OptionType.PUT) {
                putStrike = s0.strikePrice;
                callStrike = s1.strikePrice;
            } else {
                callStrike = s0.strikePrice;
                putStrike = s1.strikePrice;
            }

            breakevenLow = putStrike > totalPremium ? putStrike - totalPremium : 0;
            breakevenHigh = callStrike + totalPremium;
        } else if (strategyType == StrategyType.VERTICAL_SPREAD) {
            // Vertical: breakeven = lower strike + net premium (for call spread)
            uint256 lowStrike = s0.strikePrice < s1.strikePrice ? s0.strikePrice : s1.strikePrice;
            uint256 netPremium = legs[0].maxPremium > legs[1].maxPremium
                ? legs[0].maxPremium - legs[1].maxPremium
                : legs[1].maxPremium - legs[0].maxPremium;
            breakevenLow = lowStrike + netPremium;
        }
    }

    /// @inheritdoc IOptionsRouter
    function getPosition(uint256 positionId) external view returns (StrategyPosition memory) {
        return _positions[positionId];
    }

    /**
     * @notice Get legs for a position
     * @param positionId Position ID
     * @return legs Array of legs
     */
    function getPositionLegs(uint256 positionId) external view returns (Leg[] memory legs) {
        uint256 count = _positionLegCount[positionId];
        legs = new Leg[](count);
        for (uint256 i; i < count; ++i) {
            legs[i] = _positionLegs[positionId][i];
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC1155 RECEIVER
    // ═══════════════════════════════════════════════════════════════════════

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set the vault address
     * @param _vault New vault address (address(0) to disable)
     */
    function setVault(address _vault) external onlyRole(ADMIN_ROLE) {
        vault = OptionsVault(_vault);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL: SPREAD MARGIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Returns true if the strategy type is a spread that qualifies for margin reduction
    function _isSpreadStrategy(StrategyType t, Leg[] calldata legs) internal pure returns (bool) {
        if (legs.length != 2) return false;
        // Vertical spread or collar: one buy, one sell
        return (t == StrategyType.VERTICAL_SPREAD || t == StrategyType.COLLAR)
            && (legs[0].isBuy != legs[1].isBuy);
    }

    /// @dev Compute spread margin reduction via vault.calculateSpreadMargin
    function _computeSpreadReduction(StrategyType, Leg[] calldata legs) internal view returns (uint256) {
        // Identify which leg is short and which is long
        uint256 shortIdx = legs[0].isBuy ? 1 : 0;
        uint256 longIdx = legs[0].isBuy ? 0 : 1;

        return vault.calculateSpreadMargin(
            msg.sender,
            legs[shortIdx].seriesId,
            legs[longIdx].seriesId,
            legs[shortIdx].quantity
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    function _validateStrategy(
        StrategyType strategyType,
        Leg[] calldata legs
    ) internal view returns (bool, string memory) {
        if (legs.length == 0) return (false, "No legs");
        if (legs.length > 4) return (false, "Too many legs");

        // Check all quantities non-zero
        for (uint256 i; i < legs.length; ++i) {
            if (legs[i].quantity == 0) return (false, "Zero quantity");
        }

        if (strategyType == StrategyType.VERTICAL_SPREAD) {
            return _validateVerticalSpread(legs);
        } else if (strategyType == StrategyType.IRON_CONDOR) {
            return _validateIronCondor(legs);
        } else if (strategyType == StrategyType.BUTTERFLY) {
            return _validateButterfly(legs);
        } else if (strategyType == StrategyType.STRADDLE) {
            return _validateStraddle(legs);
        } else if (strategyType == StrategyType.STRANGLE) {
            return _validateStrangle(legs);
        } else if (strategyType == StrategyType.COLLAR) {
            return _validateCollar(legs);
        } else if (strategyType == StrategyType.CALENDAR_SPREAD) {
            return _validateCalendarSpread(legs);
        } else if (strategyType == StrategyType.IRON_BUTTERFLY) {
            return _validateIronButterfly(legs);
        } else {
            // CUSTOM: no structural validation
            return (true, "");
        }
    }

    function _validateVerticalSpread(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 2) return (false, "Vertical spread requires 2 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        if (!s0.exists || !s1.exists) return (false, "Series not found");
        if (s0.underlying != s1.underlying) return (false, "Underlying mismatch");
        if (s0.expiry != s1.expiry) return (false, "Expiry mismatch");
        if (s0.optionType != s1.optionType) return (false, "Must be same type");
        if (s0.strikePrice == s1.strikePrice) return (false, "Strikes must differ");
        if (legs[0].isBuy == legs[1].isBuy) return (false, "One buy, one sell required");

        return (true, "");
    }

    function _validateIronCondor(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 4) return (false, "Iron condor requires 4 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);
        Options.OptionSeries memory s2 = options.getSeries(legs[2].seriesId);
        Options.OptionSeries memory s3 = options.getSeries(legs[3].seriesId);

        if (!s0.exists || !s1.exists || !s2.exists || !s3.exists) return (false, "Series not found");

        // All same underlying, same expiry
        if (s0.underlying != s1.underlying || s0.underlying != s2.underlying || s0.underlying != s3.underlying) {
            return (false, "Underlying mismatch");
        }
        if (s0.expiry != s1.expiry || s0.expiry != s2.expiry || s0.expiry != s3.expiry) {
            return (false, "Expiry mismatch");
        }

        // Need 2 puts and 2 calls
        uint256 putCount;
        uint256 callCount;
        for (uint256 i; i < 4; ++i) {
            Options.OptionSeries memory s = options.getSeries(legs[i].seriesId);
            if (s.optionType == Options.OptionType.PUT) putCount++;
            else callCount++;
        }
        if (putCount != 2 || callCount != 2) return (false, "Need 2 puts and 2 calls");

        return (true, "");
    }

    function _validateButterfly(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length < 3 || legs.length > 4) return (false, "Butterfly requires 3-4 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        if (!s0.exists) return (false, "Series not found");

        for (uint256 i = 1; i < legs.length; ++i) {
            Options.OptionSeries memory si = options.getSeries(legs[i].seriesId);
            if (!si.exists) return (false, "Series not found");
            if (si.underlying != s0.underlying) return (false, "Underlying mismatch");
            if (si.expiry != s0.expiry) return (false, "Expiry mismatch");
        }

        return (true, "");
    }

    function _validateStraddle(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 2) return (false, "Straddle requires 2 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        if (!s0.exists || !s1.exists) return (false, "Series not found");
        if (s0.underlying != s1.underlying) return (false, "Underlying mismatch");
        if (s0.expiry != s1.expiry) return (false, "Expiry mismatch");
        if (s0.strikePrice != s1.strikePrice) return (false, "Straddle requires same strike");
        if (s0.optionType == s1.optionType) return (false, "Need one call and one put");
        if (legs[0].isBuy != legs[1].isBuy) return (false, "Both legs same direction");

        return (true, "");
    }

    function _validateStrangle(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 2) return (false, "Strangle requires 2 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        if (!s0.exists || !s1.exists) return (false, "Series not found");
        if (s0.underlying != s1.underlying) return (false, "Underlying mismatch");
        if (s0.expiry != s1.expiry) return (false, "Expiry mismatch");
        if (s0.strikePrice == s1.strikePrice) return (false, "Strangle requires different strikes");
        if (s0.optionType == s1.optionType) return (false, "Need one call and one put");
        if (legs[0].isBuy != legs[1].isBuy) return (false, "Both legs same direction");

        return (true, "");
    }

    function _validateCollar(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 2) return (false, "Collar requires 2 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        if (!s0.exists || !s1.exists) return (false, "Series not found");
        if (s0.underlying != s1.underlying) return (false, "Underlying mismatch");
        if (s0.optionType == s1.optionType) return (false, "Need one call and one put");
        if (legs[0].isBuy == legs[1].isBuy) return (false, "One buy, one sell required");

        return (true, "");
    }

    function _validateCalendarSpread(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 2) return (false, "Calendar spread requires 2 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        if (!s0.exists || !s1.exists) return (false, "Series not found");
        if (s0.underlying != s1.underlying) return (false, "Underlying mismatch");
        if (s0.strikePrice != s1.strikePrice) return (false, "Calendar requires same strike");
        if (s0.optionType != s1.optionType) return (false, "Calendar requires same type");
        if (s0.expiry == s1.expiry) return (false, "Calendar requires different expiries");
        if (legs[0].isBuy == legs[1].isBuy) return (false, "One buy, one sell required");

        return (true, "");
    }

    function _validateIronButterfly(Leg[] calldata legs) internal view returns (bool, string memory) {
        if (legs.length != 4) return (false, "Iron butterfly requires 4 legs");

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        if (!s0.exists) return (false, "Series not found");

        for (uint256 i = 1; i < 4; ++i) {
            Options.OptionSeries memory si = options.getSeries(legs[i].seriesId);
            if (!si.exists) return (false, "Series not found");
            if (si.underlying != s0.underlying) return (false, "Underlying mismatch");
            if (si.expiry != s0.expiry) return (false, "Expiry mismatch");
        }

        // Need 2 puts and 2 calls
        uint256 putCount;
        uint256 callCount;
        for (uint256 i; i < 4; ++i) {
            Options.OptionSeries memory s = options.getSeries(legs[i].seriesId);
            if (s.optionType == Options.OptionType.PUT) putCount++;
            else callCount++;
        }
        if (putCount != 2 || callCount != 2) return (false, "Need 2 puts and 2 calls");

        return (true, "");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL MAX-LOSS COMPUTATION
    // ═══════════════════════════════════════════════════════════════════════

    function _computeVerticalMaxLoss(
        Leg[] calldata legs,
        Options.OptionSeries memory s0
    ) internal view returns (uint256) {
        Options.OptionSeries memory s1 = options.getSeries(legs[1].seriesId);

        uint256 strikeDiff = s0.strikePrice > s1.strikePrice
            ? s0.strikePrice - s1.strikePrice
            : s1.strikePrice - s0.strikePrice;

        uint8 dec = options.tokenDecimals(s0.underlying);
        return (legs[0].quantity * strikeDiff) / (10 ** dec);
    }

    function _computeIronCondorMaxLoss(Leg[] calldata legs) internal view returns (uint256) {
        // Max loss = wider of the two spreads * quantity
        // Find put spread width and call spread width, take the larger
        uint256 maxWidth;

        for (uint256 i; i < legs.length; ++i) {
            for (uint256 j = i + 1; j < legs.length; ++j) {
                Options.OptionSeries memory si = options.getSeries(legs[i].seriesId);
                Options.OptionSeries memory sj = options.getSeries(legs[j].seriesId);

                if (si.optionType == sj.optionType) {
                    uint256 diff = si.strikePrice > sj.strikePrice
                        ? si.strikePrice - sj.strikePrice
                        : sj.strikePrice - si.strikePrice;
                    if (diff > maxWidth) maxWidth = diff;
                }
            }
        }

        Options.OptionSeries memory s0 = options.getSeries(legs[0].seriesId);
        uint8 dec = options.tokenDecimals(s0.underlying);
        return (legs[0].quantity * maxWidth) / (10 ** dec);
    }

    function _computeButterflyMaxLoss(Leg[] calldata legs) internal view returns (uint256) {
        // Butterfly max loss = net premium paid (for long butterfly)
        // Approximated as the sum of buy premiums - sum of sell premiums
        uint256 totalBuyPremium;
        uint256 totalSellPremium;

        for (uint256 i; i < legs.length; ++i) {
            if (legs[i].isBuy) {
                totalBuyPremium += legs[i].maxPremium;
            } else {
                totalSellPremium += legs[i].maxPremium;
            }
        }

        return totalBuyPremium > totalSellPremium ? totalBuyPremium - totalSellPremium : 0;
    }
}
