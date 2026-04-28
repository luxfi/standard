// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IOrderBook.sol";

/// @title OrderBook — pure-Solidity CLOB reference implementation.
/// @notice Price-time-priority matcher. Storage is per-symbol arrays of
///         resting orders, sorted descending for bids and ascending for
///         asks. Domain wrappers (ATS, darkpool, etc.) inherit this and
///         layer their own registries, gates, or hooks around it.
abstract contract OrderBook is IOrderBook {
    struct Order {
        uint64 id;
        address trader;
        uint256 price;
        uint256 qty;
        Side side;
    }

    mapping(bytes32 => Order[]) private _bids;
    mapping(bytes32 => Order[]) private _asks;
    mapping(bytes32 => uint64) private _next;

    function match_(Side side, string calldata symbol, uint256 price, uint256 qty)
        public
        virtual
        override
        returns (bytes32 orderId)
    {
        require(price > 0 && qty > 0, "OrderBook: zero");
        bytes32 key = keccak256(bytes(symbol));
        uint64 id = ++_next[key];
        uint256 remaining = qty;

        if (side == Side.Buy) {
            Order[] storage asks = _asks[key];
            uint256 i = 0;
            while (i < asks.length && remaining > 0) {
                if (asks[i].price > price) break;
                uint256 fill = remaining < asks[i].qty ? remaining : asks[i].qty;
                remaining -= fill;
                asks[i].qty -= fill;
                emit OrderFilled(_id(asks[i].id), _id(id), asks[i].price, fill);
                if (asks[i].qty == 0) _shiftLeft(asks, i);
                else i++;
            }
            if (remaining > 0) {
                _insertDesc(_bids[key], Order(id, msg.sender, price, remaining, side));
                emit OrderPlaced(_id(id), msg.sender, symbol, side, price, remaining);
            }
        } else {
            Order[] storage bids = _bids[key];
            uint256 i = 0;
            while (i < bids.length && remaining > 0) {
                if (bids[i].price < price) break;
                uint256 fill = remaining < bids[i].qty ? remaining : bids[i].qty;
                remaining -= fill;
                bids[i].qty -= fill;
                emit OrderFilled(_id(bids[i].id), _id(id), bids[i].price, fill);
                if (bids[i].qty == 0) _shiftLeft(bids, i);
                else i++;
            }
            if (remaining > 0) {
                _insertAsc(_asks[key], Order(id, msg.sender, price, remaining, side));
                emit OrderPlaced(_id(id), msg.sender, symbol, side, price, remaining);
            }
        }
        return _id(id);
    }

    function cancel(string calldata symbol, uint64 orderId) public virtual override returns (bool) {
        bytes32 key = keccak256(bytes(symbol));
        if (_remove(_bids[key], orderId, msg.sender) || _remove(_asks[key], orderId, msg.sender)) {
            emit OrderCancelled(_id(orderId));
            return true;
        }
        return false;
    }

    function bestPrice(string calldata symbol, Side side) public view virtual override returns (uint256) {
        bytes32 key = keccak256(bytes(symbol));
        if (side == Side.Buy) {
            Order[] storage asks = _asks[key];
            return asks.length == 0 ? 0 : asks[0].price;
        }
        Order[] storage bids = _bids[key];
        return bids.length == 0 ? 0 : bids[0].price;
    }

    function _id(uint64 v) private pure returns (bytes32) {
        return bytes32(uint256(v));
    }

    function _insertDesc(Order[] storage s, Order memory o) private {
        s.push(o);
        for (uint256 i = s.length - 1; i > 0; i--) {
            if (s[i].price > s[i - 1].price) {
                Order memory t = s[i];
                s[i] = s[i - 1];
                s[i - 1] = t;
            } else {
                break;
            }
        }
    }

    function _insertAsc(Order[] storage s, Order memory o) private {
        s.push(o);
        for (uint256 i = s.length - 1; i > 0; i--) {
            if (s[i].price < s[i - 1].price) {
                Order memory t = s[i];
                s[i] = s[i - 1];
                s[i - 1] = t;
            } else {
                break;
            }
        }
    }

    function _shiftLeft(Order[] storage s, uint256 idx) private {
        for (uint256 i = idx; i + 1 < s.length; i++) {
            s[i] = s[i + 1];
        }
        s.pop();
    }

    function _remove(Order[] storage s, uint64 id, address owner) private returns (bool) {
        for (uint256 i = 0; i < s.length; i++) {
            if (s[i].id == id && s[i].trader == owner) {
                _shiftLeft(s, i);
                return true;
            }
        }
        return false;
    }
}
