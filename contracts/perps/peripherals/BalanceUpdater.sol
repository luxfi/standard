// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import "../core/interfaces/IVault.sol";

contract BalanceUpdater {
    

    function updateBalance(
        address _vault,
        address _token,
        address _lpusd,
        uint256 _lpusdAmount
    ) public {
        IVault vault = IVault(_vault);
        IERC20 token = IERC20(_token);
        uint256 poolAmount = vault.poolAmounts(_token);
        uint256 fee = vault.feeReserves(_token);
        uint256 balance = token.balanceOf(_vault);

        uint256 transferAmount = poolAmount + fee - balance;
        token.transferFrom(msg.sender, _vault, transferAmount);
        IERC20(_lpusd).transferFrom(msg.sender, _vault, _lpusdAmount);

        vault.sellLPUSD(_token, msg.sender);
    }
}
