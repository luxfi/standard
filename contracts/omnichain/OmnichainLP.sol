// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import { ERC20 } from "@luxfi/standard/lib/token/ERC20/ERC20.sol";
import { Ownable } from "@luxfi/standard/lib/access/Ownable.sol";
import { SafeERC20 } from "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@luxfi/standard/lib/utils/ReentrancyGuard.sol";
import { IERC20Bridgable } from "./interfaces/IERC20Bridgable.sol";
import { Bridge } from "./Bridge.sol";

/**
 * @title OmnichainLP
 * @dev Omnichain Liquidity Pool contract that integrates with the Bridge for cross-chain LP operations
 * Enables LP tokens to be bridged across chains while maintaining liquidity positions
 */
contract OmnichainLP is ERC20, IERC20Bridgable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Bridge contract reference
    Bridge public bridge;

    // Underlying token pairs
    address public token0;
    address public token1;

    // Chain-specific liquidity reserves
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    // Cross-chain liquidity tracking
    mapping(uint256 => uint256) public chainLiquidity; // chainId => total liquidity on that chain
    mapping(address => mapping(uint256 => uint256)) public userChainBalances; // user => chainId => balance

    // Price accumulators for oracle functionality
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // Constants
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public bridgeFee = 30; // 0.3% bridge fee

    // Events
    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityBridged(address indexed user, uint256 fromChain, uint256 toChain, uint256 amount);
    event Sync(uint112 reserve0, uint112 reserve1);
    event CrossChainSync(uint256 indexed chainId, uint256 totalLiquidity);

    modifier onlyBridge() {
        require(msg.sender == address(bridge), "OmnichainLP: Only bridge can call");
        _;
    }

    bool private initialized;

    constructor() ERC20("", "") Ownable(msg.sender) {
        // Empty constructor for CREATE2 deployment
    }

    /**
     * @dev Initialize the LP pair (called once by factory)
     */
    function initialize(
        address _bridge,
        address _token0,
        address _token1,
        string memory _name,
        string memory _symbol
    ) external {
        require(!initialized, "OmnichainLP: Already initialized");
        require(_bridge != address(0), "OmnichainLP: Invalid bridge");
        require(_token0 != address(0) && _token1 != address(0), "OmnichainLP: Invalid tokens");
        require(_token0 != _token1, "OmnichainLP: Identical tokens");

        initialized = true;
        bridge = Bridge(_bridge);
        token0 = _token0;
        token1 = _token1;

        // Note: ERC20 name/symbol set in constructor, cannot be changed post-deployment
        // For upgradeable patterns, use ERC20Upgradeable
    }

    /**
     * @dev Get current reserves
     */
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @dev Add liquidity to the pool
     */
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        require(deadline >= block.timestamp, "OmnichainLP: Expired");
        require(to != address(0), "OmnichainLP: Invalid recipient");

        (amount0, amount1) = _addLiquidity(amount0Desired, amount1Desired, amount0Min, amount1Min);

        // Transfer tokens from user
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        // Calculate liquidity tokens to mint
        liquidity = _mintLiquidity(to, amount0, amount1);

        // Update chain liquidity tracking
        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] + liquidity;
        userChainBalances[to][block.chainid] = userChainBalances[to][block.chainid] + liquidity;

        emit LiquidityAdded(to, amount0, amount1, liquidity);
    }

    /**
     * @dev Remove liquidity from the pool
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(deadline >= block.timestamp, "OmnichainLP: Expired");
        require(liquidity > 0, "OmnichainLP: Insufficient liquidity");
        require(to != address(0), "OmnichainLP: Invalid recipient");

        // Transfer LP tokens from user
        _transfer(msg.sender, address(this), liquidity);

        // Calculate amounts to return
        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * reserve0) / _totalSupply;
        amount1 = (liquidity * reserve1) / _totalSupply;

        require(amount0 >= amount0Min, "OmnichainLP: Insufficient amount0");
        require(amount1 >= amount1Min, "OmnichainLP: Insufficient amount1");

        // Burn LP tokens
        _burn(address(this), liquidity);

        // Transfer tokens to user
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        // Update reserves
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );

        // Update chain liquidity tracking
        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] - liquidity;
        userChainBalances[msg.sender][block.chainid] = userChainBalances[msg.sender][block.chainid] - liquidity;

        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
    }

    /**
     * @dev Bridge LP tokens to another chain
     */
    function bridgeLPTokens(
        uint256 amount,
        uint256 targetChainId,
        address recipient
    ) external nonReentrant {
        require(amount > 0, "OmnichainLP: Invalid amount");
        require(recipient != address(0), "OmnichainLP: Invalid recipient");
        require(targetChainId != block.chainid, "OmnichainLP: Same chain");
        require(balanceOf(msg.sender) >= amount, "OmnichainLP: Insufficient balance");

        // Apply bridge fee
        uint256 fee = (amount * bridgeFee) / FEE_DENOMINATOR;
        uint256 amountAfterFee = amount - fee;

        // Burn LP tokens on source chain
        _burn(msg.sender, amount);

        // Update chain liquidity tracking
        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] - amount;
        userChainBalances[msg.sender][block.chainid] = userChainBalances[msg.sender][block.chainid] - amount;

        // Prepare bridge transaction
        Bridge.Token memory fromToken = Bridge.Token({
            kind: Bridge.Type.ERC20,
            id: 0,
            chainId: block.chainid,
            tokenAddress: address(this),
            enabled: true
        });

        Bridge.Token memory toToken = Bridge.Token({
            kind: Bridge.Type.ERC20,
            id: 0,
            chainId: targetChainId,
            tokenAddress: address(this),
            enabled: true
        });

        // Initiate bridge transfer
        bridge.swap(fromToken, toToken, recipient, amountAfterFee, block.timestamp);

        emit LiquidityBridged(msg.sender, block.chainid, targetChainId, amountAfterFee);
    }

    /**
     * @dev Bridge mint function - called by bridge contract
     */
    function bridgeMint(address to, uint256 amount) external override onlyBridge {
        _mint(to, amount);
        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] + amount;
        userChainBalances[to][block.chainid] = userChainBalances[to][block.chainid] + amount;
        emit CrossChainSync(block.chainid, chainLiquidity[block.chainid]);
    }

    /**
     * @dev Bridge burn function - called by bridge contract
     */
    function bridgeBurn(address from, uint256 amount) external override onlyBridge {
        _burn(from, amount);
        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] - amount;
        userChainBalances[from][block.chainid] = userChainBalances[from][block.chainid] - amount;
        emit CrossChainSync(block.chainid, chainLiquidity[block.chainid]);
    }

    /**
     * @dev Swap tokens in the pool
     */
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "OmnichainLP: Insufficient output amount");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "OmnichainLP: Insufficient liquidity");
        require(to != address(0) && to != token0 && to != token1, "OmnichainLP: Invalid to");

        // Optimistically transfer tokens
        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        // Execute callback if data is provided
        if (data.length > 0) {
            // Implement flash loan callback interface if needed
            // IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        }

        // Get new balances
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Validate swap amounts
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "OmnichainLP: Insufficient input amount");

        // Validate K invariant
        uint256 balance0Adjusted = balance0 * 10000 - amount0In * 30;
        uint256 balance1Adjusted = balance1 * 10000 - amount1In * 30;
        require(
            balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * 10000**2,
            "OmnichainLP: K invariant failed"
        );

        _update(balance0, balance1, _reserve0, _reserve1);
    }

    /**
     * @dev Sync reserves to current balances
     */
    function sync() external nonReentrant {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    /**
     * @dev Mint function for router compatibility
     */
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // Permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = _min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }

        require(liquidity > 0, "OmnichainLP: Insufficient liquidity minted");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);

        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] + liquidity;
        userChainBalances[to][block.chainid] = userChainBalances[to][block.chainid] + liquidity;

        emit LiquidityAdded(to, amount0, amount1, liquidity);
    }

    /**
     * @dev Burn function for router compatibility
     */
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "OmnichainLP: Insufficient liquidity burned");

        _burn(address(this), liquidity);
        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);

        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);

        chainLiquidity[block.chainid] = chainLiquidity[block.chainid] - liquidity;
        userChainBalances[msg.sender][block.chainid] = userChainBalances[msg.sender][block.chainid] - liquidity;

        emit LiquidityRemoved(to, amount0, amount1, liquidity);
    }

    /**
     * @dev Get total liquidity across all chains
     */
    function getTotalCrossChainLiquidity() external view returns (uint256 total) {
        // In production, this would aggregate liquidity data from all chains
        // For now, return current chain liquidity
        return chainLiquidity[block.chainid];
    }

    /**
     * @dev Update bridge fee (onlyOwner)
     */
    function setBridgeFee(uint256 _fee) external onlyOwner {
        require(_fee <= 100, "OmnichainLP: Fee too high"); // Max 1%
        bridgeFee = _fee;
    }

    // Internal functions

    function _addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal view returns (uint256 amount0, uint256 amount1) {
        if (reserve0 == 0 && reserve1 == 0) {
            (amount0, amount1) = (amount0Desired, amount1Desired);
        } else {
            uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;
            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, "OmnichainLP: Insufficient amount1");
                (amount0, amount1) = (amount0Desired, amount1Optimal);
            } else {
                uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
                assert(amount0Optimal <= amount0Desired);
                require(amount0Optimal >= amount0Min, "OmnichainLP: Insufficient amount0");
                (amount0, amount1) = (amount0Optimal, amount1Desired);
            }
        }
    }

    function _mintLiquidity(address to, uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // Permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = _min(
                (amount0 * _totalSupply) / reserve0,
                (amount1 * _totalSupply) / reserve1
            );
        }
        require(liquidity > 0, "OmnichainLP: Insufficient liquidity minted");
        _mint(to, liquidity);

        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) internal {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OmnichainLP: Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint256(_reserve1) * timeElapsed / _reserve0;
            price1CumulativeLast += uint256(_reserve0) * timeElapsed / _reserve1;
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;

        emit Sync(reserve0, reserve1);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
