// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "./interfaces/ILPUSD.sol";
import "./YieldToken.sol";

contract LPUSD is YieldToken, ILPUSD {

    mapping (address => bool) public vaults;

    modifier onlyVault() {
        require(vaults[msg.sender], "LPUSD: forbidden");
        _;
    }

    constructor(address _vault) public YieldToken("Lux Perps USD", "LPUSD", 0) {
        vaults[_vault] = true;
    }

    function addVault(address _vault) external override onlyGov {
        vaults[_vault] = true;
    }

    function removeVault(address _vault) external override onlyGov {
        vaults[_vault] = false;
    }

    function mint(address _account, uint256 _amount) external override onlyVault {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyVault {
        _burn(_account, _amount);
    }
}
