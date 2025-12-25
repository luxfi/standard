// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IGaugeController {
    function getWeightByRecipient(address recipient) external view returns (uint256);
    function gaugeCount() external view returns (uint256);
    function getGauge(uint256 gaugeId) external view returns (
        address recipient,
        string memory name,
        uint256 gaugeType,
        bool active,
        uint256 weight
    );
}

/**
 * @title FeeSplitter
 * @notice Routes protocol fees based on vLUX gauge voting
 *
 * DAO-GOVERNED FEE DISTRIBUTION:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  vLUX holders vote on gauge weights                             │
 * │  Fees distributed proportionally to gauge weights               │
 * │                                                                 │
 * │  Example current votes:                                         │
 * │  - BurnGauge:      50% → 50% of fees burned                     │
 * │  - ValidatorGauge: 48% → 48% to validators                      │
 * │  - DAOGauge:        1% → 1% to DAO treasury                     │
 * │  - POLGauge:        1% → 1% to protocol liquidity               │
 * │                                                                 │
 * │  Weights can be changed by vLUX voting at any time              │
 * └─────────────────────────────────────────────────────────────────┘
 */
contract FeeSplitter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    uint256 public constant BPS = 10000;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // ============ State ============
    
    IERC20 public immutable lux;
    
    /// @notice GaugeController for weight voting
    IGaugeController public gaugeController;
    
    /// @notice Burn gauge ID
    uint256 public burnGaugeId;
    
    /// @notice Registered recipients (for iteration)
    address[] public recipients;
    mapping(address => bool) public isRecipient;

    /// @notice Stats
    uint256 public totalReceived;
    uint256 public totalDistributed;
    uint256 public totalBurned;
    uint256 public lastDistribution;

    // ============ Events ============
    
    event FeesReceived(address indexed from, uint256 amount);
    event FeesDistributed(uint256 total, uint256 burned);
    event GaugeControllerUpdated(address indexed newController);
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);

    // ============ Errors ============
    
    error InvalidAddress();
    error NothingToDistribute();
    error RecipientExists();
    error RecipientNotFound();

    // ============ Constructor ============
    
    constructor(address _lux) Ownable(msg.sender) {
        lux = IERC20(_lux);
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
    
    /// @notice Distribute fees according to gauge weights
    /// @dev Anyone can call - no access control needed
    function distribute() external nonReentrant {
        uint256 balance = lux.balanceOf(address(this));
        if (balance == 0) revert NothingToDistribute();
        
        uint256 totalSent = 0;
        uint256 burned = 0;
        
        // Get burn weight and burn first
        if (burnGaugeId > 0 && address(gaugeController) != address(0)) {
            uint256 burnWeight = gaugeController.getWeightByRecipient(BURN_ADDRESS);
            if (burnWeight > 0) {
                burned = (balance * burnWeight) / BPS;
                if (burned > 0) {
                    lux.safeTransfer(BURN_ADDRESS, burned);
                    totalBurned += burned;
                    totalSent += burned;
                }
            }
        }
        
        // Distribute to all recipients based on gauge weights
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            if (recipient == BURN_ADDRESS) continue; // Already handled
            
            uint256 weight = gaugeController.getWeightByRecipient(recipient);
            if (weight > 0) {
                uint256 amount = (balance * weight) / BPS;
                if (amount > 0) {
                    lux.safeTransfer(recipient, amount);
                    totalSent += amount;
                }
            }
        }
        
        totalDistributed += totalSent;
        lastDistribution = block.timestamp;
        
        emit FeesDistributed(totalSent, burned);
    }

    // ============ Admin ============
    
    /// @notice Set the GaugeController
    function setGaugeController(address _gaugeController) external onlyOwner {
        if (_gaugeController == address(0)) revert InvalidAddress();
        gaugeController = IGaugeController(_gaugeController);
        emit GaugeControllerUpdated(_gaugeController);
    }
    
    /// @notice Set burn gauge ID
    function setBurnGaugeId(uint256 _burnGaugeId) external onlyOwner {
        burnGaugeId = _burnGaugeId;
    }
    
    /// @notice Add a recipient (must also be registered in GaugeController)
    function addRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidAddress();
        if (isRecipient[recipient]) revert RecipientExists();
        
        recipients.push(recipient);
        isRecipient[recipient] = true;
        
        emit RecipientAdded(recipient);
    }
    
    /// @notice Remove a recipient
    function removeRecipient(address recipient) external onlyOwner {
        if (!isRecipient[recipient]) revert RecipientNotFound();
        
        // Find and remove
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == recipient) {
                recipients[i] = recipients[recipients.length - 1];
                recipients.pop();
                break;
            }
        }
        
        isRecipient[recipient] = false;
        
        emit RecipientRemoved(recipient);
    }

    // ============ View ============
    
    /// @notice Get pending distribution amounts based on current gauge weights
    function getPendingDistribution() external view returns (
        uint256 balance,
        address[] memory addrs,
        uint256[] memory amounts
    ) {
        balance = lux.balanceOf(address(this));
        addrs = new address[](recipients.length + 1); // +1 for burn
        amounts = new uint256[](recipients.length + 1);
        
        // Burn amount
        addrs[0] = BURN_ADDRESS;
        if (burnGaugeId > 0 && address(gaugeController) != address(0)) {
            uint256 burnWeight = gaugeController.getWeightByRecipient(BURN_ADDRESS);
            amounts[0] = (balance * burnWeight) / BPS;
        }
        
        // Recipient amounts
        for (uint256 i = 0; i < recipients.length; i++) {
            addrs[i + 1] = recipients[i];
            if (address(gaugeController) != address(0)) {
                uint256 weight = gaugeController.getWeightByRecipient(recipients[i]);
                amounts[i + 1] = (balance * weight) / BPS;
            }
        }
    }
    
    /// @notice Get total stats
    function getStats() external view returns (
        uint256 received,
        uint256 distributed,
        uint256 burned
    ) {
        return (totalReceived, totalDistributed, totalBurned);
    }
    
    /// @notice Get recipient count
    function recipientCount() external view returns (uint256) {
        return recipients.length;
    }
}
