// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import "../core/interfaces/ILLPManager.sol";

contract LLPBalance {
    

    ILLPManager public llpManager;
    address public stakedLlpTracker;

    mapping (address => mapping (address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        ILLPManager _llpManager,
        address _stakedLlpTracker
    ) public {
        llpManager = _llpManager;
        stakedLlpTracker = _stakedLlpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "LLPBalance: approve from the zero address");
        require(_spender != address(0), "LLPBalance: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "LLPBalance: transfer from the zero address");
        require(_recipient != address(0), "LLPBalance: transfer to the zero address");

        require(
            llpManager.lastAddedAt(_sender) + llpManager.cooldownDuration() <= block.timestamp,
            "LLPBalance: cooldown duration not yet passed"
        );

        IERC20(stakedLlpTracker).transferFrom(_sender, _recipient, _amount);
    }
}
