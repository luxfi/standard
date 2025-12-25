// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.31;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/nft/Market.sol";
import "../../contracts/tokens/LRC1155/LRC1155.sol";
import {ILRC20} from "../../contracts/tokens/interfaces/ILRC20.sol";

/**
 * @title MockERC721
 * @notice Simple ERC721 implementation for testing
 */
contract MockERC721 is IERC721 {
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

    function supportsInterface(bytes4 interfaceId) external pure virtual override returns (bool) {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/**
 * @title MockERC721WithRoyalty
 * @notice ERC721 with ERC2981 royalty support
 */
contract MockERC721WithRoyalty is MockERC721, IERC2981 {
    address public royaltyReceiver;
    uint96 public royaltyBps = 250; // 2.5%

    constructor(address _receiver) {
        royaltyReceiver = _receiver;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBps) / 10000;
        return (royaltyReceiver, royaltyAmount);
    }

    function supportsInterface(bytes4 interfaceId) external pure override(MockERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId ||
               interfaceId == type(IERC2981).interfaceId ||
               interfaceId == type(IERC165).interfaceId;
    }
}

/**
 * @title MockLRC20
 * @notice Simple ERC20 for testing
 */
contract MockLRC20 is ILRC20 {
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

/**
 * @title MarketTest
 * @notice Comprehensive tests for NFT marketplace
 */
contract MarketTest is Test {
    Market public market;
    MockERC721 public nft;
    MockERC721WithRoyalty public nftWithRoyalty;
    MockLRC20 public lusd;

    address public owner = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public royaltyRecipient = address(4);
    address public seaport = address(5);
    address public conduit = address(6);

    uint256 public constant PRICE = 1 ether;
    uint256 public constant DURATION = 7 days;

    event Listed(
        bytes32 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 expiration
    );

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

    event OfferAccepted(
        bytes32 indexed offerId,
        address indexed seller,
        address indexed buyer,
        address nftContract,
        uint256 tokenId,
        uint256 amount
    );

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);
        lusd = new MockLRC20();
        market = new Market(seaport, conduit, address(lusd));
        nft = new MockERC721();
        nftWithRoyalty = new MockERC721WithRoyalty(royaltyRecipient);
        vm.stopPrank();

        // Setup seller with NFT
        vm.startPrank(seller);
        nft.mint(seller);
        nft.setApprovalForAll(address(market), true);
        vm.stopPrank();

        // Setup buyer with funds
        vm.deal(buyer, 100 ether);
        lusd.mint(buyer, 1000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LISTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_List_Success() public {
        vm.startPrank(seller);

        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);

        Market.Listing memory listing = market.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(nft));
        assertEq(listing.tokenId, 1);
        assertEq(listing.paymentToken, address(0));
        assertEq(listing.price, PRICE);
        assertTrue(listing.active);

        vm.stopPrank();
    }

    function test_List_EmitsEvent() public {
        vm.startPrank(seller);

        // Skip checking listingId (first indexed param) since it's computed from hash
        vm.expectEmit(false, true, true, true);
        emit Listed(
            bytes32(0), // Not checked - computed from keccak256
            seller,
            address(nft),
            1,
            address(0),
            PRICE,
            block.timestamp + DURATION
        );

        market.list(address(nft), 1, address(0), PRICE, DURATION);

        vm.stopPrank();
    }

    function test_List_RevertIf_ZeroPrice() public {
        vm.startPrank(seller);

        vm.expectRevert(Market.InvalidPrice.selector);
        market.list(address(nft), 1, address(0), 0, DURATION);

        vm.stopPrank();
    }

    function test_List_RevertIf_ZeroDuration() public {
        vm.startPrank(seller);

        vm.expectRevert(Market.InvalidExpiration.selector);
        market.list(address(nft), 1, address(0), PRICE, 0);

        vm.stopPrank();
    }

    function test_List_RevertIf_NotOwner() public {
        vm.startPrank(buyer);

        vm.expectRevert(Market.NotOwner.selector);
        market.list(address(nft), 1, address(0), PRICE, DURATION);

        vm.stopPrank();
    }

    function test_List_RevertIf_NotApproved() public {
        vm.startPrank(seller);
        nft.setApprovalForAll(address(market), false);

        vm.expectRevert(Market.NotApproved.selector);
        market.list(address(nft), 1, address(0), PRICE, DURATION);

        vm.stopPrank();
    }

    function test_List_UpdatesFloorPrice() public {
        vm.startPrank(seller);

        market.list(address(nft), 1, address(0), PRICE, DURATION);

        Market.Collection memory collection = market.getCollection(address(nft));
        assertEq(collection.floorPrice, PRICE);

        vm.stopPrank();
    }

    function test_CancelListing_Success() public {
        vm.startPrank(seller);

        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);
        market.cancelListing(listingId);

        Market.Listing memory listing = market.getListing(listingId);
        assertFalse(listing.active);

        vm.stopPrank();
    }

    function test_CancelListing_RevertIf_NotSeller() public {
        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert(Market.NotSeller.selector);
        market.cancelListing(listingId);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PURCHASE TESTS (Native Token)
    // ═══════════════════════════════════════════════════════════════════════

    function test_Buy_NativeToken_Success() public {
        // List NFT
        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);
        vm.stopPrank();

        // Calculate expected amounts
        uint256 protocolFee = (PRICE * 250) / 10000; // 2.5%
        uint256 sellerProceeds = PRICE - protocolFee;

        uint256 sellerBalanceBefore = seller.balance;
        uint256 treasuryBalanceBefore = market.DAO_TREASURY().balance;

        // Buy NFT
        vm.startPrank(buyer);
        market.buy{value: PRICE}(listingId);
        vm.stopPrank();

        // Verify NFT transferred
        assertEq(nft.ownerOf(1), buyer);

        // Verify payments
        assertEq(seller.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(market.DAO_TREASURY().balance, treasuryBalanceBefore + protocolFee);

        // Verify listing deactivated
        Market.Listing memory listing = market.getListing(listingId);
        assertFalse(listing.active);

        // Verify stats updated
        assertEq(market.totalVolume(), PRICE);
        assertEq(market.totalFeesCollected(), protocolFee);
    }

    function test_Buy_WithRoyalty_Success() public {
        // Mint NFT with royalty
        vm.startPrank(seller);
        uint256 tokenId = nftWithRoyalty.mint(seller);
        nftWithRoyalty.setApprovalForAll(address(market), true);

        bytes32 listingId = market.list(address(nftWithRoyalty), tokenId, address(0), PRICE, DURATION);
        vm.stopPrank();

        // Calculate expected amounts
        uint256 protocolFee = (PRICE * 250) / 10000; // 2.5%
        uint256 royaltyFee = (PRICE * 250) / 10000; // 2.5%
        uint256 sellerProceeds = PRICE - protocolFee - royaltyFee;

        uint256 royaltyBalanceBefore = royaltyRecipient.balance;

        // Buy NFT
        vm.startPrank(buyer);
        market.buy{value: PRICE}(listingId);
        vm.stopPrank();

        // Verify royalty paid
        assertEq(royaltyRecipient.balance, royaltyBalanceBefore + royaltyFee);
    }

    function test_Buy_RefundsExcess() public {
        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);
        vm.stopPrank();

        uint256 buyerBalanceBefore = buyer.balance;

        vm.startPrank(buyer);
        market.buy{value: PRICE + 1 ether}(listingId);
        vm.stopPrank();

        // Verify refund (should only spend PRICE + gas)
        assertLt(buyerBalanceBefore - buyer.balance, PRICE + 0.01 ether); // Allow for gas
    }

    function test_Buy_RevertIf_InsufficientPayment() public {
        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert(Market.InsufficientPayment.selector);
        market.buy{value: PRICE - 1}(listingId);
        vm.stopPrank();
    }

    function test_Buy_RevertIf_ListingExpired() public {
        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), PRICE, DURATION);
        vm.stopPrank();

        // Fast forward past expiration
        vm.warp(block.timestamp + DURATION + 1);

        vm.startPrank(buyer);
        vm.expectRevert(Market.ListingExpired.selector);
        market.buy{value: PRICE}(listingId);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PURCHASE TESTS (LRC20 Token)
    // ═══════════════════════════════════════════════════════════════════════

    function test_Buy_LRC20_Success() public {
        // List NFT for LUSD
        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(lusd), PRICE, DURATION);
        vm.stopPrank();

        // Approve market
        vm.startPrank(buyer);
        lusd.approve(address(market), PRICE);

        uint256 sellerBalanceBefore = lusd.balanceOf(seller);
        uint256 buyerBalanceBefore = lusd.balanceOf(buyer);

        // Buy NFT
        market.buy(listingId);
        vm.stopPrank();

        // Calculate expected amounts
        uint256 protocolFee = (PRICE * 250) / 10000;
        uint256 sellerProceeds = PRICE - protocolFee;

        // Verify NFT transferred
        assertEq(nft.ownerOf(1), buyer);

        // Verify payments
        assertEq(lusd.balanceOf(seller), sellerBalanceBefore + sellerProceeds);
        assertEq(lusd.balanceOf(buyer), buyerBalanceBefore - PRICE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OFFER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_MakeOffer_Success() public {
        vm.startPrank(buyer);
        lusd.approve(address(market), PRICE);

        bytes32 offerId = market.makeOffer(address(nft), 1, address(lusd), PRICE, DURATION);

        Market.Offer memory offer = market.getOffer(offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.nftContract, address(nft));
        assertEq(offer.tokenId, 1);
        assertEq(offer.paymentToken, address(lusd));
        assertEq(offer.amount, PRICE);
        assertTrue(offer.active);

        vm.stopPrank();
    }

    function test_MakeOffer_RevertIf_NativeToken() public {
        vm.startPrank(buyer);

        vm.expectRevert(Market.InvalidPrice.selector);
        market.makeOffer(address(nft), 1, address(0), PRICE, DURATION);

        vm.stopPrank();
    }

    function test_MakeOffer_RevertIf_InsufficientBalance() public {
        vm.startPrank(address(99)); // Address with no tokens

        vm.expectRevert(Market.InsufficientPayment.selector);
        market.makeOffer(address(nft), 1, address(lusd), PRICE, DURATION);

        vm.stopPrank();
    }

    function test_CancelOffer_Success() public {
        vm.startPrank(buyer);
        bytes32 offerId = market.makeOffer(address(nft), 1, address(lusd), PRICE, DURATION);
        market.cancelOffer(offerId);

        Market.Offer memory offer = market.getOffer(offerId);
        assertFalse(offer.active);

        vm.stopPrank();
    }

    function test_AcceptOffer_Success() public {
        // Buyer makes offer
        vm.startPrank(buyer);
        lusd.approve(address(market), PRICE);
        bytes32 offerId = market.makeOffer(address(nft), 1, address(lusd), PRICE, DURATION);
        vm.stopPrank();

        // Calculate expected amounts
        uint256 protocolFee = (PRICE * 250) / 10000;
        uint256 sellerProceeds = PRICE - protocolFee;

        uint256 sellerBalanceBefore = lusd.balanceOf(seller);

        // Seller accepts offer
        vm.startPrank(seller);
        market.acceptOffer(offerId);
        vm.stopPrank();

        // Verify NFT transferred
        assertEq(nft.ownerOf(1), buyer);

        // Verify payments
        assertEq(lusd.balanceOf(seller), sellerBalanceBefore + sellerProceeds);

        // Verify offer deactivated
        Market.Offer memory offer = market.getOffer(offerId);
        assertFalse(offer.active);
    }

    function test_AcceptOffer_RevertIf_NotOwner() public {
        vm.startPrank(buyer);
        bytes32 offerId = market.makeOffer(address(nft), 1, address(lusd), PRICE, DURATION);
        vm.stopPrank();

        vm.startPrank(address(99));
        vm.expectRevert(Market.NotOwner.selector);
        market.acceptOffer(offerId);
        vm.stopPrank();
    }

    function test_AcceptOffer_RevertIf_Expired() public {
        vm.startPrank(buyer);
        bytes32 offerId = market.makeOffer(address(nft), 1, address(lusd), PRICE, DURATION);
        vm.stopPrank();

        // Fast forward past expiration
        vm.warp(block.timestamp + DURATION + 1);

        vm.startPrank(seller);
        vm.expectRevert(Market.OfferExpired.selector);
        market.acceptOffer(offerId);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_SetCollectionVerified() public {
        vm.startPrank(owner);
        market.setCollectionVerified(address(nft), true);

        Market.Collection memory collection = market.getCollection(address(nft));
        assertTrue(collection.verified);

        vm.stopPrank();
    }

    function test_SetPaused() public {
        vm.startPrank(owner);
        market.setPaused(true);
        assertTrue(market.paused());
        vm.stopPrank();

        // Test that listing fails when paused
        vm.startPrank(seller);
        vm.expectRevert(Market.MarketPaused.selector);
        market.list(address(nft), 1, address(0), PRICE, DURATION);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_List(uint256 price, uint256 duration) public {
        vm.assume(price > 0 && price < type(uint128).max);
        vm.assume(duration > 0 && duration < 365 days);

        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), price, duration);

        Market.Listing memory listing = market.getListing(listingId);
        assertEq(listing.price, price);
        assertEq(listing.expiration, block.timestamp + duration);

        vm.stopPrank();
    }

    function testFuzz_Buy(uint256 price) public {
        vm.assume(price > 0 && price < 100 ether);

        vm.startPrank(seller);
        bytes32 listingId = market.list(address(nft), 1, address(0), price, DURATION);
        vm.stopPrank();

        vm.deal(buyer, price * 2);

        vm.startPrank(buyer);
        market.buy{value: price}(listingId);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), buyer);
    }
}

/**
 * @title LRC1155Test
 * @notice Comprehensive tests for LRC1155 multi-token
 */
contract LRC1155Test is Test {
    LRC1155 public token;

    address public owner = address(1);
    address public minter = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public royaltyRecipient = address(5);

    uint256 public constant TOKEN_ID_1 = 1;
    uint256 public constant TOKEN_ID_2 = 2;
    uint256 public constant AMOUNT = 100;

    function setUp() public {
        vm.startPrank(owner);
        token = new LRC1155(
            "Test Collection",
            "TEST",
            "https://example.com/metadata/",
            royaltyRecipient,
            250 // 2.5% royalty
        );
        token.grantRole(token.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINTING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Mint_Success() public {
        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");

        assertEq(token.balanceOf(user1, TOKEN_ID_1), AMOUNT);
        assertEq(token.totalSupply(TOKEN_ID_1), AMOUNT);

        vm.stopPrank();
    }

    function test_Mint_RevertIf_NotMinter() public {
        vm.startPrank(user1);

        vm.expectRevert();
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");

        vm.stopPrank();
    }

    function test_MintBatch_Success() public {
        vm.startPrank(minter);

        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = AMOUNT;
        amounts[1] = AMOUNT * 2;

        token.mintBatch(user1, ids, amounts, "");

        assertEq(token.balanceOf(user1, TOKEN_ID_1), AMOUNT);
        assertEq(token.balanceOf(user1, TOKEN_ID_2), AMOUNT * 2);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRANSFER TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Transfer_Success() public {
        // Mint tokens
        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");
        vm.stopPrank();

        // Transfer
        vm.startPrank(user1);
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, 50, "");

        assertEq(token.balanceOf(user1, TOKEN_ID_1), 50);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), 50);

        vm.stopPrank();
    }

    function test_TransferBatch_Success() public {
        // Mint tokens
        vm.startPrank(minter);
        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = AMOUNT;
        amounts[1] = AMOUNT * 2;

        token.mintBatch(user1, ids, amounts, "");
        vm.stopPrank();

        // Transfer batch
        vm.startPrank(user1);
        uint256[] memory transferAmounts = new uint256[](2);
        transferAmounts[0] = 50;
        transferAmounts[1] = 100;

        token.safeBatchTransferFrom(user1, user2, ids, transferAmounts, "");

        assertEq(token.balanceOf(user2, TOKEN_ID_1), 50);
        assertEq(token.balanceOf(user2, TOKEN_ID_2), 100);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // APPROVAL TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_ApprovalForAll_Success() public {
        vm.startPrank(user1);
        token.setApprovalForAll(user2, true);

        assertTrue(token.isApprovedForAll(user1, user2));

        vm.stopPrank();
    }

    function test_TransferFrom_WithApproval() public {
        // Mint tokens
        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");
        vm.stopPrank();

        // Approve user2
        vm.startPrank(user1);
        token.setApprovalForAll(user2, true);
        vm.stopPrank();

        // User2 transfers on behalf of user1
        vm.startPrank(user2);
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, 50, "");

        assertEq(token.balanceOf(user2, TOKEN_ID_1), 50);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BURNING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Burn_Success() public {
        // Mint tokens
        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");
        vm.stopPrank();

        // Burn
        vm.startPrank(user1);
        token.burn(user1, TOKEN_ID_1, 50);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), 50);
        assertEq(token.totalSupply(TOKEN_ID_1), 50);

        vm.stopPrank();
    }

    function test_BurnBatch_Success() public {
        // Mint tokens
        vm.startPrank(minter);
        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = AMOUNT;
        amounts[1] = AMOUNT * 2;

        token.mintBatch(user1, ids, amounts, "");
        vm.stopPrank();

        // Burn batch
        vm.startPrank(user1);
        uint256[] memory burnAmounts = new uint256[](2);
        burnAmounts[0] = 50;
        burnAmounts[1] = 100;

        token.burnBatch(user1, ids, burnAmounts);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), 50);
        assertEq(token.balanceOf(user1, TOKEN_ID_2), 100);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // URI TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_URI_Default() public {
        string memory uri = token.uri(TOKEN_ID_1);
        assertEq(uri, "https://example.com/metadata/");
    }

    function test_SetTokenURI() public {
        vm.startPrank(owner);
        token.setTokenURI(TOKEN_ID_1, "https://custom.com/1.json");

        string memory uri = token.uri(TOKEN_ID_1);
        assertEq(uri, "https://custom.com/1.json");

        vm.stopPrank();
    }

    function test_SetURI_RevertIf_NotAuthorized() public {
        vm.startPrank(user1);

        vm.expectRevert();
        token.setURI("https://newbase.com/");

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROYALTY TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Royalty_DefaultRoyalty() public {
        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(TOKEN_ID_1, 1000);

        assertEq(receiver, royaltyRecipient);
        assertEq(royaltyAmount, 25); // 2.5% of 1000
    }

    function test_Royalty_SetTokenRoyalty() public {
        vm.startPrank(owner);
        token.setTokenRoyalty(TOKEN_ID_1, user1, 500); // 5%

        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(TOKEN_ID_1, 1000);

        assertEq(receiver, user1);
        assertEq(royaltyAmount, 50); // 5% of 1000

        vm.stopPrank();
    }

    function test_SupportsInterface() public {
        assertTrue(token.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(token.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PAUSABLE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_Pause_Success() public {
        vm.startPrank(owner);
        token.pause();
        assertTrue(token.paused());
        vm.stopPrank();
    }

    function test_Transfer_RevertIf_Paused() public {
        // Mint tokens
        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");
        vm.stopPrank();

        // Pause
        vm.startPrank(owner);
        token.pause();
        vm.stopPrank();

        // Attempt transfer
        vm.startPrank(user1);
        vm.expectRevert();
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, 50, "");
        vm.stopPrank();
    }

    function test_Unpause_Success() public {
        vm.startPrank(owner);
        token.pause();
        token.unpause();
        assertFalse(token.paused());
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_Mint(uint256 tokenId, uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        vm.startPrank(minter);
        token.mint(user1, tokenId, amount, "");

        assertEq(token.balanceOf(user1, tokenId), amount);
        assertEq(token.totalSupply(tokenId), amount);

        vm.stopPrank();
    }

    function testFuzz_Transfer(uint256 amount) public {
        vm.assume(amount > 0 && amount <= AMOUNT);

        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");
        vm.stopPrank();

        vm.startPrank(user1);
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, amount, "");

        assertEq(token.balanceOf(user1, TOKEN_ID_1), AMOUNT - amount);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), amount);

        vm.stopPrank();
    }

    function testFuzz_Burn(uint256 amount) public {
        vm.assume(amount > 0 && amount <= AMOUNT);

        vm.startPrank(minter);
        token.mint(user1, TOKEN_ID_1, AMOUNT, "");
        vm.stopPrank();

        vm.startPrank(user1);
        token.burn(user1, TOKEN_ID_1, amount);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), AMOUNT - amount);
        assertEq(token.totalSupply(TOKEN_ID_1), AMOUNT - amount);

        vm.stopPrank();
    }

    function testFuzz_Royalty(uint256 salePrice) public {
        vm.assume(salePrice > 0 && salePrice < type(uint128).max);

        (address receiver, uint256 royaltyAmount) = token.royaltyInfo(TOKEN_ID_1, salePrice);

        assertEq(receiver, royaltyRecipient);
        assertEq(royaltyAmount, (salePrice * 250) / 10000);
    }
}
