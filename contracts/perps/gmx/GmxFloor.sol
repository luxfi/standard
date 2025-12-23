//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "@luxfi/standard/lib/token/ERC20/IERC20.sol";
import "@luxfi/standard/lib/token/ERC20/utils/SafeERC20.sol";
import "@luxfi/standard/lib/utils/ReentrancyGuard.sol";

import "../tokens/interfaces/IMintable.sol";
import "../access/TokenManager.sol";

contract GmxFloor is ReentrancyGuard, TokenManager {
    
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant BURN_BASIS_POINTS = 9000;

    address public gmx;
    address public reserveToken;
    uint256 public backedSupply;
    uint256 public baseMintPrice;
    uint256 public mintMultiplier;
    uint256 public mintedSupply;
    uint256 public multiplierPrecision;

    mapping (address => bool) public isHandler;

    modifier onlyHandler() {
        require(isHandler[msg.sender], "GmxFloor: forbidden");
        _;
    }

    constructor(
        address _gmx,
        address _reserveToken,
        uint256 _backedSupply,
        uint256 _baseMintPrice,
        uint256 _mintMultiplier,
        uint256 _multiplierPrecision,
        uint256 _minAuthorizations
    ) TokenManager(_minAuthorizations) {
        gmx = _gmx;

        reserveToken = _reserveToken;
        backedSupply = _backedSupply;

        baseMintPrice = _baseMintPrice;
        mintMultiplier = _mintMultiplier;
        multiplierPrecision = _multiplierPrecision;
    }

    function initialize(address[] memory _signers) public override onlyAdmin {
        TokenManager.initialize(_signers);
    }

    function setHandler(address _handler, bool _isHandler) public onlyAdmin {
        isHandler[_handler] = _isHandler;
    }

    function setBackedSupply(uint256 _backedSupply) public onlyAdmin {
        require(_backedSupply > backedSupply, "GmxFloor: invalid _backedSupply");
        backedSupply = _backedSupply;
    }

    function setMintMultiplier(uint256 _mintMultiplier) public onlyAdmin {
        require(_mintMultiplier > mintMultiplier, "GmxFloor: invalid _mintMultiplier");
        mintMultiplier = _mintMultiplier;
    }

    // mint refers to increasing the circulating supply
    // the GMX tokens to be transferred out must be pre-transferred into this contract
    function mint(uint256 _amount, uint256 _maxCost, address _receiver) public onlyHandler nonReentrant returns (uint256) {
        require(_amount > 0, "GmxFloor: invalid _amount");

        uint256 currentMintPrice = getMintPrice();
        uint256 nextMintPrice = currentMintPrice + (_amount * mintMultiplier / multiplierPrecision);
        uint256 averageMintPrice = (currentMintPrice + nextMintPrice) / 2;

        uint256 cost = _amount * averageMintPrice / PRICE_PRECISION;
        require(cost <= _maxCost, "GmxFloor: _maxCost exceeded");

        mintedSupply = mintedSupply + _amount;
        backedSupply = backedSupply + _amount;

        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), cost);
        IERC20(gmx).transfer(_receiver, _amount);

        return cost;
    }

    function burn(uint256 _amount, uint256 _minOut, address _receiver) public onlyHandler nonReentrant returns (uint256) {
        require(_amount > 0, "GmxFloor: invalid _amount");

        uint256 amountOut = getBurnAmountOut(_amount);
        require(amountOut >= _minOut, "GmxFloor: insufficient amountOut");

        backedSupply = backedSupply - _amount;

        IMintable(gmx).burn(msg.sender, _amount);
        IERC20(reserveToken).safeTransfer(_receiver, amountOut);

        return amountOut;
    }

    function getMintPrice() public view returns (uint256) {
        return baseMintPrice + (mintedSupply * mintMultiplier / multiplierPrecision);
    }

    function getBurnAmountOut(uint256 _amount) public view returns (uint256) {
        uint256 balance = IERC20(reserveToken).balanceOf(address(this));
        return _amount * balance / backedSupply * BURN_BASIS_POINTS / BASIS_POINTS_DIVISOR;
    }
}
