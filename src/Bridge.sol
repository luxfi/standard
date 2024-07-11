// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { DLUX } from "./DLUX.sol";
import { IERC20Bridgable } from "./interfaces/IERC20Bridgable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILux } from "./interfaces/ILux.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./console.sol";

contract Bridge is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Supported token types
    enum Type {
        ERC20,
        ERC721
    }

    // Supported tokens
    struct Token {
        Type kind;
        uint256 id;
        uint chainId;
        address tokenAddress;
        bool enabled;
    }

    // Unique Swap Tx
    struct Transaction {
        uint256 id;
        Token tokenA;
        Token tokenB;
        address sender;
        address recipient;
        uint256 amount;
        uint256 nonce;
    }

    // Supported tokens
    mapping (uint256 => Token) public tokens;

    // Transactions
    mapping (uint256 => Transaction) public transactions;

    // Events
    event AddToken(uint chainId, address tokenAddress);
    event RemoveToken(uint chainId, address tokenAddress);
    event Mint(uint chainId, address tokenAddress, address to, uint256 amount);
    event Burn(uint chainId, address tokenAddress, address from, uint256 amount);
    event Swap(uint256 tokenA, uint256 tokenB, uint256 txID, address sender, address recipient, uint256 amount);

    // DAO address
    address public daoAddress;

    // DAO share
    uint256 public daoShare;

    constructor(address _daoAddress, uint _daoShare) {
        daoAddress = _daoAddress;
        daoShare = _daoShare;
    }

    // Hash chain, address to a unique identifier
    function tokenID(Token memory token) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(token.chainId, token.tokenAddress)));
    }

    // Hash TX to unique identifier
    function txID(Transaction memory t) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(t.tokenA.id, t.tokenB.id, t.sender, t.recipient, t.amount, t.nonce)));
    }

    // Check if chain ID and token is supported
    function enabledToken(Token memory token) internal view returns (bool) {
        return tokens[tokenID(token)].enabled;
    }

    // Compare chain ID to local chain ID
    function currentChain(uint _chainId) internal view returns (bool) {
        return keccak256(abi.encodePacked(block.chainid)) == keccak256(abi.encodePacked(_chainId));
    }

    // Enable swapping a new ERC20 token
    function setToken(Token memory token) public onlyOwner {
        console.log("setToken", token.chainId, token.tokenAddress);
        require(token.tokenAddress != address(0), "Token address must not be zero");

        require(token.chainId != 0, "Chain ID must not be zero");

        // Update token configuration save ID
        token.id = tokenID(token);
        tokens[token.id] = token;
        console.log("Save token");

        console.log("Check enabled Token");
        if (enabledToken(token)) {
            console.log("AddToken");
            emit AddToken(token.chainId, token.tokenAddress);
        } else {
            console.log("RemoveToken");
            emit RemoveToken(token.chainId, token.tokenAddress);
        }
    }

    // Swap from tokenA to tokenB on another chain. User initiated function, relies on msg.sender
    function swap(Token memory tokenA, Token memory tokenB, address recipient, uint256 amount, uint256 nonce) public {
        require(currentChain(tokenA.chainId) || currentChain(tokenB.chainId), "Wrong chain");
        console.log("swap", msg.sender, recipient, nonce);
        require(enabledToken(tokenA), "Swap from token not enabled");
        require(enabledToken(tokenB), "Swap to token not enabled");
        require(amount > 0, "Amount must be greater than zero");
        require(recipient != address(0), "Recipient should not be zero address");

        // Save transaction
        Transaction memory t = Transaction(0, tokenA, tokenB, msg.sender, recipient, amount, nonce);
        t.id = txID(t);

        // Ensure this is a new swap request
        // There could be an error here as the transaction itself is created
        // and then this check is run.
        // TODO: revert the swap
        require(transactions[t.id].nonce != nonce, "Nonce already used");
        transactions[t.id] = t;

        // Emit all swap related events so listening contracts can mint on other side
        emit Swap(tokenID(tokenA), tokenID(tokenB), t.id, msg.sender, recipient, amount);

        // Burn original tokens
        if (currentChain(tokenA.chainId)) {
            console.log("burn", msg.sender, amount);
            burn(tokenA, msg.sender, amount);
        } else

        // Mint new tokens
        if (currentChain(tokenB.chainId)) {
            console.log("mint", msg.sender, amount);
            mint(tokenB, msg.sender, amount);
        }
    }

    // Internal function to burn token + emit event
    function burn(Token memory token, address owner, uint256 amount) internal {
        console.log("burn", token.tokenAddress, owner, amount);

        if (token.kind == Type.ERC20) {
            IERC20Bridgable(token.tokenAddress).bridgeBurn(owner, amount);
        } else if (token.kind == Type.ERC721) {
            // DLUX(token.tokenAddress).swap(owner, token.id);
        }

        emit Burn(token.chainId, token.tokenAddress, owner, token.id);
    }

    // Mint new tokens for user after burn + swap on alternate chain
    function mint(Token memory token, address owner, uint256 amount) public onlyOwner {
        require(owner != address(0));
        require(amount > 0);
        require(currentChain(token.chainId), "Token not on chain");

        if (token.kind == Type.ERC20) {
            uint256 fee = daoShare.div(10000).mul(amount);
            IERC20Bridgable(token.tokenAddress).bridgeMint(owner, amount.sub(fee));
            IERC20Bridgable(token.tokenAddress).bridgeMint(daoAddress, fee);
        } else {
            // DLUX(token.id).remint(owner, token, token.chainId);
        }
        emit Mint(token.chainId, token.tokenAddress, owner, amount);
    }
}
