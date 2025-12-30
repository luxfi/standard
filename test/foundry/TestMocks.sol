// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {MarketParams, Market} from "../../contracts/markets/interfaces/IMarkets.sol";

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED TEST MOCKS - Import these instead of defining inline
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title MockERC20
 * @notice Standard mock ERC20 with mint/burn
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title MockERC20Simple
 * @notice Mock ERC20 without decimals in constructor (18 decimals default)
 */
contract MockERC20Simple is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title MockERC20Solmate
 * @notice Solmate-based mock ERC20
 */
contract MockERC20Solmate is SolmateERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_) SolmateERC20(name, symbol, decimals_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title MockWLUX
 * @notice Mock WLUX (wrapped native token)
 */
contract MockWLUX is MockERC20 {
    constructor() MockERC20("Wrapped LUX", "WLUX", 18) {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/**
 * @title MockWETH
 * @notice Mock WETH (same as WLUX but named differently)
 */
contract MockWETH is MockWLUX {
    constructor() {
        // Inherits WLUX behavior
    }
}

/**
 * @title MockNFT
 * @notice Simple ERC721 for testing
 */
contract MockNFT is ERC721 {
    uint256 public tokenIdCounter;

    constructor() ERC721("Test NFT", "TNFT") {}

    function mint(address to) external returns (uint256) {
        uint256 tokenId = tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }

    function mintBatch(address to, uint256 count) external returns (uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenIds[i] = tokenIdCounter++;
            _mint(to, tokenIds[i]);
        }
        return tokenIds;
    }
}

/**
 * @title MockNFTWithId
 * @notice ERC721 with explicit tokenId minting (for LSSVM tests)
 */
contract MockNFTWithId is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

/**
 * @title MockNFTWithRoyalty
 * @notice ERC721 with ERC2981 royalty support
 */
contract MockNFTWithRoyalty is MockNFT, IERC2981 {
    address public royaltyRecipient;
    uint96 public royaltyBps;

    constructor(address recipient, uint96 bps) {
        royaltyRecipient = recipient;
        royaltyBps = bps;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        return (royaltyRecipient, (salePrice * royaltyBps) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}

/**
 * @title MockOracle
 * @notice Simple price oracle for Markets testing
 */
contract MockOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 priceValue) external {
        prices[token] = priceValue;
    }

    function price() external pure returns (uint256) {
        return 1e36; // 1:1 ratio for simplicity
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token] == 0 ? 1e36 : prices[token];
    }
}

/**
 * @title MockPriceFeed
 * @notice Chainlink-style price feed
 */
contract MockPriceFeed {
    int256 public answer;
    uint8 public decimals_;

    constructor(int256 _answer, uint8 _decimals) {
        answer = _answer;
        decimals_ = _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function setAnswer(int256 _answer) external {
        answer = _answer;
    }
}

/**
 * @title MockRateModel
 * @notice Simple interest rate model for Markets testing
 */
contract MockRateModel {
    uint256 public rate;

    constructor() {
        rate = uint256(0.05e18) / uint256(365 days); // 5% APY default
    }

    function borrowRate(MarketParams memory, Market memory) external view returns (uint256) {
        return rate;
    }

    function setRate(uint256 newRate) external {
        rate = newRate;
    }
}

/**
 * @title MockYearnVault
 * @notice Mock Yearn V2 vault (ERC4626-like)
 */
contract MockYearnVault is MockERC20 {
    MockERC20 public underlying;
    uint256 public pricePerShare = 1e18;

    constructor(MockERC20 _underlying) MockERC20("Yearn Vault", "yvToken", 18) {
        underlying = _underlying;
    }

    function token() external view returns (address) {
        return address(underlying);
    }

    function deposit(uint256 amount) external returns (uint256) {
        underlying.transferFrom(msg.sender, address(this), amount);
        uint256 shares = (amount * 1e18) / pricePerShare;
        _mint(msg.sender, shares);
        return shares;
    }

    function withdraw(uint256 shares) external returns (uint256) {
        uint256 amount = (shares * pricePerShare) / 1e18;
        _burn(msg.sender, shares);
        underlying.transfer(msg.sender, amount);
        return amount;
    }

    function setPricePerShare(uint256 _pricePerShare) external {
        pricePerShare = _pricePerShare;
    }
}

/**
 * @title MockGaugeController
 * @notice Mock gauge controller for governance testing
 */
contract MockGaugeController {
    mapping(address => uint256) public gaugeWeights;

    function vote_for_gauge_weights(address gauge, uint256 weight) external {
        gaugeWeights[gauge] = weight;
    }

    function get_gauge_weight(address gauge) external view returns (uint256) {
        return gaugeWeights[gauge];
    }
}

/**
 * @title MockRewardRouter
 * @notice Mock GMX/LPX reward router
 */
contract MockRewardRouter {
    function stakeGmx(uint256) external {}
    function unstakeGmx(uint256) external {}
    function claimFees() external {}
    function compound() external {}
}

/**
 * @title MockTarget
 * @notice Simple target contract for governance proposals
 */
contract MockTarget {
    uint256 public value;
    event ValueSet(uint256 newValue);

    function setValue(uint256 _value) external {
        value = _value;
        emit ValueSet(_value);
    }
}

/**
 * @title MockTargetFull
 * @notice Enhanced target contract with execution tracking and reverting function
 */
contract MockTargetFull {
    uint256 public value;
    bool public executed;

    function setValue(uint256 newValue) external {
        value = newValue;
        executed = true;
    }

    function revertingFunction() external pure {
        revert("Intentional revert");
    }
}

/**
 * @title MockYieldToken
 * @notice Mock yield-bearing token for Synths testing (Solmate-based)
 */
contract MockYieldToken is SolmateERC20 {
    address public underlying;
    uint256 public pricePerShare = 1e18;

    constructor(
        string memory name,
        string memory symbol,
        address underlying_
    ) SolmateERC20(name, symbol, 18) {
        underlying = underlying_;
    }

    function setPricePerShare(uint256 price) external {
        pricePerShare = price;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = (assets * 1e18) / pricePerShare;
        SolmateERC20(underlying).transferFrom(msg.sender, address(this), assets);
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 assets) {
        assets = (shares * pricePerShare) / 1e18;
        _burn(msg.sender, shares);
        SolmateERC20(underlying).transfer(msg.sender, assets);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/**
 * @title MockPriceFeedFull
 * @notice Enhanced Chainlink-style price feed with all methods
 */
contract MockPriceFeedFull {
    int256 private _answer;
    uint8 private _decimals;

    constructor(int256 initialAnswer, uint8 decimals_) {
        _answer = initialAnswer;
        _decimals = decimals_;
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }

    function latestRound() external pure returns (uint80) {
        return 1;
    }

    function getRoundData(uint80) external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }
}

/**
 * @title MockERC20Minimal
 * @notice Minimal ERC20 mock without inheritance (for compatibility tests)
 */
contract MockERC20Minimal {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MocksLUX
 * @notice Mock staked LUX token with exchange rate
 */
contract MocksLUX is ERC20 {
    ERC20 public immutable lux;
    uint256 public totalStaked;

    constructor(address _lux) ERC20("Mock sLUX", "msLUX") {
        lux = ERC20(_lux);
    }

    function exchangeRate() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalStaked * 1e18) / supply;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        return (assets * supply) / totalStaked;
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return (shares * totalStaked) / supply;
    }

    function stake(uint256 amount) external returns (uint256) {
        lux.transferFrom(msg.sender, address(this), amount);
        uint256 shares = previewDeposit(amount);
        totalStaked += amount;
        _mint(msg.sender, shares);
        return shares;
    }

    function instantUnstake(uint256 shares) external returns (uint256) {
        uint256 assets = previewRedeem(shares);
        uint256 afterPenalty = (assets * 90) / 100;
        totalStaked -= afterPenalty;
        _burn(msg.sender, shares);
        lux.transfer(msg.sender, afterPenalty);
        return afterPenalty;
    }

    function simulateRewards(uint256 amount) external {
        totalStaked += amount;
    }
}

/**
 * @title MockRewardToken
 * @notice Mock reward token with Solmate ERC20 (for staking tests)
 */
contract MockRewardToken is SolmateERC20 {
    constructor() SolmateERC20("Mock Reward", "REWARD", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TREASURY MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title MockGaugeControllerFull
 * @notice Full gauge controller with gauges array for Treasury tests
 */
contract MockGaugeControllerFull {
    struct Gauge {
        address recipient;
        string name;
        uint256 gaugeType;
        bool active;
    }

    address public vLux;
    Gauge[] public gauges;
    mapping(address => uint256) public gaugeIds;
    mapping(address => uint256) public weights;

    constructor(address _vLux) {
        vLux = _vLux;
        // Dummy gauge at 0
        gauges.push(Gauge(address(0), "INVALID", 0, false));
    }

    function addGauge(
        address recipient,
        string memory name,
        uint256 gaugeType
    ) external returns (uint256) {
        uint256 id = gauges.length;
        gauges.push(Gauge(recipient, name, gaugeType, true));
        gaugeIds[recipient] = id;
        return id;
    }

    function setWeight(address recipient, uint256 weight) external {
        weights[recipient] = weight;
    }

    function setGaugeWeight(uint256 gaugeId, uint256 weight) external {
        require(gaugeId < gauges.length, "Invalid gauge");
        weights[gauges[gaugeId].recipient] = weight;
    }

    function getWeightByRecipient(address recipient) external view returns (uint256) {
        return weights[recipient];
    }

    function gaugeCount() external view returns (uint256) {
        return gauges.length;
    }

    function getGauge(uint256 gaugeId) external view returns (
        address recipient,
        string memory name,
        uint256 gaugeType,
        bool active,
        uint256 weight
    ) {
        Gauge memory g = gauges[gaugeId];
        return (g.recipient, g.name, g.gaugeType, g.active, weights[g.recipient]);
    }
}

/**
 * @title MockVLUX
 * @notice Mock voting-escrowed LUX token
 */
contract MockVLUX {
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }

    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }
}

/**
 * @title MockSLUXRewards
 * @notice Mock sLUX for treasury reward distribution (different from MocksLUX staking)
 */
contract MockSLUXRewards {
    address public lux;
    uint256 public pendingRewards;

    constructor(address _lux) {
        lux = _lux;
    }

    function addRewards(uint256 amount) external {
        // Transfer tokens from sender
        (bool success,) = lux.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(success, "Transfer failed");
        pendingRewards += amount;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NFT MARKETPLACE MOCKS  
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * @title MockERC721Full
 * @notice Full ERC721 implementation with all IERC721 methods
 */
contract MockERC721Full is IERC721 {
    string public name = "Mock NFT";
    string public symbol = "MNFT";

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 public nextTokenId = 1;

    function mint(address to) external returns (uint256) {
        uint256 tokenId = nextTokenId++;
        _owners[tokenId] = to;
        _balances[to]++;
        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Token doesn't exist");
        return owner;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    function approve(address to, uint256 tokenId) external {
        address owner = _owners[tokenId];
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "Token doesn't exist");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return (spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender]);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(_owners[tokenId] == from, "Wrong owner");
        require(to != address(0), "Transfer to zero");

        delete _tokenApprovals[tokenId];
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) external pure virtual returns (bool) {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/**
 * @title MockERC721FullWithRoyalty
 * @notice Full ERC721 with ERC2981 royalty support
 */
contract MockERC721FullWithRoyalty is MockERC721Full, IERC2981 {
    address public royaltyReceiver;
    uint96 public royaltyBps = 250; // 2.5%

    constructor(address _receiver) {
        royaltyReceiver = _receiver;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function supportsInterface(bytes4 interfaceId) external pure override(MockERC721Full, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId ||
               interfaceId == type(IERC2981).interfaceId ||
               interfaceId == type(IERC165).interfaceId;
    }
}

/**
 * @title MockLRC20
 * @notice Simple LRC20 mock for NFT marketplace tests
 */
contract MockLRC20 {
    string public name = "Mock LUSD";
    string public symbol = "MLUSD";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }

        return true;
    }
}
