// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Registry
 * @author Lux Industries Inc
 * @notice Multi-chain DID Registry for the Lux ecosystem
 * @dev Manages decentralized identities across Lux, Pars, Zoo, and Hanzo chains
 *
 * DID Formats:
 *   did:lux:alice   - W3C DID method (canonical, for protocols)
 *   alice[at]lux.id - Display format (user-friendly, like email)
 *
 * Supported Networks:
 * - Lux:   did:lux:alice   / alice[at]lux.id
 * - Pars:  did:pars:alice  / alice[at]pars.id
 * - Zoo:   did:zoo:alice   / alice[at]zoo.id
 * - Hanzo: did:hanzo:alice / alice[at]hanzo.id
 *
 * Features:
 * - Stake-based identity registration
 * - NFT-bound identity ownership
 * - Encryption/signature key storage
 * - Custom records (social links, etc.)
 * - Delegation system for voting power
 * - Cross-chain identity resolution
 */
interface IIdentityNFT {
    function mint(address to) external returns (uint256);
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract Registry is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable {

    // ═══════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════

    struct ClaimParams {
        string name;           // Username (alphanumeric, 1-63 chars)
        uint256 chainId;       // Target chain namespace
        uint256 stakeAmount;   // Tokens to stake
        address owner;         // Identity owner
        string referrer;       // Referrer DID (for discount)
    }

    struct IdentityData {
        uint256 boundNft;           // NFT token ID
        uint256 stakedTokens;       // Staked amount
        string encryptionKey;       // Public encryption key
        string signatureKey;        // Public signature key
        bool routing;               // Direct address vs proxy
        string[] nodes;             // Node addresses or proxy nodes
        uint256 delegatedTokens;    // Tokens delegated to others
        uint256 lastUpdated;        // Last update timestamp
    }

    struct Delegation {
        string delegatee;      // DID of delegatee
        uint256 amount;        // Delegated amount
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Staking token (ASHA, ZOO, etc.)
    IERC20 public stakingToken;

    /// @notice Identity NFT contract
    IIdentityNFT public identityNft;

    /// @notice Chain ID to DID method (e.g., 96369 => "lux")
    mapping(uint256 => string) public methods;

    /// @notice Chain ID to display domain (e.g., 96369 => "lux.id")
    mapping(uint256 => string) public domains;

    /// @notice DID => owner address
    mapping(string => address) private _owners;

    /// @notice NFT token ID => DID
    mapping(uint256 => string) public tokenToDID;

    /// @notice DID => identity data
    mapping(string => IdentityData) private _data;

    /// @notice DID => key => value (custom records)
    mapping(string => mapping(string => string)) public records;

    /// @notice DID => delegatee DID => amount
    mapping(string => mapping(string => uint256)) public delegations;

    /// @notice DID => list of delegatees
    mapping(string => string[]) private _delegatees;

    /// @notice Pricing tiers (in wei, 18 decimals)
    uint256 public price1Char;
    uint256 public price2Char;
    uint256 public price3Char;
    uint256 public price4Char;
    uint256 public price5PlusChar;
    uint256 public referrerDiscountBps;

    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════

    event IdentityClaimed(string indexed did, uint256 indexed nftId, address indexed owner);
    event IdentityUnclaimed(string indexed did, uint256 indexed nftId);
    event KeysUpdated(string indexed did, string encryptionKey, string signatureKey);
    event NodesUpdated(string indexed did, bool routing, string[] nodes);
    event StakeUpdated(string indexed did, uint256 newStake);
    event DelegationsUpdated(string indexed did, Delegation[] delegations);
    event RecordsUpdated(string indexed did, string[] keys, string[] values);
    event PricingUpdated(uint256 p1, uint256 p2, uint256 p3, uint256 p4, uint256 p5, uint256 discount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════

    error IdentityNotAvailable(string did);
    error InvalidName(string name);
    error InvalidChain(uint256 chainId);
    error InvalidReferrer(string referrer);
    error InsufficientStake();
    error Unauthorized();
    error InputMismatch();

    // ═══════════════════════════════════════════════════════════════════════
    // INITIALIZER
    // ═══════════════════════════════════════════════════════════════════════

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address stakingToken_,
        address identityNft_
    ) public initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        stakingToken = IERC20(stakingToken_);
        identityNft = IIdentityNFT(identityNft_);

        // Initialize chain namespaces
        // Lux ecosystem
        methods[96369] = "lux";
        domains[96369] = "lux.id";
        methods[96368] = "lux-test";
        domains[96368] = "test.lux.id";

        // Pars ecosystem
        methods[494949] = "pars";
        domains[494949] = "pars.id";
        methods[494950] = "pars-test";
        domains[494950] = "test.pars.id";

        // Zoo ecosystem
        methods[200200] = "zoo";
        domains[200200] = "zoo.id";
        methods[200201] = "zoo-test";
        domains[200201] = "test.zoo.id";

        // Hanzo ecosystem
        methods[36963] = "hanzo";
        domains[36963] = "hanzo.id";
        methods[36962] = "hanzo-test";
        domains[36962] = "test.hanzo.id";

        // Development
        methods[31337] = "local";
        domains[31337] = "local.id";

        // Pricing tiers (in staking token units)
        price1Char = 100000 * 1e18;     // 100,000 tokens
        price2Char = 10000 * 1e18;      // 10,000 tokens
        price3Char = 1000 * 1e18;       // 1,000 tokens
        price4Char = 100 * 1e18;        // 100 tokens
        price5PlusChar = 10 * 1e18;     // 10 tokens
        referrerDiscountBps = 5000;     // 50% discount
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ═══════════════════════════════════════════════════════════════════════
    // CLAIM / UNCLAIM
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Claim a new DID
     * @param params Claim parameters
     */
    function claim(ClaimParams calldata params) external returns (string memory did) {
        // Validate name
        if (!_validName(params.name)) revert InvalidName(params.name);

        // Validate chain
        if (bytes(methods[params.chainId]).length == 0) revert InvalidChain(params.chainId);

        // Construct canonical DID: did:lux:alice
        did = string(abi.encodePacked("did:", methods[params.chainId], ":", params.name));

        // Check availability
        if (_owners[did] != address(0)) revert IdentityNotAvailable(did);

        // Calculate stake requirement
        bool validReferrer = bytes(params.referrer).length > 0 && _owners[params.referrer] != address(0);
        uint256 required = stakeRequirement(params.name, validReferrer);
        if (params.stakeAmount < required) revert InsufficientStake();

        // Transfer stake
        stakingToken.transferFrom(msg.sender, address(this), params.stakeAmount);

        // Mint NFT
        uint256 nftId = identityNft.mint(params.owner);

        // Store data
        _owners[did] = params.owner;
        tokenToDID[nftId] = did;
        _data[did] = IdentityData({
            boundNft: nftId,
            stakedTokens: params.stakeAmount,
            encryptionKey: "",
            signatureKey: "",
            routing: false,
            nodes: new string[](0),
            delegatedTokens: 0,
            lastUpdated: block.timestamp
        });

        emit IdentityClaimed(did, nftId, params.owner);
        emit StakeUpdated(did, params.stakeAmount);
    }

    /**
     * @notice Unclaim (release) a DID
     * @param did DID to unclaim
     */
    function unclaim(string calldata did) external {
        _requireOwner(did);

        IdentityData storage data = _data[did];
        uint256 nftId = data.boundNft;

        // Return staked tokens
        if (data.stakedTokens > 0) {
            stakingToken.transfer(msg.sender, data.stakedTokens);
        }

        // Burn NFT
        identityNft.burn(nftId);

        // Clear data
        delete _owners[did];
        delete tokenToDID[nftId];
        delete _data[did];
        delete _delegatees[did];

        emit IdentityUnclaimed(did, nftId);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IDENTITY DATA
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set encryption and signature keys
     */
    function setKeys(
        string calldata did,
        string calldata encryptionKey,
        string calldata signatureKey
    ) external {
        _requireOwner(did);

        IdentityData storage data = _data[did];
        data.encryptionKey = encryptionKey;
        data.signatureKey = signatureKey;
        data.lastUpdated = block.timestamp;

        emit KeysUpdated(did, encryptionKey, signatureKey);
    }

    /**
     * @notice Set node routing
     */
    function setNodes(
        string calldata did,
        bool routing,
        string[] calldata nodes
    ) external {
        _requireOwner(did);

        IdentityData storage data = _data[did];
        data.routing = routing;
        data.nodes = nodes;
        data.lastUpdated = block.timestamp;

        emit NodesUpdated(did, routing, nodes);
    }

    /**
     * @notice Increase stake
     */
    function increaseStake(string calldata did, uint256 amount) external {
        _requireOwner(did);

        stakingToken.transferFrom(msg.sender, address(this), amount);

        IdentityData storage data = _data[did];
        data.stakedTokens += amount;
        data.lastUpdated = block.timestamp;

        emit StakeUpdated(did, data.stakedTokens);
    }

    /**
     * @notice Update custom records
     */
    function updateRecords(
        string calldata did,
        string[] calldata keys,
        string[] calldata values
    ) external {
        _requireOwner(did);
        if (keys.length != values.length) revert InputMismatch();

        for (uint256 i = 0; i < keys.length; i++) {
            records[did][keys[i]] = values[i];
        }

        emit RecordsUpdated(did, keys, values);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Get owner of a DID
     */
    function ownerOf(string calldata did) external view returns (address) {
        return _owners[did];
    }

    /**
     * @notice Get canonical DID format: did:lux:alice
     */
    function getDID(string calldata name, uint256 chainId) public view returns (string memory) {
        return string(abi.encodePacked("did:", methods[chainId], ":", name));
    }

    /**
     * @notice Get display format: alice@lux.id
     */
    function getDisplayId(string calldata name, uint256 chainId) public view returns (string memory) {
        return string(abi.encodePacked(name, "@", domains[chainId]));
    }

    /**
     * @notice Get identity data
     */
    function getData(string calldata did) external view returns (IdentityData memory) {
        return _data[did];
    }

    /**
     * @notice Calculate stake requirement for a name
     */
    function stakeRequirement(string calldata name, bool hasReferrer) public view returns (uint256) {
        uint256 length = bytes(name).length;
        uint256 base;

        if (length == 1) base = price1Char;
        else if (length == 2) base = price2Char;
        else if (length == 3) base = price3Char;
        else if (length == 4) base = price4Char;
        else base = price5PlusChar;

        return hasReferrer ? (base * (10000 - referrerDiscountBps)) / 10000 : base;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Add or update a chain namespace
     */
    function setChain(uint256 chainId, string calldata method, string calldata domain) external onlyOwner {
        methods[chainId] = method;
        domains[chainId] = domain;
    }

    /**
     * @notice Update pricing
     */
    function setPricing(
        uint256 p1, uint256 p2, uint256 p3, uint256 p4, uint256 p5,
        uint256 discountBps
    ) external onlyOwner {
        require(discountBps <= 10000, "Invalid discount");
        price1Char = p1;
        price2Char = p2;
        price3Char = p3;
        price4Char = p4;
        price5PlusChar = p5;
        referrerDiscountBps = discountBps;
        emit PricingUpdated(p1, p2, p3, p4, p5, discountBps);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════

    function _requireOwner(string memory did) internal view {
        if (_owners[did] != msg.sender) revert Unauthorized();
    }

    /**
     * @notice Validate name (alphanumeric + underscore, 1-63 chars)
     */
    function _validName(string calldata name) internal pure returns (bool) {
        bytes memory b = bytes(name);
        if (b.length == 0 || b.length > 63) return false;

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            bool valid = (c >= 0x30 && c <= 0x39) ||  // 0-9
                        (c >= 0x41 && c <= 0x5A) ||   // A-Z
                        (c >= 0x61 && c <= 0x7A) ||   // a-z
                        (c == 0x5F);                   // _
            if (!valid) return false;
        }
        return true;
    }
}
