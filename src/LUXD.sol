
/*
 ___       ___  ___     ___    ___ ___  ___  ________  ________     
|\  \     |\  \|\  \   |\  \  /  /|\  \|\  \|\   ____\|\   ___ \    
\ \  \    \ \  \\\  \  \ \  \/  / | \  \\\  \ \  \___|\ \  \_|\ \   
 \ \  \    \ \  \\\  \  \ \    / / \ \  \\\  \ \_____  \ \  \ \\ \  
  \ \  \____\ \  \\\  \  /     \/   \ \  \\\  \|____|\  \ \  \_\\ \ 
   \ \_______\ \_______\/  /\   \    \ \_______\____\_\  \ \_______\
    \|_______|\|_______/__/ /\ __\    \|_______|\_________\|_______|
                       |__|/ \|__|             \|_________|         
                                                                    
                                                                    
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20WrappedAsset.sol"; 

contract LuxUSD is ERC20WrappedAsset {

    string public constant _name = 'LuxUSD';
    string public constant _symbol = 'LUSD';

    constructor() ERC20WrappedAsset(_name, _symbol) {}

}

