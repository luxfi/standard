// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { Topics } from "../../contracts/securities/constants/Topics.sol";
import { Offerings } from "../../contracts/securities/constants/Offerings.sol";

/// @dev Validates the canonical six-topic / five-offering constants and the
///      per-offering required-topic mapping.
contract TopicsAndOfferingsTest is Test {
    function test_TopicIds() public pure {
        assertEq(Topics.KYC, 1);
        assertEq(Topics.AML, 2);
        assertEq(Topics.ACCREDITED_VERIFIED, 3);
        assertEq(Topics.ACCREDITED_SELF, 4);
        assertEq(Topics.QIB, 5);
        assertEq(Topics.AFFILIATE, 6);
    }

    function test_OfferingHashes() public pure {
        assertEq(Offerings.RETAIL_PUBLIC, keccak256("RETAIL_PUBLIC"));
        assertEq(Offerings.REG_D_506B, keccak256("REG_D_506B"));
        assertEq(Offerings.REG_D_506C, keccak256("REG_D_506C"));
        assertEq(Offerings.REG_S, keccak256("REG_S"));
        assertEq(Offerings.RULE_144A, keccak256("RULE_144A"));
    }

    function test_RequiredTopics_RetailPublic() public pure {
        uint256[] memory t = Offerings.requiredTopics(Offerings.RETAIL_PUBLIC);
        assertEq(t.length, 2);
        assertEq(t[0], Topics.KYC);
        assertEq(t[1], Topics.AML);
    }

    function test_RequiredTopics_RegS() public pure {
        uint256[] memory t = Offerings.requiredTopics(Offerings.REG_S);
        assertEq(t.length, 2);
        assertEq(t[0], Topics.KYC);
        assertEq(t[1], Topics.AML);
    }

    function test_RequiredTopics_RegD506B() public pure {
        uint256[] memory t = Offerings.requiredTopics(Offerings.REG_D_506B);
        assertEq(t.length, 3);
        assertEq(t[0], Topics.KYC);
        assertEq(t[1], Topics.AML);
        assertEq(t[2], Topics.ACCREDITED_SELF);
    }

    function test_RequiredTopics_RegD506C() public pure {
        uint256[] memory t = Offerings.requiredTopics(Offerings.REG_D_506C);
        assertEq(t.length, 3);
        assertEq(t[0], Topics.KYC);
        assertEq(t[1], Topics.AML);
        assertEq(t[2], Topics.ACCREDITED_VERIFIED);
    }

    function test_RequiredTopics_Rule144A() public pure {
        uint256[] memory t = Offerings.requiredTopics(Offerings.RULE_144A);
        assertEq(t.length, 3);
        assertEq(t[0], Topics.KYC);
        assertEq(t[1], Topics.AML);
        assertEq(t[2], Topics.QIB);
    }

    function test_RequiredTopics_UnknownReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Offerings.UnknownOffering.selector, bytes32("nope")));
        this._call(bytes32("nope"));
    }

    /// @dev External so we can `expectRevert` against a library function.
    function _call(bytes32 offering) external pure returns (uint256) {
        return Offerings.requiredTopics(offering).length;
    }
}
