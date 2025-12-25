// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./LSSVMPair.sol";
import "./ICurve.sol";

/// @title LSSVMPairFactory - NFT AMM Factory
/// @notice Creates and manages LSSVM pairs for NFT trading
/// @dev Based on Sudoswap LSSVM whitepaper
contract LSSVMPairFactory is Ownable {
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event PairCreated(
        address indexed pair,
        address indexed nft,
        address indexed bondingCurve,
        address token,
        LSSVMPair.PoolType poolType
    );
    event BondingCurveStatusUpdate(address indexed curve, bool allowed);
    event ProtocolFeeRecipientUpdate(address indexed recipient);
    event ProtocolFeeMultiplierUpdate(uint256 multiplier);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error InvalidCurve();
    error InvalidSpotPrice();
    error InvalidDelta();
    error InvalidFee();

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Allowed bonding curves
    mapping(address => bool) public bondingCurveAllowed;

    /// @notice Protocol fee recipient
    address public protocolFeeRecipient;

    /// @notice Protocol fee in basis points (e.g., 50 = 0.5%)
    uint256 public protocolFeeMultiplier;

    /// @notice All pairs created
    address[] public allPairs;

    /// @notice Pairs by NFT collection
    mapping(address => address[]) public pairsByNft;

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _protocolFeeRecipient) Ownable(msg.sender) {
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeMultiplier = 50; // 0.5% default
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAIR CREATION
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Create a new LSSVM pair
    /// @param _nft NFT collection address
    /// @param _bondingCurve Bonding curve to use
    /// @param _token Quote token (address(0) for native LUX)
    /// @param _poolType Pool type (TOKEN, NFT, or TRADE)
    /// @param _spotPrice Initial spot price
    /// @param _delta Price delta parameter
    /// @param _fee Trade fee in basis points
    /// @param _assetRecipient Fee recipient for TRADE pools
    /// @param _initialNFTIds Initial NFT IDs to deposit
    /// @return pair Address of created pair
    function createPair(
        address _nft,
        address _bondingCurve,
        address _token,
        LSSVMPair.PoolType _poolType,
        uint128 _spotPrice,
        uint128 _delta,
        uint96 _fee,
        address _assetRecipient,
        uint256[] calldata _initialNFTIds
    ) external payable returns (address pair) {
        // Validate inputs
        if (!bondingCurveAllowed[_bondingCurve]) revert InvalidCurve();
        if (!ICurve(_bondingCurve).validateSpotPrice(_spotPrice)) revert InvalidSpotPrice();
        if (!ICurve(_bondingCurve).validateDelta(_delta)) revert InvalidDelta();
        if (_fee > 9000) revert InvalidFee(); // Max 90%

        // Create pair
        pair = address(new LSSVMPair());
        LSSVMPair(payable(pair)).initialize(
            msg.sender,
            _nft,
            _bondingCurve,
            _token,
            _poolType,
            _spotPrice,
            _delta,
            _fee,
            _assetRecipient
        );

        // Track pair
        allPairs.push(pair);
        pairsByNft[_nft].push(pair);

        // Deposit initial NFTs (use safeTransferFrom to trigger onERC721Received for tracking)
        if (_initialNFTIds.length > 0) {
            for (uint256 i = 0; i < _initialNFTIds.length; i++) {
                IERC721(_nft).safeTransferFrom(msg.sender, pair, _initialNFTIds[i]);
            }
        }

        // Deposit initial tokens (for ETH pools)
        if (msg.value > 0 && _token == address(0)) {
            (bool success,) = pair.call{value: msg.value}("");
            require(success, "LSSVMPairFactory: ETH_TRANSFER_FAILED");
        }

        emit PairCreated(pair, _nft, _bondingCurve, _token, _poolType);
    }

    /// @notice Create a pair that only buys NFTs (TOKEN pool)
    function createPairTokenOnly(
        address _nft,
        address _bondingCurve,
        address _token,
        uint128 _spotPrice,
        uint128 _delta,
        uint96 _fee
    ) external payable returns (address) {
        uint256[] memory empty = new uint256[](0);
        return this.createPair(
            _nft,
            _bondingCurve,
            _token,
            LSSVMPair.PoolType.TOKEN,
            _spotPrice,
            _delta,
            _fee,
            address(0),
            empty
        );
    }

    /// @notice Create a pair that only sells NFTs (NFT pool)
    function createPairNFTOnly(
        address _nft,
        address _bondingCurve,
        address _token,
        uint128 _spotPrice,
        uint128 _delta,
        uint256[] calldata _initialNFTIds
    ) external returns (address) {
        return this.createPair(
            _nft,
            _bondingCurve,
            _token,
            LSSVMPair.PoolType.NFT,
            _spotPrice,
            _delta,
            0, // No fee for NFT-only pools
            address(0),
            _initialNFTIds
        );
    }

    /// @notice Create a two-sided trading pair (TRADE pool)
    function createPairTrade(
        address _nft,
        address _bondingCurve,
        address _token,
        uint128 _spotPrice,
        uint128 _delta,
        uint96 _fee,
        address _assetRecipient,
        uint256[] calldata _initialNFTIds
    ) external payable returns (address) {
        return this.createPair(
            _nft,
            _bondingCurve,
            _token,
            LSSVMPair.PoolType.TRADE,
            _spotPrice,
            _delta,
            _fee,
            _assetRecipient,
            _initialNFTIds
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Enable or disable a bonding curve
    function setBondingCurveAllowed(address curve, bool allowed) external onlyOwner {
        bondingCurveAllowed[curve] = allowed;
        emit BondingCurveStatusUpdate(curve, allowed);
    }

    /// @notice Set protocol fee recipient
    function setProtocolFeeRecipient(address recipient) external onlyOwner {
        protocolFeeRecipient = recipient;
        emit ProtocolFeeRecipientUpdate(recipient);
    }

    /// @notice Set protocol fee multiplier
    function setProtocolFeeMultiplier(uint256 multiplier) external onlyOwner {
        require(multiplier <= 1000, "LSSVMPairFactory: FEE_TOO_HIGH"); // Max 10%
        protocolFeeMultiplier = multiplier;
        emit ProtocolFeeMultiplierUpdate(multiplier);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function getPairsByNft(address nft) external view returns (address[] memory) {
        return pairsByNft[nft];
    }

    function getPairsByNftLength(address nft) external view returns (uint256) {
        return pairsByNft[nft].length;
    }
}
