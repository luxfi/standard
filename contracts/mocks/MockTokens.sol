// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

import "../tokens/LRC20.sol";

/**
 * @title Mock Tokens for Testing
 * @notice Test versions of Lux ecosystem tokens with public mint
 * @dev NOT FOR PRODUCTION - testing only
 *      Built on LRC20 standard (Lux Request for Comments 20)
 */

/// @notice Mock Lux Dollar for testing
contract MockLUSD is LRC20 {
    constructor() LRC20("Mock Lux Dollar", "LUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @notice Mock Bridged ETH for testing
contract MockLETH is LRC20 {
    constructor() LRC20("Mock Lux ETH", "LETH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @notice Mock Bridged BTC for testing (8 decimals)
contract MockLBTC is LRC20 {
    uint8 private constant _decimals = 8;

    constructor() LRC20("Mock Lux BTC", "LBTC") {}

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @notice Mock Wrapped LUX for testing
contract MockWLUX is LRC20 {
    constructor() LRC20("Mock Wrapped LUX", "WLUX") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /// @notice Wrap native LUX
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @notice Unwrap to native LUX
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/// @notice Mock Bridged SOL for testing (9 decimals)
contract MockLSOL is LRC20 {
    uint8 private constant _decimals = 9;

    constructor() LRC20("Mock Lux SOL", "LSOL") {}

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @notice Mock AI Token for testing
contract MockAI is LRC20 {
    constructor() LRC20("Mock AI Token", "AI") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @notice Mock ZOO Token for testing
contract MockZOO is LRC20 {
    constructor() LRC20("Mock Zoo Token", "ZOO") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
