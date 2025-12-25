// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "../contracts/ai/AIToken.sol";

/**
 * @title DeployAI
 * @notice Deploy AI token contracts to C-Chain for testing
 *
 * Usage:
 *   forge script script/DeployAI.s.sol:DeployAI --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc --broadcast
 */
contract DeployAI is Script {
    // Ewoq account - the default funded account on local networks
    address constant EWOQ_ADDRESS = 0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC;

    // Placeholder addresses for testing
    address constant MOCK_WLUX = 0x0000000000000000000000000000000000000001;
    address constant MOCK_WETH = 0x0000000000000000000000000000000000000002;
    address constant MOCK_DEX = 0x0000000000000000000000000000000000000003;
    bytes32 constant MOCK_A_CHAIN_ID = bytes32(uint256(1));

    function run() external {
        // Load private key from environment or use ewoq default
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027)
        );

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying AI contracts...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));

        // Deploy AINative for local testing (no TEE verification)
        AINative aiNative = new AINative();
        console.log("AINative deployed to:", address(aiNative));

        // Deploy AIRemote for C-Chain
        AIRemote aiRemote = new AIRemote(MOCK_A_CHAIN_ID, address(aiNative));
        console.log("AIRemote deployed to:", address(aiRemote));

        // Deploy AIPaymentRouter
        AIPaymentRouter paymentRouter = new AIPaymentRouter(
            MOCK_WLUX,
            MOCK_WETH,
            MOCK_DEX,
            MOCK_A_CHAIN_ID,
            address(aiRemote),
            0.01 ether // 0.01 LUX attestation cost
        );
        console.log("AIPaymentRouter deployed to:", address(paymentRouter));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("AINative:", address(aiNative));
        console.log("AIRemote:", address(aiRemote));
        console.log("AIPaymentRouter:", address(paymentRouter));
    }
}

/**
 * @title DeployAIMiningTest
 * @notice Deploy a simpler AI mining contract for local testing without TEE
 */
contract DeployAIMiningTest is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027)
        );

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying AITestMiner...");

        // Deploy test miner
        AITestMiner miner = new AITestMiner();
        console.log("AITestMiner deployed to:", address(miner));

        vm.stopBroadcast();
    }
}

/**
 * @title AITestMiner
 * @notice Simple test contract for AI mining without TEE verification
 */
contract AITestMiner is ERC20B {
    uint256 public constant REWARD_PER_TASK = 1e18; // 1 AI per task

    mapping(bytes32 => bool) public completedTasks;
    mapping(address => uint256) public minerRewards;

    event TaskSubmitted(bytes32 indexed taskHash, address indexed miner, uint256 reward);

    constructor() ERC20B("AI Test Token", "tAI") {}

    /**
     * @notice Submit a completed compute task and receive AI tokens
     * @param taskHash Hash of the task (from MLX attestation)
     * @param resultHash Hash of the compute result
     * @param computeUnits Number of compute units used
     * @param attestation Attestation from MLX module
     */
    function submitTask(
        bytes32 taskHash,
        bytes32 resultHash,
        uint256 computeUnits,
        bytes calldata attestation
    ) external returns (uint256 reward) {
        require(!completedTasks[taskHash], "Task already completed");
        require(attestation.length >= 32, "Invalid attestation");

        // Mark task as completed
        completedTasks[taskHash] = true;

        // Calculate reward based on compute units
        // Base: 1 AI per 10M compute units
        reward = (computeUnits * REWARD_PER_TASK) / 10_000_000;
        if (reward == 0) reward = REWARD_PER_TASK / 10; // Minimum reward

        // Mint reward to miner
        _mint(msg.sender, reward);
        minerRewards[msg.sender] += reward;

        emit TaskSubmitted(taskHash, msg.sender, reward);
        return reward;
    }

    /**
     * @notice Get miner's total earned rewards
     */
    function getMinerRewards(address miner) external view returns (uint256) {
        return minerRewards[miner];
    }
}
