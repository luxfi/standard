// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IvLUX {
    function balanceOf(address user) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title GaugeController
 * @notice Manages gauge weights based on vLUX voting
 *
 * GAUGE VOTING:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  vLUX holders vote to allocate weights to gauges               │
 * │                                                                 │
 * │  User voting power = vLUX balance                               │
 * │  User can split votes across multiple gauges                   │
 * │  Weights update weekly (epochs)                                 │
 * │                                                                 │
 * │  Fee distribution follows gauge weights:                        │
 * │  - BurnGauge: 50% weight → 50% of fees burned                   │
 * │  - ValidatorGauge: 30% weight → 30% to validators               │
 * │  - etc.                                                         │
 * └─────────────────────────────────────────────────────────────────┘
 *
 * GAUGES:
 * - BurnGauge: LUX burning (deflationary)
 * - ValidatorGauge: Validator/delegator rewards
 * - DAOGauge: DAO treasury
 * - POLGauge: Protocol owned liquidity
 * - LiquidGauge: Synth protocol rewards
 * - [Custom gauges can be added by governance]
 */
contract GaugeController is ReentrancyGuard, Ownable {
    // ============ Constants ============
    
    uint256 public constant BPS = 10000;
    uint256 public constant WEEK = 7 days;
    uint256 public constant WEIGHT_VOTE_DELAY = 10 days; // Delay between weight changes

    // ============ Types ============
    
    struct Gauge {
        address recipient;      // Address that receives fees
        string name;            // Human readable name
        uint256 gaugeType;      // Type category (0 = protocol, 1 = pool, etc.)
        bool active;            // Can receive votes
    }
    
    struct VoteInfo {
        uint256 weight;         // Weight allocated (BPS)
        uint256 lastVoteTime;   // Last vote timestamp
    }

    // ============ State ============
    
    /// @notice vLUX token for voting power
    IvLUX public immutable vLux;
    
    /// @notice All gauges
    Gauge[] public gauges;
    
    /// @notice Gauge ID by address
    mapping(address => uint256) public gaugeIds;
    
    /// @notice User votes per gauge: user => gaugeId => VoteInfo
    mapping(address => mapping(uint256 => VoteInfo)) public userVotes;
    
    /// @notice Total weight used by user (must be <= BPS)
    mapping(address => uint256) public userTotalWeight;
    
    /// @notice Current gauge weights (updated weekly)
    mapping(uint256 => uint256) public gaugeWeights;
    
    /// @notice Total weight across all gauges
    uint256 public totalWeight;
    
    /// @notice Last weight update timestamp
    uint256 public lastWeightUpdate;
    
    /// @notice Pending weight changes: gaugeId => weight delta
    mapping(uint256 => int256) public pendingWeightChanges;

    // ============ Events ============
    
    event GaugeAdded(uint256 indexed gaugeId, address recipient, string name);
    event GaugeUpdated(uint256 indexed gaugeId, bool active);
    event VoteCast(address indexed user, uint256 indexed gaugeId, uint256 weight);
    event WeightsUpdated(uint256 timestamp);

    // ============ Errors ============
    
    error GaugeNotActive();
    error GaugeNotFound();
    error TooMuchWeight();
    error VoteTooSoon();
    error NoVotingPower();

    // ============ Constructor ============
    
    constructor(address _vLux) Ownable(msg.sender) {
        vLux = IvLUX(_vLux);
        lastWeightUpdate = block.timestamp;
        
        // Add a dummy gauge at index 0 (gaugeIds mapping returns 0 for unknown)
        gauges.push(Gauge({
            recipient: address(0),
            name: "INVALID",
            gaugeType: 0,
            active: false
        }));
    }

    // ============ Admin Functions ============
    
    /// @notice Add a new gauge
    /// @param recipient Address that receives fees
    /// @param name Human readable name
    /// @param gaugeType Category (0=protocol, 1=pool, 2=custom)
    function addGauge(
        address recipient,
        string calldata name,
        uint256 gaugeType
    ) external onlyOwner returns (uint256 gaugeId) {
        gaugeId = gauges.length;
        
        gauges.push(Gauge({
            recipient: recipient,
            name: name,
            gaugeType: gaugeType,
            active: true
        }));
        
        gaugeIds[recipient] = gaugeId;
        
        emit GaugeAdded(gaugeId, recipient, name);
    }
    
    /// @notice Update gauge status
    function setGaugeActive(uint256 gaugeId, bool active) external onlyOwner {
        if (gaugeId >= gauges.length) revert GaugeNotFound();
        gauges[gaugeId].active = active;
        emit GaugeUpdated(gaugeId, active);
    }
    
    /// @notice Update gauge recipient
    function setGaugeRecipient(uint256 gaugeId, address recipient) external onlyOwner {
        if (gaugeId >= gauges.length) revert GaugeNotFound();
        gauges[gaugeId].recipient = recipient;
    }

    // ============ Voting Functions ============
    
    /// @notice Vote for gauge weights
    /// @param gaugeId Gauge to vote for
    /// @param weight Weight in BPS (e.g., 5000 = 50%)
    function vote(uint256 gaugeId, uint256 weight) external nonReentrant {
        if (gaugeId >= gauges.length) revert GaugeNotFound();
        if (!gauges[gaugeId].active) revert GaugeNotActive();
        
        uint256 votingPower = vLux.balanceOf(msg.sender);
        if (votingPower == 0) revert NoVotingPower();
        
        VoteInfo storage userVote = userVotes[msg.sender][gaugeId];
        
        // Check vote delay (prevents rapid weight manipulation)
        if (block.timestamp < userVote.lastVoteTime + WEIGHT_VOTE_DELAY) {
            revert VoteTooSoon();
        }
        
        // Update user's total weight
        uint256 oldWeight = userVote.weight;
        uint256 newTotalWeight = userTotalWeight[msg.sender] - oldWeight + weight;
        
        if (newTotalWeight > BPS) revert TooMuchWeight();
        
        userTotalWeight[msg.sender] = newTotalWeight;
        userVote.weight = weight;
        userVote.lastVoteTime = block.timestamp;
        
        // Queue weight change (applied at next epoch)
        int256 weightDelta = int256(weight * votingPower / BPS) - int256(oldWeight * votingPower / BPS);
        pendingWeightChanges[gaugeId] += weightDelta;
        
        emit VoteCast(msg.sender, gaugeId, weight);
    }
    
    /// @notice Vote for multiple gauges at once
    /// @param gaugeIds_ Array of gauge IDs
    /// @param weights Array of weights (must sum to <= BPS)
    function voteMultiple(uint256[] calldata gaugeIds_, uint256[] calldata weights) external nonReentrant {
        require(gaugeIds_.length == weights.length, "Length mismatch");
        
        uint256 votingPower = vLux.balanceOf(msg.sender);
        if (votingPower == 0) revert NoVotingPower();
        
        uint256 newTotalWeight = 0;
        
        for (uint256 i = 0; i < gaugeIds_.length; i++) {
            uint256 gaugeId = gaugeIds_[i];
            uint256 weight = weights[i];
            
            if (gaugeId >= gauges.length) revert GaugeNotFound();
            if (!gauges[gaugeId].active) revert GaugeNotActive();
            
            VoteInfo storage userVote = userVotes[msg.sender][gaugeId];
            
            // Skip delay check for batch votes (assumes user is doing full reallocation)
            uint256 oldWeight = userVote.weight;
            userVote.weight = weight;
            userVote.lastVoteTime = block.timestamp;
            
            newTotalWeight += weight;
            
            int256 weightDelta = int256(weight * votingPower / BPS) - int256(oldWeight * votingPower / BPS);
            pendingWeightChanges[gaugeId] += weightDelta;
            
            emit VoteCast(msg.sender, gaugeId, weight);
        }
        
        if (newTotalWeight > BPS) revert TooMuchWeight();
        userTotalWeight[msg.sender] = newTotalWeight;
    }
    
    /// @notice Apply pending weight changes (called weekly)
    function updateWeights() external {
        require(block.timestamp >= lastWeightUpdate + WEEK, "Too soon");
        
        uint256 newTotalWeight = 0;
        
        for (uint256 i = 1; i < gauges.length; i++) {
            int256 delta = pendingWeightChanges[i];
            if (delta != 0) {
                if (delta > 0) {
                    gaugeWeights[i] += uint256(delta);
                } else {
                    uint256 decrease = uint256(-delta);
                    if (decrease > gaugeWeights[i]) {
                        gaugeWeights[i] = 0;
                    } else {
                        gaugeWeights[i] -= decrease;
                    }
                }
                pendingWeightChanges[i] = 0;
            }
            newTotalWeight += gaugeWeights[i];
        }
        
        totalWeight = newTotalWeight;
        lastWeightUpdate = block.timestamp;
        
        emit WeightsUpdated(block.timestamp);
    }

    // ============ View Functions ============
    
    /// @notice Get gauge weight in BPS (for fee distribution)
    /// @param gaugeId Gauge ID
    /// @return Weight in BPS (e.g., 5000 = 50%)
    function getGaugeWeightBPS(uint256 gaugeId) external view returns (uint256) {
        if (totalWeight == 0) return 0;
        return (gaugeWeights[gaugeId] * BPS) / totalWeight;
    }
    
    /// @notice Get gauge weight by recipient address
    function getWeightByRecipient(address recipient) external view returns (uint256) {
        uint256 gaugeId = gaugeIds[recipient];
        if (gaugeId == 0) return 0;
        if (totalWeight == 0) return 0;
        return (gaugeWeights[gaugeId] * BPS) / totalWeight;
    }
    
    /// @notice Get all gauge weights
    function getAllWeights() external view returns (uint256[] memory weights) {
        weights = new uint256[](gauges.length);
        for (uint256 i = 0; i < gauges.length; i++) {
            if (totalWeight > 0) {
                weights[i] = (gaugeWeights[i] * BPS) / totalWeight;
            }
        }
    }
    
    /// @notice Get gauge info
    function getGauge(uint256 gaugeId) external view returns (
        address recipient,
        string memory name,
        uint256 gaugeType,
        bool active,
        uint256 weight
    ) {
        Gauge memory g = gauges[gaugeId];
        return (g.recipient, g.name, g.gaugeType, g.active, gaugeWeights[gaugeId]);
    }
    
    /// @notice Get number of gauges
    function gaugeCount() external view returns (uint256) {
        return gauges.length;
    }
    
    /// @notice Get user's vote for a gauge
    function getUserVote(address user, uint256 gaugeId) external view returns (uint256 weight, uint256 lastVoteTime) {
        VoteInfo memory v = userVotes[user][gaugeId];
        return (v.weight, v.lastVoteTime);
    }
}
