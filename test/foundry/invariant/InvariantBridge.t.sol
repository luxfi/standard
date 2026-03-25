// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BridgedETH} from "../../../contracts/bridge/collateral/ETH.sol";

contract MockBridgeToken is ERC20 {
    address public admin;
    constructor() ERC20("Bridged ETH", "LETH") {
        admin = msg.sender;
    }
    function mint(address to, uint256 amount) external {
        require(msg.sender == admin, "Only admin");
        _mint(to, amount);
    }
    function burn(address from, uint256 amount) external {
        require(msg.sender == admin, "Only admin");
        _burn(from, amount);
    }
}

contract BridgeHandler is Test {
    MockBridgeToken public token;
    address[] public users;
    uint256 public totalBridgedIn;
    uint256 public totalBridgedOut;

    constructor(MockBridgeToken _token) {
        token = _token;
        for (uint256 i = 0; i < 5; i++) {
            users.push(address(uint160(0x3000 + i)));
        }
    }

    function bridgeIn(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        amount = bound(amount, 0.01e18, 1000e18);
        token.mint(user, amount);
        totalBridgedIn += amount;
    }

    function bridgeOut(uint256 userSeed, uint256 amount) external {
        address user = users[userSeed % users.length];
        uint256 bal = token.balanceOf(user);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        token.burn(user, amount);
        totalBridgedOut += amount;
    }
}

contract InvariantBridgeTest is Test {
    MockBridgeToken public token;
    BridgeHandler public handler;

    function setUp() public {
        token = new MockBridgeToken();
        handler = new BridgeHandler(token);

        targetContract(address(handler));
    }

    /// @notice totalSupply == totalBridgedIn - totalBridgedOut
    function invariant_supplyMatchesBridgeFlows() public view {
        assertEq(
            token.totalSupply(),
            handler.totalBridgedIn() - handler.totalBridgedOut(),
            "Supply != net bridge flows"
        );
    }

    /// @notice No user can have more than totalSupply
    function invariant_noUserExceedsSupply() public view {
        for (uint256 i = 0; i < 5; i++) {
            assertLe(
                token.balanceOf(address(uint160(0x3000 + i))),
                token.totalSupply(),
                "User > supply"
            );
        }
    }
}
