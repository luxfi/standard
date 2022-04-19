pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract LuxETH is ERC20, Ownable, AccessControl {
    event LogMint(address indexed account, uint amount);
    event LogBurn(address indexed account, uint amount);
    event AdminGranted(address to);
    event AdminRevoked(address to);

    string public constant _name = 'LuxETH';
    string public constant _symbol = 'LETH';

    constructor() ERC20(_name, _symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Ownable: caller is not the owner or admin");
        _;
    }

    function grantAdmin(address to) public onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminGranted(to);
    }

    function revokeAdmin(address to) public onlyAdmin { 
        require(hasRole(DEFAULT_ADMIN_ROLE, to), "Ownable");
        revokeRole(DEFAULT_ADMIN_ROLE, to);
        emit AdminRevoked(to);
    }

    function mint(address account, uint256 amount) public onlyAdmin returns (bool) {
        _mint(account, amount);
        emit LogMint(account, amount);
        return true;
    }

    function burnIt(address account, uint256 amount) public onlyAdmin returns (bool) {
        _burn(account, amount);
        emit LogBurn(account, amount);
        return true;
    }
}

