// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import {GaugeController} from "../../../contracts/governance/GaugeController.sol";
import {DLUX} from "../../../contracts/governance/DLUX.sol";
import {vLUX} from "../../../contracts/governance/vLUX.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWLUXG is ERC20 {
    constructor() ERC20("WLUX", "WLUX") { _mint(msg.sender, 1e27); }
    function mint(address to, uint256 a) external { _mint(to, a); }
}

contract GovHandler is Test {
    GaugeController public gauge;
    address[] public voters;
    uint256 public gaugeCount;

    constructor(GaugeController _gauge, uint256 _gaugeCount) {
        gauge = _gauge;
        gaugeCount = _gaugeCount;
        for (uint256 i = 0; i < 5; i++) {
            voters.push(address(uint160(0x4000 + i)));
        }
    }

    function vote(uint256 voterSeed, uint256 gaugeSeed, uint256 weight) external {
        address voter = voters[voterSeed % voters.length];
        uint256 gaugeId = gaugeSeed % gaugeCount;
        weight = bound(weight, 0, 10000);
        vm.prank(voter);
        try gauge.vote(gaugeId, weight) {} catch {}
    }
}

contract InvariantGovernanceTest is Test {
    GaugeController public gauge;
    DLUX public dlux;
    vLUX public vlux;
    MockWLUXG public wlux;
    GovHandler public handler;

    function setUp() public {
        wlux = new MockWLUXG();
        dlux = new DLUX(address(wlux), address(this), address(this));
        vlux = new vLUX(address(dlux));
        gauge = new GaugeController(address(vlux));

        gauge.addGauge(address(0x5001), "DEX", 0);
        gauge.addGauge(address(0x5002), "Lending", 0);
        gauge.addGauge(address(0x5003), "Perps", 0);

        dlux.grantRole(dlux.MINTER_ROLE(), address(this));
        for (uint256 i = 0; i < 5; i++) {
            address voter = address(uint160(0x4000 + i));
            dlux.mint(voter, 10_000e18, bytes32(0));
        }

        handler = new GovHandler(gauge, 3);
        targetContract(address(handler));
    }

    function invariant_gaugeCountMonotonic() public view {
        assertGe(gauge.gaugeCount(), 3, "Gauges removed");
    }
}
