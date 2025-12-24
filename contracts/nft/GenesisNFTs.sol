// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Lux Industries Inc.
pragma solidity ^0.8.31;

/**
    ██╗     ██╗   ██╗██╗  ██╗     ██████╗ ███████╗███╗   ██╗███████╗███████╗██╗███████╗
    ██║     ██║   ██║╚██╗██╔╝    ██╔════╝ ██╔════╝████╗  ██║██╔════╝██╔════╝██║██╔════╝
    ██║     ██║   ██║ ╚███╔╝     ██║  ███╗█████╗  ██╔██╗ ██║█████╗  ███████╗██║███████╗
    ██║     ██║   ██║ ██╔██╗     ██║   ██║██╔══╝  ██║╚██╗██║██╔══╝  ╚════██║██║╚════██║
    ███████╗╚██████╔╝██╔╝ ██╗    ╚██████╔╝███████╗██║ ╚████║███████╗███████║██║███████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝     ╚═════╝ ╚══════╝╚═╝  ╚═══╝╚══════╝╚══════╝╚═╝╚══════╝

    GenesisNFTs - Genesis NFT collection for Lux ecosystem
    Migrated from Ethereum to Lux C-Chain with LRC721 standard
    
    PERMANENT LUX LOCKING:
    - Each Genesis NFT has 1 billion LUX permanently locked
    - LUX backing can NEVER be unlocked (permanent lockup)
    - Staking rewards flow to current NFT holder
    - NFT can be transferred; new holder receives future rewards
    
    Migration from Ethereum collection: 0x31e0f919c67cedd2bc3e294340dc900735810311
*/

import {LRC721} from "../tokens/LRC721/LRC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ILRC20
 * @notice Minimal LRC20 interface for token transfers
 */
interface ILRC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title ILuxV2Pair
 * @notice Interface to query AMM reserves for dynamic pricing
 */
interface ILuxV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

/**
 * @title IGenesisMarket
 * @notice Interface for marketplace integration
 */
interface IGenesisMarket {
    struct BidShares {
        uint256 creator;    // Creator's share (basis points)
        uint256 owner;      // Owner's share (basis points)
        uint256 protocol;   // Protocol's share (basis points)
    }

    function configure(address mediaContract) external;
    function setBidShares(uint256 tokenId, BidShares calldata bidShares) external;
    function isValidBidShares(BidShares calldata bidShares) external pure returns (bool);
}

/**
 * @title IStakingRewards
 * @notice Interface for staking rewards source
 */
interface IStakingRewards {
    function claimRewardsFor(address recipient, uint256 lockedAmount) external returns (uint256);
    function pendingRewards(uint256 lockedAmount) external view returns (uint256);
}

/**
 * @title GenesisNFTs
 * @author Lux Network
 * @notice Genesis NFT collection with permanently locked LUX and staking rewards
 * @dev Preserves Zora-style content/metadata URIs and marketplace integration
 * 
 * Token Tiers:
 * - Genesis: 1,000,000,000 LUX (1B) - $1M value
 * - Validator: 100,000,000 LUX (100M) - $100K value
 * - Mini: 10,000,000 LUX (10M) - $10K value
 * - Nano: 1,000,000 LUX (1M) - $1K value
 */
contract GenesisNFTs is LRC721, Ownable, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Amount of LUX locked per Genesis NFT (1 billion)
    uint256 public constant LUX_LOCKED_PER_NFT = 1_000_000_000 ether;
    
    /// @notice DAO Treasury (receives all sale proceeds)
    address payable public constant DAO_TREASURY = payable(0x9011E888251AB053B7bD1cdB598Db4f9DEd94714);

    /// @notice Ethereum genesis collection address
    address public constant ETH_GENESIS_CONTRACT = 0x31e0F919C67ceDd2Bc3E294340Dc900735810311;

    /// @notice Discount ends at 1% on Jan 1, 2026 (Unix timestamp)
    uint256 public constant DISCOUNT_END_TIMESTAMP = 1735689600;

    /// @notice Starting discount: 11% (1100 basis points)
    uint256 public constant START_DISCOUNT_BPS = 1100;

    /// @notice Ending discount: 1% (100 basis points)
    uint256 public constant END_DISCOUNT_BPS = 100;

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    enum NFTType {
        VALIDATOR,  // Validator NFT
        CARD,       // Membership card NFT
        COIN        // Collectible coin NFT
    }

    enum Tier {
        GENESIS,    // $1M - 1B LUX
        VALIDATOR,  // $100K - 100M LUX
        MINI,       // $10K - 10M LUX
        NANO        // $1K - 1M LUX
    }

    struct MediaData {
        string tokenURI;      // Combined URI (IPFS/Arweave)
        string contentURI;    // Direct content URI (legacy compatibility)
        string metadataURI;   // Metadata URI (legacy compatibility)
        bytes32 contentHash;  // SHA256 hash of content
        bytes32 metadataHash; // SHA256 hash of metadata
    }

    struct TokenMeta {
        NFTType nftType;      // NFT type (validator/card/coin)
        Tier tier;            // Tier (genesis/validator/mini/nano)
        string name;          // Token name
        uint256 originTokenId; // Original Ethereum token ID
        uint256 luxLocked;    // Amount of LUX locked (PERMANENT)
        uint256 timestamp;    // Creation timestamp
        bool reserved;        // Reserved for future use
    }

    struct RewardInfo {
        uint256 claimedRewards;     // Total rewards claimed by this token
        uint256 lastClaimTimestamp; // Last claim timestamp
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Marketplace contract
    address public market;

    /// @notice Staking rewards source contract
    IStakingRewards public stakingRewards;

    /// @notice WLUX token for rewards
    ILRC20 public wlux;

    /// @notice LUSD stablecoin for purchases
    ILRC20 public lusd;

    /// @notice LUX/LUSD AMM pair for dynamic pricing
    ILuxV2Pair public luxLusdPair;

    /// @notice Which token in the pair is LUX (true = token0, false = token1)
    bool public luxIsToken0;

    /// @notice Timestamp when sales opened (used for time-based discount calculation)
    uint256 public salesStartTimestamp;

    /// @notice Token ID => Media Data
    mapping(uint256 => MediaData) public mediaData;

    /// @notice Token ID => Token Metadata
    mapping(uint256 => TokenMeta) public tokenMeta;

    /// @notice Token ID => Reward Info
    mapping(uint256 => RewardInfo) public rewardInfo;

    /// @notice Token ID => Creator address
    mapping(uint256 => address) public tokenCreators;

    /// @notice Content hash => Token ID (prevents duplicate content)
    mapping(bytes32 => uint256) public contentToToken;

    /// @notice Original Ethereum token ID => C-Chain token ID
    mapping(uint256 => uint256) public originToToken;

    /// @notice Total LUX locked across all NFTs (PERMANENT)
    uint256 public totalLuxLocked;

    /// @notice Next token ID
    uint256 private _nextTokenId;

    /// @notice Whether migration is complete
    bool public migrationComplete;

    /// @notice Whether public sales are open
    bool public salesOpen;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event TokenMinted(
        uint256 indexed tokenId,
        address indexed creator,
        NFTType nftType,
        Tier tier,
        uint256 luxLocked
    );

    event TokenMigrated(
        uint256 indexed newTokenId,
        uint256 indexed originTokenId,
        address indexed holder,
        uint256 luxLocked
    );

    event RewardsClaimed(
        uint256 indexed tokenId,
        address indexed holder,
        uint256 amount
    );

    event StakingRewardsSet(address indexed stakingRewards);
    event MarketSet(address indexed market);
    event MigrationCompleted();

    event TokenPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        NFTType nftType,
        Tier tier,
        uint256 price
    );

    event SalesOpened(uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error ContentAlreadyExists();
    error MigrationAlreadyComplete();
    error MigrationNotComplete();
    error InvalidMarket();
    error InvalidMediaData();
    error InvalidStakingRewards();
    error NoRewardsAvailable();
    error OnlyTokenHolder();
    error LuxCannotBeUnlocked();
    error SalesNotOpen();
    error TransferFailed();


    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize GenesisNFTs
     * @param baseURI_ Base URI for metadata
     * @param royaltyReceiver Royalty receiver address
     * @param royaltyBps Royalty in basis points (250 = 2.5%)
     * @param wlux_ WLUX token address
     * @param lusd_ LUSD stablecoin address
     * @param luxLusdPair_ LUX/LUSD AMM pair for dynamic pricing
     */
    constructor(
        string memory baseURI_,
        address royaltyReceiver,
        uint96 royaltyBps,
        address wlux_,
        address lusd_,
        address luxLusdPair_
    )
        LRC721("Lux Genesis", "GENESIS", baseURI_, royaltyReceiver, royaltyBps)
        Ownable(msg.sender)
    {
        wlux = ILRC20(wlux_);
        lusd = ILRC20(lusd_);
        luxLusdPair = ILuxV2Pair(luxLusdPair_);
        
        // Determine which token in pair is LUX (WLUX)
        luxIsToken0 = (luxLusdPair.token0() == wlux_);

        // Grant admin roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MIGRATION (Admin only, one-time)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Migrate tokens from Ethereum snapshot
     * @dev 1:1 migration from Ethereum - holders keep their NFTs
     * @param holders Array of holder addresses from Ethereum
     * @param originTokenIds Array of original Ethereum token IDs
     * @param uris Array of token URIs
     * @param contentHashes Array of content hashes
     * @param metadataHashes Array of metadata hashes
     * @param nftTypes Array of NFT types
     * @param tiers Array of tiers
     * @param names Array of token names
     */
    function migrateTokens(
        address[] calldata holders,
        uint256[] calldata originTokenIds,
        string[] calldata uris,
        bytes32[] calldata contentHashes,
        bytes32[] calldata metadataHashes,
        NFTType[] calldata nftTypes,
        Tier[] calldata tiers,
        string[] calldata names
    ) external onlyRole(MINTER_ROLE) {
        if (migrationComplete) revert MigrationAlreadyComplete();

        uint256 len = holders.length;
        require(
            len == originTokenIds.length &&
            len == uris.length &&
            len == contentHashes.length &&
            len == metadataHashes.length &&
            len == nftTypes.length &&
            len == tiers.length &&
            len == names.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < len; i++) {
            _migrateToken(
                holders[i],
                originTokenIds[i],
                uris[i],
                contentHashes[i],
                metadataHashes[i],
                nftTypes[i],
                tiers[i],
                names[i]
            );
        }
    }

    function _migrateToken(
        address holder,
        uint256 originTokenId,
        string calldata uri,
        bytes32 contentHash,
        bytes32 metadataHash,
        NFTType nftType,
        Tier tier,
        string calldata name
    ) internal {
        uint256 tokenId = _nextTokenId++;

        // 1:1 mapping - mint directly to ETH holder for crypto continuity
        uint256 luxLocked = _getLuxForTier(tier);

        _safeMint(holder, tokenId);
        _setTokenURI(tokenId, uri);

        mediaData[tokenId] = MediaData({
            tokenURI: uri,
            contentURI: uri,
            metadataURI: uri,
            contentHash: contentHash,
            metadataHash: metadataHash
        });

        tokenMeta[tokenId] = TokenMeta({
            nftType: nftType,
            tier: tier,
            name: name,
            originTokenId: originTokenId,
            luxLocked: luxLocked,
            timestamp: block.timestamp,
            reserved: false
        });

        rewardInfo[tokenId] = RewardInfo({
            claimedRewards: 0,
            lastClaimTimestamp: block.timestamp
        });

        tokenCreators[tokenId] = holder;
        originToToken[originTokenId] = tokenId;
        totalLuxLocked += luxLocked;

        if (contentHash != bytes32(0)) {
            contentToToken[contentHash] = tokenId;
        }

        emit TokenMigrated(tokenId, originTokenId, holder, luxLocked);
    }

    /**
     * @notice Get LUX amount for a tier
     */
    function _getLuxForTier(Tier tier) internal pure returns (uint256) {
        if (tier == Tier.GENESIS) return 1_000_000_000 ether;   // 1B LUX
        if (tier == Tier.VALIDATOR) return 100_000_000 ether;   // 100M LUX
        if (tier == Tier.MINI) return 10_000_000 ether;         // 10M LUX
        if (tier == Tier.NANO) return 1_000_000 ether;          // 1M LUX
        return 0;
    }

    /**
     * @notice Complete migration and lock migration functions
     */
    function completeMigration() external onlyOwner {
        migrationComplete = true;
        emit MigrationCompleted();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STAKING REWARDS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim staking rewards for an NFT
     * @dev Only current holder can claim rewards
     * @param tokenId Token ID to claim rewards for
     */
    function claimRewards(uint256 tokenId) external nonReentrant returns (uint256) {
        if (ownerOf(tokenId) != msg.sender) revert OnlyTokenHolder();
        if (address(stakingRewards) == address(0)) revert InvalidStakingRewards();

        TokenMeta memory meta = tokenMeta[tokenId];
        
        // Claim rewards from staking contract based on locked LUX
        uint256 rewards = stakingRewards.claimRewardsFor(msg.sender, meta.luxLocked);
        
        if (rewards == 0) revert NoRewardsAvailable();

        // Update reward info
        rewardInfo[tokenId].claimedRewards += rewards;
        rewardInfo[tokenId].lastClaimTimestamp = block.timestamp;

        emit RewardsClaimed(tokenId, msg.sender, rewards);
        
        return rewards;
    }

    /**
     * @notice Get pending rewards for an NFT
     * @param tokenId Token ID to check
     */
    function pendingRewards(uint256 tokenId) external view returns (uint256) {
        if (address(stakingRewards) == address(0)) return 0;
        
        TokenMeta memory meta = tokenMeta[tokenId];
        return stakingRewards.pendingRewards(meta.luxLocked);
    }

    /**
     * @notice Set staking rewards contract
     */
    function setStakingRewards(address stakingRewards_) external onlyOwner {
        if (stakingRewards_ == address(0)) revert InvalidStakingRewards();
        stakingRewards = IStakingRewards(stakingRewards_);
        emit StakingRewardsSet(stakingRewards_);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LUX LOCKING (PERMANENT - NO UNLOCK)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice LUX locked in Genesis NFTs can NEVER be unlocked
     * @dev This function always reverts - it exists to make the intent clear
     */
    function unlockLux(uint256 /*tokenId*/) external pure {
        revert LuxCannotBeUnlocked();
    }

    /**
     * @notice Get total LUX locked for an address (sum of all their NFTs)
     */
    function luxLockedForAddress(address holder) external view returns (uint256 total) {
        uint256 balance = balanceOf(holder);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(holder, i);
            total += tokenMeta[tokenId].luxLocked;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MINTING (Post-migration)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint a new token (post-migration)
     * @param to Recipient address
     * @param data Media data for the token
     * @param nftType NFT type
     * @param tier Token tier
     * @param name Token name
     */
    function mintToken(
        address to,
        MediaData calldata data,
        NFTType nftType,
        Tier tier,
        string calldata name
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (!migrationComplete) revert MigrationNotComplete();
        if (bytes(data.contentURI).length == 0) revert InvalidMediaData();

        // Check for duplicate content
        if (data.contentHash != bytes32(0) && contentToToken[data.contentHash] != 0) {
            revert ContentAlreadyExists();
        }

        uint256 tokenId = _nextTokenId++;
        uint256 luxLocked = _getLuxForTier(tier);

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, data.tokenURI);

        mediaData[tokenId] = data;
        tokenMeta[tokenId] = TokenMeta({
            nftType: nftType,
            tier: tier,
            name: name,
            originTokenId: 0,
            luxLocked: luxLocked,
            timestamp: block.timestamp,
            reserved: false
        });

        rewardInfo[tokenId] = RewardInfo({
            claimedRewards: 0,
            lastClaimTimestamp: block.timestamp
        });

        tokenCreators[tokenId] = msg.sender;
        totalLuxLocked += luxLocked;

        if (data.contentHash != bytes32(0)) {
            contentToToken[data.contentHash] = tokenId;
        }

        emit TokenMinted(tokenId, msg.sender, nftType, tier, luxLocked);

        return tokenId;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PUBLIC SALES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Buy a Genesis NFT with LUSD (discounted market price from AMM)
     * @dev Price = current LUX price on AMM minus discount. Proceeds go to DAO_TREASURY.
     * @param nftType Type of NFT (Validator, Card, Coin)
     * @param tier Tier (Genesis, Validator, Mini, Nano)
     * @param name Custom name for the NFT
     */
    function buy(
        NFTType nftType,
        Tier tier,
        string calldata name
    ) external nonReentrant returns (uint256) {
        if (!salesOpen) revert SalesNotOpen();
        if (!migrationComplete) revert MigrationNotComplete();

        // Get current LUX price from AMM with discount applied
        uint256 price = getDiscountedPrice();

        // Transfer LUSD from buyer to DAO Treasury
        bool success = lusd.transferFrom(msg.sender, DAO_TREASURY, price);
        if (!success) revert TransferFailed();

        uint256 tokenId = _nextTokenId++;
        uint256 luxLocked = _getLuxForTier(tier);

        _safeMint(msg.sender, tokenId);

        // Default media data for purchased NFTs
        string memory defaultURI = string(abi.encodePacked("ipfs://genesis/", _toString(tokenId)));
        
        mediaData[tokenId] = MediaData({
            tokenURI: defaultURI,
            contentURI: defaultURI,
            metadataURI: defaultURI,
            contentHash: bytes32(0),
            metadataHash: bytes32(0)
        });

        tokenMeta[tokenId] = TokenMeta({
            nftType: nftType,
            tier: tier,
            name: name,
            originTokenId: 0,
            luxLocked: luxLocked,
            timestamp: block.timestamp,
            reserved: false
        });

        rewardInfo[tokenId] = RewardInfo({
            claimedRewards: 0,
            lastClaimTimestamp: block.timestamp
        });

        tokenCreators[tokenId] = msg.sender;
        totalLuxLocked += luxLocked;

        emit TokenPurchased(tokenId, msg.sender, nftType, tier, price);

        return tokenId;
    }

    /**
     * @notice Get current LUX price in LUSD from AMM
     * @dev Queries LUX/LUSD pair reserves to calculate spot price
     * @return Price of 1 LUX in LUSD (18 decimals)
     */
    function getLuxPrice() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = luxLusdPair.getReserves();
        
        if (luxIsToken0) {
            // LUX is token0, LUSD is token1
            // Price = LUSD reserve / LUX reserve
            return (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else {
            // LUX is token1, LUSD is token0
            // Price = LUSD reserve / LUX reserve
            return (uint256(reserve0) * 1e18) / uint256(reserve1);
        }
    }

    /**
     * @notice Get current discount percentage based on elapsed time
     * @dev Linear interpolation from 11% (start) to 1% (Jan 1, 2026)
     * @return Current discount in basis points
     */
    function getCurrentDiscount() public view returns (uint256) {
        // If sales haven't started, return starting discount
        if (salesStartTimestamp == 0) return START_DISCOUNT_BPS;
        
        // If past end date, return ending discount (1%)
        if (block.timestamp >= DISCOUNT_END_TIMESTAMP) return END_DISCOUNT_BPS;
        
        // Linear interpolation: starts at 11%, ends at 1%
        uint256 elapsed = block.timestamp - salesStartTimestamp;
        uint256 totalDuration = DISCOUNT_END_TIMESTAMP - salesStartTimestamp;
        uint256 discountRange = START_DISCOUNT_BPS - END_DISCOUNT_BPS; // 1000 bps (10%)
        
        // Discount decreases linearly over time
        uint256 discountReduction = (elapsed * discountRange) / totalDuration;
        return START_DISCOUNT_BPS - discountReduction;
    }

    /**
     * @notice Get discounted price for NFT purchases
     * @dev Market price minus time-based discount (starts 11%, descends to 1% by Jan 1 2026)
     * @return Discounted price in LUSD (18 decimals)
     */
    function getDiscountedPrice() public view returns (uint256) {
        uint256 marketPrice = getLuxPrice();
        uint256 discount = getCurrentDiscount();
        // Apply discount: price * (10000 - discount) / 10000
        return (marketPrice * (10000 - discount)) / 10000;
    }

    /**
     * @notice Open or close public sales
     * @dev When sales open, sets salesStartTimestamp for discount calculation
     */
    function setSalesOpen(bool open) external onlyOwner {
        salesOpen = open;
        // Set start timestamp when sales first open (for discount calculation)
        if (open && salesStartTimestamp == 0) {
            salesStartTimestamp = block.timestamp;
        }
    }

    /**
     * @notice Update the AMM pair used for pricing (admin only)
     * @param newPair New LUX/LUSD pair address
     * @param wluxAddress WLUX token address to determine token order
     */
    function setLuxLusdPair(address newPair, address wluxAddress) external onlyOwner {
        luxLusdPair = ILuxV2Pair(newPair);
        luxIsToken0 = (luxLusdPair.token0() == wluxAddress);
    }

    /**
     * @notice Convert uint to string (for URI generation)
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARKET INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set marketplace contract
     */
    function setMarket(address market_) external onlyOwner {
        if (market_ == address(0)) revert InvalidMarket();
        market = market_;
        emit MarketSet(market_);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEWS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get token by original Ethereum ID
     */
    function getTokenByOrigin(uint256 originTokenId) external view returns (uint256) {
        return originToToken[originTokenId];
    }

    /**
     * @notice Get full token data
     */
    function getToken(uint256 tokenId) external view returns (
        address owner,
        address creator,
        MediaData memory data,
        TokenMeta memory meta,
        RewardInfo memory rewards
    ) {
        owner = ownerOf(tokenId);
        creator = tokenCreators[tokenId];
        data = mediaData[tokenId];
        meta = tokenMeta[tokenId];
        rewards = rewardInfo[tokenId];
    }

    /**
     * @notice Get total supply
     */
    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set token URI (admin function)
     */
    function setTokenURI(uint256 tokenId, string memory uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenURI(tokenId, uri);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(LRC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
