// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { IZChainBridge } from "../../../contracts/bridge/v4/IZChainBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IYieldStrategy } from "../../../contracts/staking/IYieldStrategy.sol";

/**
 * @dev Mock P3Q precompile. Returns abi.encode(bool) — `true` if its policy bit
 *      is enabled, else `false`. Used by tests via vm.etch at the P3Q slot.
 */
contract MockP3QPrecompile {
    bool public valid = true;

    /// @dev keccak256("verifyEnvelope(bytes)") selector
    function verifyEnvelope(bytes calldata) external view returns (bool) {
        return valid;
    }

    function setValid(bool v) external {
        valid = v;
    }
}

/**
 * @dev Mock Z-Chain bridge. Tracks calls; returns deterministic acks.
 */
contract MockZChainBridge is IZChainBridge {
    struct MintCall {
        address asset;
        uint256 amount;
        bytes32 commitment;
        bytes32 claimId;
    }

    struct SpendCall {
        bytes32 nullifier;
        address asset;
        uint256 amount;
        bytes zkProof;
    }

    MintCall[] public mints;
    SpendCall[] public spends;
    bool public rejectSpend; // set true to test verify-failure path

    function receiveShieldedMint(address asset, uint256 amount, bytes32 commitment, bytes32 claimId)
        external
        returns (bytes32 ack)
    {
        mints.push(MintCall(asset, amount, commitment, claimId));
        return keccak256(abi.encode("ack-mint", claimId));
    }

    function verifyShieldedSpend(bytes32 nullifier, address asset, uint256 amount, bytes calldata zkProof)
        external
        returns (bytes32 ack)
    {
        require(!rejectSpend, "MockZ: bad proof");
        spends.push(SpendCall(nullifier, asset, amount, zkProof));
        return keccak256(abi.encode("ack-spend", nullifier));
    }

    function setRejectSpend(bool v) external {
        rejectSpend = v;
    }

    function mintsLength() external view returns (uint256) {
        return mints.length;
    }

    function spendsLength() external view returns (uint256) {
        return spends.length;
    }
}

/**
 * @dev Mock yield strategy. Tracks deployed external balance; harvest() pretends
 *      to earn `yieldPerHarvest` of the L token and transfers it to the vault.
 */
contract MockYieldStrategy is IYieldStrategy {
    address public immutable lToken;
    address public immutable vault;
    uint256 public deployed;
    uint256 public yieldPerHarvest;

    constructor(address _lToken, address _vault) {
        lToken = _lToken;
        vault = _vault;
    }

    function liquidToken() external view returns (address) {
        return lToken;
    }

    function externalBalance() external view returns (uint256) {
        return deployed;
    }

    /// @dev Test helper — caller drops L into the strategy's "deployed" budget.
    function deployFromVault(uint256 amount) external {
        IERC20(lToken).transferFrom(vault, address(this), amount);
        deployed += amount;
    }

    function setYieldPerHarvest(uint256 v) external {
        yieldPerHarvest = v;
    }

    /// @dev Test helper — mint yield directly to vault (via underlying admin
    ///      role pre-granted in setUp). For the mock we expect the caller to
    ///      have pre-funded the strategy with L tokens equal to yieldPerHarvest.
    function harvest() external returns (uint256 harvested) {
        harvested = yieldPerHarvest;
        if (harvested > 0) {
            IERC20(lToken).transfer(vault, harvested);
        }
    }

    function unwindTo(address to, uint256 amount) external returns (uint256 returned) {
        require(msg.sender == vault, "MockStrat: only vault");
        uint256 bal = IERC20(lToken).balanceOf(address(this));
        returned = amount > bal ? bal : amount;
        require(returned <= deployed, "MockStrat: over-unwind");
        deployed -= returned;
        IERC20(lToken).transfer(to, returned);
    }
}
