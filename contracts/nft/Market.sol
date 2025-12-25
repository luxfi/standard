// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
    ███╗   ███╗ █████╗ ██████╗ ██╗  ██╗███████╗████████╗
    ████╗ ████║██╔══██╗██╔══██╗██║ ██╔╝██╔════╝╚══██╔══╝
    ██╔████╔██║███████║██████╔╝█████╔╝ █████╗     ██║
    ██║╚██╔╝██║██╔══██║██╔══██╗██╔═██╗ ██╔══╝     ██║
    ██║ ╚═╝ ██║██║  ██║██║  ██║██║  ██╗███████╗   ██║
    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝

    Market - Native NFT Marketplace

    First-principles NFT trading:
    - Direct peer-to-peer trades (no custodial escrow)
    - Protocol fees to DAO Treasury
    - Royalty enforcement via ERC-2981
    - LUSD as primary settlement currency
    - Seaport integration for trustless execution
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// Seaport interfaces
import {SeaportInterface} from "seaport-types/src/interfaces/SeaportInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {
    OrderComponents,
    OfferItem,
    ConsiderationItem,
    OrderParameters,
    Order,
    AdvancedOrder,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {OrderType, ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {ILRC20} from "../tokens/interfaces/ILRC20.sol";

/**
 * @title IMarket
 * @notice Market interface
 */
interface IMarket {
    function list(address nftContract, uint256 tokenId, address paymentToken, uint256 price, uint256 duration) external returns (bytes32);
    function cancelListing(bytes32 listingId) external;
    function buy(bytes32 listingId) external payable;
    function makeOffer(address nftContract, uint256 tokenId, address paymentToken, uint256 amount, uint256 duration) external returns (bytes32);
    function cancelOffer(bytes32 offerId) external;
    function acceptOffer(bytes32 offerId) external;
}

/**
 * @title Market
 * @author Lux Industries
 * @notice Native NFT marketplace
 * @dev Uses Seaport for trustless order execution
 */
contract Market is IMarket, Ownable, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice DAO Treasury receives protocol fees
    address payable public constant DAO_TREASURY = payable(0x9011E888251AB053B7bD1cdB598Db4f9DEd94714);

    /// @notice Protocol fee in basis points (2.5%)
    uint256 public constant PROTOCOL_FEE_BPS = 250;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Listing data for an NFT
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        address paymentToken;    // address(0) = native LUX, otherwise LRC20
        uint256 price;
        uint256 expiration;
        bool active;
    }

    /// @notice Offer data for an NFT
    struct Offer {
        address buyer;
        address nftContract;
        uint256 tokenId;
        address paymentToken;
        uint256 amount;
        uint256 expiration;
        bool active;
    }

    /// @notice Collection configuration
    struct Collection {
        bool verified;
        bool tradingEnabled;
        uint256 floorPrice;
        uint256 totalVolume;
        uint256 totalSales;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Seaport contract for order execution
    SeaportInterface public seaport;

    /// @notice Conduit for token approvals
    address public conduit;

    /// @notice LUSD stablecoin (primary payment token)
    ILRC20 public lusd;

    /// @notice Listing ID => Listing data
    mapping(bytes32 => Listing) public listings;

    /// @notice Offer ID => Offer data
    mapping(bytes32 => Offer) public offers;

    /// @notice Collection address => Collection data
    mapping(address => Collection) public collections;

    /// @notice User => nonce for order uniqueness
    mapping(address => uint256) public userNonce;

    /// @notice Total protocol fees collected
    uint256 public totalFeesCollected;

    /// @notice Total trading volume
    uint256 public totalVolume;

    /// @notice Whether market is paused
    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event Listed(
        bytes32 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 expiration
    );

    event ListingCancelled(bytes32 indexed listingId);

    event Sale(
        bytes32 indexed listingId,
        address indexed seller,
        address indexed buyer,
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 protocolFee,
        uint256 royaltyFee
    );

    event OfferMade(
        bytes32 indexed offerId,
        address indexed buyer,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 amount,
        uint256 expiration
    );

    event OfferCancelled(bytes32 indexed offerId);

    event OfferAccepted(
        bytes32 indexed offerId,
        address indexed seller,
        address indexed buyer,
        address nftContract,
        uint256 tokenId,
        uint256 amount
    );

    event CollectionVerified(address indexed collection, bool verified);
    event Paused(bool paused);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error MarketPaused();
    error InvalidPrice();
    error InvalidExpiration();
    error NotOwner();
    error NotSeller();
    error NotBuyer();
    error ListingNotActive();
    error ListingExpired();
    error OfferNotActive();
    error OfferExpired();
    error InsufficientPayment();
    error TransferFailed();
    error NotApproved();
    error CollectionNotEnabled();

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize Market
     * @param seaport_ Seaport contract address
     * @param conduit_ Conduit address for approvals
     * @param lusd_ LUSD stablecoin address
     */
    constructor(
        address seaport_,
        address conduit_,
        address lusd_
    ) Ownable(msg.sender) {
        seaport = SeaportInterface(seaport_);
        conduit = conduit_;
        lusd = ILRC20(lusd_);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════

    modifier whenNotPaused() {
        if (paused) revert MarketPaused();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LISTING FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice List an NFT for sale
     * @param nftContract NFT contract address
     * @param tokenId Token ID to list
     * @param paymentToken Payment token (address(0) for native LUX)
     * @param price Listing price
     * @param duration Listing duration in seconds
     * @return listingId Unique listing identifier
     */
    function list(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (bytes32 listingId) {
        if (price == 0) revert InvalidPrice();
        if (duration == 0) revert InvalidExpiration();

        // Verify ownership
        IERC721 nft = IERC721(nftContract);
        if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();

        // Verify approval
        if (!nft.isApprovedForAll(msg.sender, address(this)) &&
            nft.getApproved(tokenId) != address(this)) {
            revert NotApproved();
        }

        // Generate listing ID
        uint256 nonce = userNonce[msg.sender]++;
        listingId = keccak256(abi.encodePacked(
            msg.sender,
            nftContract,
            tokenId,
            nonce,
            block.timestamp
        ));

        uint256 expiration = block.timestamp + duration;

        // Store listing
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            price: price,
            expiration: expiration,
            active: true
        });

        // Update collection stats
        if (collections[nftContract].floorPrice == 0 || price < collections[nftContract].floorPrice) {
            collections[nftContract].floorPrice = price;
        }

        emit Listed(listingId, msg.sender, nftContract, tokenId, paymentToken, price, expiration);
    }

    /**
     * @notice Cancel a listing
     * @param listingId Listing to cancel
     */
    function cancelListing(bytes32 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.active) revert ListingNotActive();

        listing.active = false;

        emit ListingCancelled(listingId);
    }

    /**
     * @notice Buy a listed NFT
     * @param listingId Listing to purchase
     */
    function buy(bytes32 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];

        if (!listing.active) revert ListingNotActive();
        if (block.timestamp > listing.expiration) revert ListingExpired();

        // Calculate fees
        uint256 price = listing.price;
        uint256 protocolFee = (price * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyFee = 0;
        address royaltyRecipient = address(0);

        // Check for ERC-2981 royalties
        if (IERC165(listing.nftContract).supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyRecipient, royaltyFee) = IERC2981(listing.nftContract).royaltyInfo(listing.tokenId, price);
        }

        uint256 sellerProceeds = price - protocolFee - royaltyFee;

        // Handle payment
        if (listing.paymentToken == address(0)) {
            // Native LUX payment
            if (msg.value < price) revert InsufficientPayment();

            // Pay seller
            (bool success, ) = payable(listing.seller).call{value: sellerProceeds}("");
            if (!success) revert TransferFailed();

            // Pay protocol fee
            (success, ) = DAO_TREASURY.call{value: protocolFee}("");
            if (!success) revert TransferFailed();

            // Pay royalty
            if (royaltyFee > 0 && royaltyRecipient != address(0)) {
                (success, ) = payable(royaltyRecipient).call{value: royaltyFee}("");
                if (!success) revert TransferFailed();
            }

            // Refund excess
            if (msg.value > price) {
                (success, ) = payable(msg.sender).call{value: msg.value - price}("");
                if (!success) revert TransferFailed();
            }
        } else {
            // LRC20 payment
            ILRC20 token = ILRC20(listing.paymentToken);

            // Transfer to seller
            if (!token.transferFrom(msg.sender, listing.seller, sellerProceeds)) {
                revert TransferFailed();
            }

            // Transfer protocol fee
            if (!token.transferFrom(msg.sender, DAO_TREASURY, protocolFee)) {
                revert TransferFailed();
            }

            // Transfer royalty
            if (royaltyFee > 0 && royaltyRecipient != address(0)) {
                if (!token.transferFrom(msg.sender, royaltyRecipient, royaltyFee)) {
                    revert TransferFailed();
                }
            }
        }

        // Transfer NFT
        IERC721(listing.nftContract).safeTransferFrom(listing.seller, msg.sender, listing.tokenId);

        // Update state
        listing.active = false;
        totalFeesCollected += protocolFee;
        totalVolume += price;
        collections[listing.nftContract].totalVolume += price;
        collections[listing.nftContract].totalSales++;

        emit Sale(
            listingId,
            listing.seller,
            msg.sender,
            listing.nftContract,
            listing.tokenId,
            listing.paymentToken,
            price,
            protocolFee,
            royaltyFee
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OFFER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Make an offer on an NFT
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param paymentToken Payment token (must be LRC20, not native)
     * @param amount Offer amount
     * @param duration Offer duration in seconds
     * @return offerId Unique offer identifier
     */
    function makeOffer(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 amount,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (amount == 0) revert InvalidPrice();
        if (duration == 0) revert InvalidExpiration();
        if (paymentToken == address(0)) revert InvalidPrice(); // Must use LRC20 for offers

        // Verify buyer has funds and approval
        ILRC20 token = ILRC20(paymentToken);
        if (token.balanceOf(msg.sender) < amount) revert InsufficientPayment();

        // Generate offer ID
        uint256 nonce = userNonce[msg.sender]++;
        offerId = keccak256(abi.encodePacked(
            msg.sender,
            nftContract,
            tokenId,
            nonce,
            block.timestamp,
            "offer"
        ));

        uint256 expiration = block.timestamp + duration;

        // Store offer
        offers[offerId] = Offer({
            buyer: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            amount: amount,
            expiration: expiration,
            active: true
        });

        emit OfferMade(offerId, msg.sender, nftContract, tokenId, paymentToken, amount, expiration);
    }

    /**
     * @notice Cancel an offer
     * @param offerId Offer to cancel
     */
    function cancelOffer(bytes32 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        if (offer.buyer != msg.sender) revert NotBuyer();
        if (!offer.active) revert OfferNotActive();

        offer.active = false;

        emit OfferCancelled(offerId);
    }

    /**
     * @notice Accept an offer (seller calls this)
     * @param offerId Offer to accept
     */
    function acceptOffer(bytes32 offerId) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];

        if (!offer.active) revert OfferNotActive();
        if (block.timestamp > offer.expiration) revert OfferExpired();

        // Verify caller owns the NFT
        IERC721 nft = IERC721(offer.nftContract);
        if (nft.ownerOf(offer.tokenId) != msg.sender) revert NotOwner();

        // Calculate fees
        uint256 amount = offer.amount;
        uint256 protocolFee = (amount * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 royaltyFee = 0;
        address royaltyRecipient = address(0);

        // Check for ERC-2981 royalties
        if (IERC165(offer.nftContract).supportsInterface(type(IERC2981).interfaceId)) {
            (royaltyRecipient, royaltyFee) = IERC2981(offer.nftContract).royaltyInfo(offer.tokenId, amount);
        }

        uint256 sellerProceeds = amount - protocolFee - royaltyFee;

        // Handle payment (always LRC20 for offers)
        ILRC20 token = ILRC20(offer.paymentToken);

        // Transfer to seller
        if (!token.transferFrom(offer.buyer, msg.sender, sellerProceeds)) {
            revert TransferFailed();
        }

        // Transfer protocol fee
        if (!token.transferFrom(offer.buyer, DAO_TREASURY, protocolFee)) {
            revert TransferFailed();
        }

        // Transfer royalty
        if (royaltyFee > 0 && royaltyRecipient != address(0)) {
            if (!token.transferFrom(offer.buyer, royaltyRecipient, royaltyFee)) {
                revert TransferFailed();
            }
        }

        // Transfer NFT to buyer
        nft.safeTransferFrom(msg.sender, offer.buyer, offer.tokenId);

        // Update state
        offer.active = false;
        totalFeesCollected += protocolFee;
        totalVolume += amount;
        collections[offer.nftContract].totalVolume += amount;
        collections[offer.nftContract].totalSales++;

        emit OfferAccepted(offerId, msg.sender, offer.buyer, offer.nftContract, offer.tokenId, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Verify or unverify a collection
     * @param collection Collection address
     * @param verified Verification status
     */
    function setCollectionVerified(address collection, bool verified) external onlyOwner {
        collections[collection].verified = verified;
        emit CollectionVerified(collection, verified);
    }

    /**
     * @notice Enable or disable trading for a collection
     * @param collection Collection address
     * @param enabled Trading enabled status
     */
    function setCollectionTradingEnabled(address collection, bool enabled) external onlyOwner {
        collections[collection].tradingEnabled = enabled;
    }

    /**
     * @notice Pause or unpause the market
     * @param _paused Pause status
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    /**
     * @notice Update Seaport contract
     * @param newSeaport New Seaport address
     */
    function setSeaport(address newSeaport) external onlyOwner {
        seaport = SeaportInterface(newSeaport);
    }

    /**
     * @notice Update conduit
     * @param newConduit New conduit address
     */
    function setConduit(address newConduit) external onlyOwner {
        conduit = newConduit;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get listing details
     * @param listingId Listing ID
     */
    function getListing(bytes32 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    /**
     * @notice Get offer details
     * @param offerId Offer ID
     */
    function getOffer(bytes32 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    /**
     * @notice Get collection stats
     * @param collection Collection address
     */
    function getCollection(address collection) external view returns (Collection memory) {
        return collections[collection];
    }

    /**
     * @notice Calculate fees for a given price
     * @param price Sale price
     * @return protocolFee Protocol fee amount
     * @return royaltyFee Estimated royalty (assumes 2.5% if ERC-2981)
     */
    function calculateFees(uint256 price) external pure returns (uint256 protocolFee, uint256 royaltyFee) {
        protocolFee = (price * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        royaltyFee = (price * 250) / BPS_DENOMINATOR; // Estimate 2.5% royalty
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RECEIVE
    // ═══════════════════════════════════════════════════════════════════════

    receive() external payable {}
}
