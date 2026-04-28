// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ILedger.sol";

/// @title Ledger — pure-Solidity append-only books & records.
/// @notice Base implementation; domain wrappers add access control
///         (e.g. Transfer Agent only, DAO-multisig only).
abstract contract Ledger is ILedger {
    struct Rec {
        uint64 id;
        address from;
        address to;
        address asset;
        uint256 amount;
    }

    Rec[] private _records;
    mapping(bytes32 => uint256) private _balances;
    mapping(address => uint64) private _holders;
    mapping(uint64 => bool) private _reversed;

    function record(address from, address to, address asset, uint256 amount)
        public
        virtual
        override
        returns (uint64 recordId)
    {
        require(amount > 0, "Ledger: zero");
        recordId = uint64(_records.length + 1);
        _records.push(Rec(recordId, from, to, asset, amount));

        if (from != address(0)) {
            bytes32 fk = keccak256(abi.encodePacked(from, asset));
            require(_balances[fk] >= amount, "Ledger: insufficient");
            _balances[fk] -= amount;
            if (_balances[fk] == 0) _holders[asset] -= 1;
        }
        if (to != address(0)) {
            bytes32 tk = keccak256(abi.encodePacked(to, asset));
            if (_balances[tk] == 0) _holders[asset] += 1;
            _balances[tk] += amount;
        }
        emit Recorded(recordId, from, to, asset, amount);
    }

    function reverse(uint64 recordId, uint8 reasonCode) public virtual override returns (bool) {
        if (recordId == 0 || recordId > _records.length || _reversed[recordId]) return false;
        Rec memory r = _records[recordId - 1];
        if (r.to != address(0)) {
            bytes32 tk = keccak256(abi.encodePacked(r.to, r.asset));
            require(_balances[tk] >= r.amount, "Ledger: reverse underflow");
            _balances[tk] -= r.amount;
            if (_balances[tk] == 0) _holders[r.asset] -= 1;
        }
        if (r.from != address(0)) {
            bytes32 fk = keccak256(abi.encodePacked(r.from, r.asset));
            if (_balances[fk] == 0) _holders[r.asset] += 1;
            _balances[fk] += r.amount;
        }
        _reversed[recordId] = true;
        emit Reversed(recordId, reasonCode);
        return true;
    }

    function balanceOf(address holder, address asset) public view virtual override returns (uint256) {
        return _balances[keccak256(abi.encodePacked(holder, asset))];
    }

    function holderCount(address asset) public view virtual override returns (uint64) {
        return _holders[asset];
    }
}
