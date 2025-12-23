
/*
 ___       ___  ___     ___    ___
|\  \     |\  \|\  \   |\  \  /  /|
\ \  \    \ \  \\\  \  \ \  \/  / |
 \ \  \    \ \  \\\  \  \ \    / /
  \ \  \____\ \  \\\  \  /     \/
   \ \_______\ \_______\/  /\   \
    \|_______|\|_______/__/ /\ __\
                       |__|/ \|__|


*/
// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.0;

import "./ERC20B.sol";

contract LUXD is ERC20B {
    string public constant _name = 'Lux Dollar';
    string public constant _symbol = 'LUXD';
    constructor() ERC20B(_name, _symbol) {}
}

