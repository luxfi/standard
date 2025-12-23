// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IGMT {
    function beginMigration() external;
    function endMigration() external;
}
