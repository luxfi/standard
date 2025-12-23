// SPDX-License-Identifier: GPL-3.0
// Forked from https://github.com/ourzora/auction-house @ 54a12ec1a6cf562e49f0a4917990474b11350a2d

pragma solidity >=0.8.4;
pragma experimental ABIEncoderV2;

import { Counters } from "@openzeppelin/contracts/utils/Counters.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IMarket, Decimal } from "./interfaces/IMarket.sol";
import { IMedia } from "./interfaces/IMedia.sol";
import { IAuctionHouse } from "./interfaces/IAuctionHouse.sol";
import "forge-std/console.sol";

interface IMediaExtended is IMedia {
    function marketContract() external returns (address);
}

/**
 * @title Lux's auction house, enabling players to buy, sell and trade NFTs
 */
contract Auction is IAuctionHouse, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    // The minimum amount of time left in an auction after a new bid is created
    uint256 public timeBuffer;

    // The minimum percentage difference between the last bid amount and the current bid.
    uint8 public minBidIncrementPercentage;

    // The address of the Media protocol to use via this contract
    address public mediaAddress;

    // The address of the Token contract
    address public tokenAddress;

    // A mapping of all of the auctions currently running.
    mapping(uint256 => IAuctionHouse.Auction) public auctions;

    bytes4 constant interfaceID = 0x80ac58cd; // 721 interface id

    Counters.Counter private _auctionIDTracker;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Require that the specified auction exists
     */
    modifier auctionExists(uint256 auctionID) {
        require(_exists(auctionID), "Auction doesn't exist");
        _;
    }

    function getAllAuctions() public view returns(IAuctionHouse.Auction[] memory) {
        IAuctionHouse.Auction[] memory allAuctions = new IAuctionHouse.Auction[](_auctionIDTracker.current());
        
        for (uint256 i = 0; i < _auctionIDTracker.current(); i++) {
            if(auctions[i + 1].addresses.tokenOwner != address(0)){
                allAuctions[i] = auctions[i + 1];
            }
        }

        return allAuctions;
    }

    /*
     * Configure LuxAuction to work with the proper media and token contract
     */
    function configure(address _mediaAddress, address _tokenAddress) public onlyOwner {
        require(
            IERC165(_mediaAddress).supportsInterface(interfaceID),
            "Doesn't support NFT interface"
        );
        mediaAddress = _mediaAddress;
        tokenAddress = _tokenAddress;
        timeBuffer = 15 * 60; // extend 15 minutes after every bid made in last 15 minutes
        minBidIncrementPercentage = 5; // 5%
    }

    /**
     * @notice Create an auction.
     * @dev Store the auction details in the auctions mapping and emit an AuctionCreated event.
     * If there is no curator, or if the curator is the auction creator, automatically approve the auction.
     */
    function createAuction(
        uint256 tokenID,
        address tokenContract,
        uint256 duration,
        uint256 reservePrice,
        address payable curator,
        uint8 curatorFeePercentage,
        address auctionCurrency
    ) public override nonReentrant returns (uint256) {
        require(
            IERC165(tokenContract).supportsInterface(interfaceID),
            "tokenContract does not support ERC721 interface"
        );
        require(
            curatorFeePercentage < 100,
            "curatorFeePercentage must be less than 100"
        );
        address tokenOwner = IERC721(tokenContract).ownerOf(tokenID);
        require(
            msg.sender == IERC721(tokenContract).getApproved(tokenID) ||
                msg.sender == tokenOwner,
            "Caller must be approved or owner for token id"
        );
        _auctionIDTracker.increment();

        uint256 auctionID = _auctionIDTracker.current();

        auctions[auctionID].auctionId = auctionID;
        auctions[auctionID].tokenID = tokenID;
        auctions[auctionID].approved = false;
        auctions[auctionID].amount = 0;
        auctions[auctionID].duration = duration;
        auctions[auctionID].firstBidTime = 0;
        auctions[auctionID].reservePrice = reservePrice;
        auctions[auctionID].curatorFeePercentage = curatorFeePercentage;
        auctions[auctionID].addresses = AuctionAddresses({tokenOwner: tokenOwner,auctionCurrency: auctionCurrency,curator: curator,tokenContract: tokenContract,bidder: payable(address(0))});

        IERC721(tokenContract).transferFrom(tokenOwner, address(this), tokenID);

        emit AuctionCreated(
            auctionID,
            tokenID,
            tokenContract,
            duration,
            reservePrice,
            tokenOwner,
            curator,
            curatorFeePercentage,
            auctionCurrency
        );

        if (
            auctions[auctionID].addresses.curator == address(0) || curator == tokenOwner
        ) {
            _approveAuction(auctionID, true);
        }

        return auctionID;
    }

    /**
     * @notice Approve an auction, opening up the auction for bids.
     * @dev Only callable by the curator. Cannot be called if the auction has already started.
     */
    function setAuctionApproval(uint256 auctionID, bool approved)
        external
        override
        auctionExists(auctionID)
    {
        require(
            msg.sender == auctions[auctionID].addresses.curator,
            "Must be auction curator"
        );
        require(
            auctions[auctionID].firstBidTime == 0,
            "Auction has already started"
        );
        _approveAuction(auctionID, approved);
    }

    function setAuctionReservePrice(uint256 auctionID, uint256 reservePrice)
        external
        override
        auctionExists(auctionID)
    {
        require(
            msg.sender == auctions[auctionID].addresses.curator ||
                msg.sender == auctions[auctionID].addresses.tokenOwner,
            "Must be auction curator or token owner"
        );
        require(
            auctions[auctionID].firstBidTime == 0,
            "Auction has already started"
        );

        auctions[auctionID].reservePrice = reservePrice;

        emit AuctionReservePriceUpdated(
            auctionID,
            auctions[auctionID].tokenID,
            auctions[auctionID].addresses.tokenContract,
            reservePrice
        );
    }

    /**
     * @notice Create a bid on a token, with a given amount.
     * @dev If provided a valid bid, transfers the provided amount to this contract.
     * If the auction is run in native ETH, the ETH is wrapped so it can be identically to other
     * auction currencies in this contract.
     */
    function createBid(uint256 auctionID, uint256 amount)
        external
        payable
        override
        auctionExists(auctionID)
        nonReentrant
    {
        address payable lastBidder = auctions[auctionID].addresses.bidder;

        require(
            auctions[auctionID].approved,
            "Auction must be approved by curator"
        );
        require(
            auctions[auctionID].firstBidTime == 0 ||
                block.timestamp <
                auctions[auctionID].firstBidTime.add(
                    auctions[auctionID].duration
                ),
            "Auction expired"
        );

        require(
            amount >= auctions[auctionID].reservePrice,
            "Must send at least reservePrice"
        );
        require(
            amount >=
                auctions[auctionID].amount.add(
                    auctions[auctionID]
                    .amount
                    .mul(minBidIncrementPercentage)
                    .div(100)
                ),
            "Must send more than last bid by minBidIncrementPercentage amount"
        );

        // For Lux Protocol, ensure that the bid is valid for the current bidShare configuration
        if (auctions[auctionID].addresses.tokenContract == tokenAddress) {
            require(
                IMarket(IMediaExtended(tokenAddress).marketContract())
                    .isValidBid(auctions[auctionID].tokenID, amount),
                "Bid invalid for share splitting"
            );
        }

        // If this is the first valid bid, we should set the starting time now.
        // If it's not, then we should refund the last bidder
        if (auctions[auctionID].firstBidTime == 0) {
            auctions[auctionID].firstBidTime = block.timestamp;
        } else if (lastBidder != address(0)) {
            _handleOutgoingBid(
                lastBidder,
                auctions[auctionID].amount,
                auctions[auctionID].addresses.auctionCurrency
            );
        }

        _handleIncomingBid(amount, tokenAddress);

        auctions[auctionID].amount = amount;
        auctions[auctionID].addresses.bidder = payable(msg.sender);

        bool extended = false;
        // at this point we know that the timestamp is less than start + duration (since the auction would be over, otherwise)
        // we want to know by how much the timestamp is less than start + duration
        // if the difference is less than the timeBuffer, increase the duration by the timeBuffer
        if (
            auctions[auctionID]
            .firstBidTime
            .add(auctions[auctionID].duration)
            .sub(block.timestamp) < timeBuffer
        ) {
            // Playing code golf for gas optimization:
            // uint256 expectedEnd = auctions[auctionID].firstBidTime.add(auctions[auctionID].duration);
            // uint256 timeRemaining = expectedEnd.sub(block.timestamp);
            // uint256 timeToAdd = timeBuffer.sub(timeRemaining);
            // uint256 newDuration = auctions[auctionID].duration.add(timeToAdd);
            uint256 oldDuration = auctions[auctionID].duration;
            auctions[auctionID].duration = oldDuration.add(
                timeBuffer.sub(
                    auctions[auctionID].firstBidTime.add(oldDuration).sub(
                        block.timestamp
                    )
                )
            );
            extended = true;
        }

        auctions[auctionID].auctionHistory.push(AuctionHistory(
            {
                amount: amount,
                bidder: msg.sender,
                blockNumber: uint40(block.number),
                time: uint40(block.timestamp)
            }
        ));

        emit AuctionBid(
            auctionID,
            auctions[auctionID].tokenID,
            auctions[auctionID].addresses.tokenContract,
            msg.sender,
            amount,
            lastBidder == address(0), // firstBid boolean
            extended
        );

        if (extended) {
            emit AuctionDurationExtended(
                auctionID,
                auctions[auctionID].tokenID,
                auctions[auctionID].addresses.tokenContract,
                auctions[auctionID].duration
            );
        }
    }

    /**
     * @notice End an auction, finalizing the bid on Lux if applicable and paying out the respective parties.
     * @dev If for some reason the auction cannot be finalized (invalid token recipient, for example),
     * The auction is reset and the NFT is transferred back to the auction creator.
     */
    function endAuction(uint256 auctionID)
        external
        override
        auctionExists(auctionID)
        nonReentrant
    {
        require(
            uint256(auctions[auctionID].firstBidTime) != 0,
            "Auction hasn't begun"
        );
        require(
            block.timestamp >=
                auctions[auctionID].firstBidTime.add(
                    auctions[auctionID].duration
                ),
            "Auction hasn't completed"
        );

        address currency = tokenAddress;

        uint256 curatorFee = 0;

        uint256 tokenOwnerProfit = auctions[auctionID].amount;

        if (auctions[auctionID].addresses.tokenContract == tokenAddress) {
            // If the auction is running on lux, settle it on the protocol
            (
                bool success,
                uint256 remainingProfit
            ) = _handleLuxAuctionSettlement(auctionID);
            tokenOwnerProfit = remainingProfit;
            if (success != true) {
                _handleOutgoingBid(
                    auctions[auctionID].addresses.bidder,
                    auctions[auctionID].amount,
                    auctions[auctionID].addresses.auctionCurrency
                );
                _cancelAuction(auctionID);
                return;
            }
        } else {
            // Otherwise, transfer the token to the winner and pay out the participants below
            try
                IERC721(auctions[auctionID].addresses.tokenContract).safeTransferFrom(
                    address(this),
                    auctions[auctionID].addresses.bidder,
                    auctions[auctionID].tokenID
                )
            {} catch {
                _handleOutgoingBid(
                    auctions[auctionID].addresses.bidder,
                    auctions[auctionID].amount,
                    auctions[auctionID].addresses.auctionCurrency
                );
                _cancelAuction(auctionID);
                return;
            }
        }

        if (auctions[auctionID].addresses.curator != address(0)) {
            curatorFee = tokenOwnerProfit
            .mul(auctions[auctionID].curatorFeePercentage)
            .div(100);
            tokenOwnerProfit = tokenOwnerProfit.sub(curatorFee);
            _handleOutgoingBid(
                auctions[auctionID].addresses.curator,
                curatorFee,
                auctions[auctionID].addresses.auctionCurrency
            );
        }
        _handleOutgoingBid(
            auctions[auctionID].addresses.tokenOwner,
            tokenOwnerProfit,
            auctions[auctionID].addresses.auctionCurrency
        );

        emit AuctionEnded(
            auctionID,
            auctions[auctionID].tokenID,
            auctions[auctionID].addresses.tokenContract,
            auctions[auctionID].addresses.tokenOwner,
            auctions[auctionID].addresses.curator,
            auctions[auctionID].addresses.bidder,
            tokenOwnerProfit,
            curatorFee,
            currency
        );
        delete auctions[auctionID];
    }

    /**
     * @notice Cancel an auction.
     * @dev Transfers the NFT back to the auction creator and emits an AuctionCanceled event
     */
    function cancelAuction(uint256 auctionID)
        external
        override
        nonReentrant
        auctionExists(auctionID)
    {
        require(
            auctions[auctionID].addresses.tokenOwner == msg.sender ||
                auctions[auctionID].addresses.curator == msg.sender,
            "Can only be called by auction creator or curator"
        );
        require(
            uint256(auctions[auctionID].firstBidTime) == 0,
            "Can't cancel an auction once it's begun"
        );
        _cancelAuction(auctionID);
    }

    /**
     * @dev Given an amount and a currency, transfer the currency to this contract.
     * If the currency is ETH (0x0), attempt to wrap the amount as WETH
     */
    function _handleIncomingBid(uint256 amount, address currency) internal {
        // We must check the balance that was actually transferred to the auction,
        // as some tokens impose a transfer fee and would not actually transfer the
        // full amount to the market, resulting in potentally locked funds
        IERC20 token = IERC20(currency);

        uint256 beforeBalance = token.balanceOf(address(this));

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 afterBalance = token.balanceOf(address(this));
        require(
            beforeBalance.add(amount) == afterBalance,
            "Token transfer call did not transfer expected amount"
        );
        // }
    }

    function _handleOutgoingBid(
        address to,
        uint256 amount,
        address currency
    ) internal {
        IERC20(currency).safeTransfer(to, amount);
    }

    function _safeTransferETH(address to, uint256 value)
        internal
        returns (bool)
    {
        (bool success, ) = to.call{value: value}(new bytes(0));
        return success;
    }

    function _cancelAuction(uint256 auctionID) internal {
        address tokenOwner = auctions[auctionID].addresses.tokenOwner;
        IERC721(auctions[auctionID].addresses.tokenContract).safeTransferFrom(
            address(this),
            tokenOwner,
            auctions[auctionID].tokenID
        );

        emit AuctionCanceled(
            auctionID,
            auctions[auctionID].tokenID,
            auctions[auctionID].addresses.tokenContract,
            tokenOwner
        );
        delete auctions[auctionID];
    }

    function _approveAuction(uint256 auctionID, bool approved) internal {
        auctions[auctionID].approved = approved;
        emit AuctionApprovalUpdated(
            auctionID,
            auctions[auctionID].tokenID,
            auctions[auctionID].addresses.tokenContract,
            approved
        );
    }

    function _exists(uint256 auctionID) internal view returns (bool) {
        return auctions[auctionID].addresses.tokenOwner != address(0);
    }

    function _handleLuxAuctionSettlement(uint256 auctionID)
        internal
        returns (bool, uint256)
    {
        address currency = tokenAddress;
        // ? tokenAddress
        // : auctions[auctionID].auctionCurrency;

        IMarket.Bid memory bid = IMarket.Bid({
            amount: auctions[auctionID].amount,
            currency: currency,
            bidder: address(this),
            recipient: auctions[auctionID].addresses.bidder,
            sellOnShare: Decimal.D256(0),
            offline: false
        });

        IERC20(currency).approve(
            IMediaExtended(tokenAddress).marketContract(),
            bid.amount
        );
        IMedia(tokenAddress).setBid(auctions[auctionID].tokenID, bid);
        uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
        try
            IMedia(tokenAddress).acceptBid(auctions[auctionID].tokenID, bid)
        {} catch {
            // If the underlying NFT transfer here fails, we should cancel the auction and refund the winner
            IMediaExtended(tokenAddress).removeBid(auctions[auctionID].tokenID);
            return (false, 0);
        }
        uint256 afterBalance = IERC20(currency).balanceOf(address(this));

        // We have to calculate the amount to send to the token owner here in case there was a
        // sell-on share on the token
        return (true, afterBalance.sub(beforeBalance));
    }

    // TODO: consider reverting if the message sender is not WETH
    receive() external payable {}

    fallback() external payable {}
}
