// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LSSVMPair.sol";

/// @title LSSVMRouter - NFT AMM Router
/// @notice Routes swaps through multiple LSSVM pairs
/// @dev Supports multi-hop swaps and batch operations
contract LSSVMRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Parameters for buying NFTs from a single pair
    struct PairSwapAny {
        LSSVMPair pair;
        uint256 numItems;
    }

    /// @notice Parameters for buying specific NFTs from a single pair
    struct PairSwapSpecific {
        LSSVMPair pair;
        uint256[] nftIds;
    }

    /// @notice Parameters for selling NFTs to a single pair
    struct PairSwapSell {
        LSSVMPair pair;
        uint256[] nftIds;
        uint256 minOutput;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event SwapNFTsForToken(
        address indexed sender,
        uint256 totalOutput,
        uint256 numPairs
    );
    event SwapTokenForNFTs(
        address indexed sender,
        uint256 totalInput,
        uint256 numPairs
    );

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InsufficientOutput();
    error DeadlineExpired();

    // ═══════════════════════════════════════════════════════════════════════
    // BUY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Buy specific NFTs from multiple pairs
    /// @param swapList List of pairs and NFT IDs to buy
    /// @param maxCost Maximum total cost in tokens
    /// @param recipient Address to receive NFTs
    /// @param deadline Transaction deadline
    /// @return totalCost Total amount spent
    function swapTokenForSpecificNFTs(
        PairSwapSpecific[] calldata swapList,
        uint256 maxCost,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 totalCost) {
        if (block.timestamp > deadline) revert DeadlineExpired();

        for (uint256 i = 0; i < swapList.length; i++) {
            PairSwapSpecific calldata swap = swapList[i];
            LSSVMPair pair = swap.pair;

            // Get quote
            (, , uint256 cost, ,) = pair.getBuyNFTQuote(swap.nftIds.length);

            // Execute swap
            uint256 spent = pair.swapTokenForNFTs{value: _isETHPair(pair) ? cost : 0}(
                swap.nftIds,
                cost,
                recipient
            );

            totalCost += spent;
        }

        require(totalCost <= maxCost, "LSSVMRouter: COST_TOO_HIGH");

        // Refund excess ETH
        if (msg.value > totalCost) {
            (bool success,) = msg.sender.call{value: msg.value - totalCost}("");
            require(success, "LSSVMRouter: REFUND_FAILED");
        }

        emit SwapTokenForNFTs(msg.sender, totalCost, swapList.length);
    }

    /// @notice Buy any NFTs from multiple pairs (cheapest first)
    /// @param swapList List of pairs and number of items to buy
    /// @param maxCost Maximum total cost in tokens
    /// @param recipient Address to receive NFTs
    /// @param deadline Transaction deadline
    /// @return totalCost Total amount spent
    function swapTokenForAnyNFTs(
        PairSwapAny[] calldata swapList,
        uint256 maxCost,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 totalCost) {
        if (block.timestamp > deadline) revert DeadlineExpired();

        for (uint256 i = 0; i < swapList.length; i++) {
            PairSwapAny calldata swap = swapList[i];
            LSSVMPair pair = swap.pair;

            // Get available NFT IDs
            uint256[] memory allIds = pair.getAllHeldIds();
            uint256 numToBuy = swap.numItems < allIds.length ? swap.numItems : allIds.length;

            if (numToBuy == 0) continue;

            // Select first N IDs
            uint256[] memory selectedIds = new uint256[](numToBuy);
            for (uint256 j = 0; j < numToBuy; j++) {
                selectedIds[j] = allIds[j];
            }

            // Get quote
            (, , uint256 cost, ,) = pair.getBuyNFTQuote(numToBuy);

            // Execute swap
            uint256 spent = pair.swapTokenForNFTs{value: _isETHPair(pair) ? cost : 0}(
                selectedIds,
                cost,
                recipient
            );

            totalCost += spent;
        }

        require(totalCost <= maxCost, "LSSVMRouter: COST_TOO_HIGH");

        // Refund excess ETH
        if (msg.value > totalCost) {
            (bool success,) = msg.sender.call{value: msg.value - totalCost}("");
            require(success, "LSSVMRouter: REFUND_FAILED");
        }

        emit SwapTokenForNFTs(msg.sender, totalCost, swapList.length);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SELL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Sell NFTs to multiple pairs
    /// @param swapList List of pairs and NFT IDs to sell
    /// @param minTotalOutput Minimum total output in tokens
    /// @param recipient Address to receive tokens
    /// @param deadline Transaction deadline
    /// @return totalOutput Total amount received
    function swapNFTsForToken(
        PairSwapSell[] calldata swapList,
        uint256 minTotalOutput,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 totalOutput) {
        if (block.timestamp > deadline) revert DeadlineExpired();

        for (uint256 i = 0; i < swapList.length; i++) {
            PairSwapSell calldata swap = swapList[i];
            LSSVMPair pair = swap.pair;

            // Transfer NFTs to this contract first
            IERC721 nft = pair.nft();
            for (uint256 j = 0; j < swap.nftIds.length; j++) {
                nft.transferFrom(msg.sender, address(this), swap.nftIds[j]);
                nft.approve(address(pair), swap.nftIds[j]);
            }

            // Execute swap
            uint256 received = pair.swapNFTsForToken(
                swap.nftIds,
                swap.minOutput,
                recipient
            );

            totalOutput += received;
        }

        if (totalOutput < minTotalOutput) revert InsufficientOutput();

        emit SwapNFTsForToken(msg.sender, totalOutput, swapList.length);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Get total cost to buy specific NFTs from multiple pairs
    function getBuyQuote(PairSwapSpecific[] calldata swapList)
        external
        view
        returns (uint256 totalCost)
    {
        for (uint256 i = 0; i < swapList.length; i++) {
            (, , uint256 cost, ,) = swapList[i].pair.getBuyNFTQuote(swapList[i].nftIds.length);
            totalCost += cost;
        }
    }

    /// @notice Get total output for selling NFTs to multiple pairs
    function getSellQuote(PairSwapSell[] calldata swapList)
        external
        view
        returns (uint256 totalOutput)
    {
        for (uint256 i = 0; i < swapList.length; i++) {
            (, , uint256 output, ,) = swapList[i].pair.getSellNFTQuote(swapList[i].nftIds.length);
            totalOutput += output;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _isETHPair(LSSVMPair pair) internal view returns (bool) {
        return pair.token() == address(0);
    }

    // Allow receiving ETH
    receive() external payable {}
}
