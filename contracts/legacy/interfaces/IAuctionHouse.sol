// SPDX-License-Identifier: GPL-3.0
// Forked from https://github.com/ourzora/auction-house @ 54a12ec1a6cf562e49f0a4917990474b11350a2d

pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

/**
 * @title Interface for Auction Houses
 */
interface IAuctionHouse {

    struct AuctionAddresses {
        address tokenContract;
        address auctionCurrency;
        address tokenOwner;
        address payable curator;
        address payable bidder;
    }

    struct AuctionHistory{
        uint256 amount;
        uint40 time;
        address bidder;
        uint40 blockNumber;
    }

    struct Auction {
        uint256 auctionId;
        // ID for the ERC721 token
        uint256 tokenID;
        // Address for the ERC721 contract
        // Whether or not the auction curator has approved the auction to start
        bool approved;
        // The current highest bid amount
        uint256 amount;
        // The length of time to run the auction for, after the first bid was made
        uint256 duration;
        // The time of the first bid
        uint256 firstBidTime;
        // The minimum price of the first bid
        uint256 reservePrice;
        // The sale percentage to send to the curator
        uint8 curatorFeePercentage;
        // The address that should receive the funds once the NFT is sold.
        // The address of the current highest bid
        AuctionAddresses addresses;

        AuctionHistory[] auctionHistory;

    }

    event AuctionCreated(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        uint256 duration,
        uint256 reservePrice,
        address tokenOwner,
        address curator,
        uint8 curatorFeePercentage,
        address auctionCurrency
    );

    event AuctionApprovalUpdated(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        bool approved
    );

    event AuctionReservePriceUpdated(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        uint256 reservePrice
    );

    event AuctionBid(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        address sender,
        uint256 value,
        bool firstBid,
        bool extended
    );

    event AuctionDurationExtended(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        uint256 duration
    );

    event AuctionEnded(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        address tokenOwner,
        address curator,
        address winner,
        uint256 amount,
        uint256 curatorFee,
        address auctionCurrency
    );

    event AuctionCanceled(
        uint256 indexed auctionID,
        uint256 indexed tokenID,
        address indexed tokenContract,
        address tokenOwner
    );

    function createAuction(
        uint256 tokenID,
        address tokenContract,
        uint256 duration,
        uint256 reservePrice,
        address payable curator,
        uint8 curatorFeePercentages,
        address auctionCurrency
    ) external returns (uint256);

    function setAuctionApproval(uint256 auctionID, bool approved) external;

    function setAuctionReservePrice(uint256 auctionID, uint256 reservePrice) external;

    function createBid(uint256 auctionID, uint256 amount) external payable;

    function endAuction(uint256 auctionID) external;

    function cancelAuction(uint256 auctionID) external;
}
