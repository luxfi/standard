// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

interface IGMT {
    function beginMigration() external;
    function endMigration() external;
}
