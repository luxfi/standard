// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import "@luxfi/standard/lib/interfaces/IERC3156FlashLender.sol";
import "@luxfi/standard/lib/interfaces/IERC3156FlashBorrower.sol";

/**
 * @title LRC20FlashMint
 * @author Lux Industries
 * @notice LRC-20 extension for flash minting (LP-3027)
 * @dev Implements EIP-3156 flash loan interface for token minting
 */
abstract contract LRC20FlashMint is ERC20, IERC3156FlashLender {
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /**
     * @notice Error thrown when token is not this contract
     */
    error LRC20FlashMintUnsupportedToken(address token);

    /**
     * @notice Error thrown when amount exceeds max flash loan
     */
    error LRC20FlashMintExceededMaxLoan(uint256 maxLoan);

    /**
     * @notice Error thrown when callback doesn't return success
     */
    error LRC20FlashMintCallbackFailed();

    /**
     * @notice Error thrown when repayment fails
     */
    error LRC20FlashMintRepayFailed();

    /**
     * @notice Returns maximum flash mintable amount
     * @dev Can be overridden to set custom limits
     * @param token Token address (must be this contract)
     * @return Maximum amount that can be flash minted
     */
    function maxFlashLoan(address token) public view virtual override returns (uint256) {
        return token == address(this) ? type(uint256).max - totalSupply() : 0;
    }

    /**
     * @notice Returns flash mint fee
     * @dev Can be overridden to charge fees. Default: 0
     * @param token Token address
     * @param amount Flash mint amount
     * @return Fee amount
     */
    function flashFee(address token, uint256 amount) public view virtual override returns (uint256) {
        if (token != address(this)) {
            revert LRC20FlashMintUnsupportedToken(token);
        }
        return _flashFee(token, amount);
    }

    /**
     * @dev Internal fee calculation. Override to customize.
     * @param token Token address
     * @param amount Flash mint amount
     * @return Fee amount (default: 0)
     */
    function _flashFee(address token, uint256 amount) internal view virtual returns (uint256) {
        // Silence unused variable warnings
        token;
        amount;
        return 0;
    }

    /**
     * @dev Fee receiver address. Override to customize.
     * @return Fee receiver (address(0) = burn fees)
     */
    function _flashFeeReceiver() internal view virtual returns (address) {
        return address(0);
    }

    /**
     * @notice Execute flash mint
     * @param receiver Callback receiver
     * @param token Token to flash mint (must be this contract)
     * @param amount Amount to mint
     * @param data Callback data
     * @return Success boolean
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) public virtual override returns (bool) {
        uint256 maxLoan = maxFlashLoan(token);
        if (amount > maxLoan) {
            revert LRC20FlashMintExceededMaxLoan(maxLoan);
        }

        uint256 fee = flashFee(token, amount);

        // Mint tokens to receiver
        _mint(address(receiver), amount);

        // Execute callback
        if (receiver.onFlashLoan(_msgSender(), token, amount, fee, data) != CALLBACK_SUCCESS) {
            revert LRC20FlashMintCallbackFailed();
        }

        // Collect repayment
        address flashFeeReceiver = _flashFeeReceiver();
        _spendAllowance(address(receiver), address(this), amount + fee);
        _burn(address(receiver), amount);

        if (fee > 0) {
            if (flashFeeReceiver == address(0)) {
                _burn(address(receiver), fee);
            } else {
                _transfer(address(receiver), flashFeeReceiver, fee);
            }
        }

        return true;
    }
}
