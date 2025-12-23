// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@luxfi/standard/lib/token/ERC1155/ERC1155.sol";
import "@luxfi/standard/lib/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@luxfi/standard/lib/token/ERC1155/extensions/ERC1155Pausable.sol";
import "@luxfi/standard/lib/token/ERC1155/extensions/ERC1155Supply.sol";
import "@luxfi/standard/lib/token/common/ERC2981.sol";
import "@luxfi/standard/lib/access/AccessControl.sol";

/**
 * @title LRC1155
 * @author Lux Network
 * @notice Lux Request for Comments 1155 - Multi-token standard
 * @dev Extends OpenZeppelin ERC1155 with:
 * - Burnable: Token burning capability
 * - Pausable: Emergency pause functionality
 * - Supply: Track total supply per token ID
 * - ERC2981: Royalty support
 * - AccessControl: Role-based permissions
 */
contract LRC1155 is
    ERC1155,
    ERC1155Burnable,
    ERC1155Pausable,
    ERC1155Supply,
    ERC2981,
    AccessControl
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");

    string public name;
    string public symbol;

    // Optional per-token URIs
    mapping(uint256 => string) private _tokenURIs;

    event TokenURISet(uint256 indexed tokenId, string uri);

    /**
     * @notice Constructor for LRC1155 token
     * @param name_ Collection name
     * @param symbol_ Collection symbol
     * @param baseURI_ Base URI for token metadata
     * @param royaltyReceiver Address to receive royalties
     * @param royaltyBps Royalty fee in basis points
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address royaltyReceiver,
        uint96 royaltyBps
    ) ERC1155(baseURI_) {
        name = name_;
        symbol = symbol_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(URI_SETTER_ROLE, msg.sender);

        if (royaltyReceiver != address(0) && royaltyBps > 0) {
            _setDefaultRoyalty(royaltyReceiver, royaltyBps);
        }
    }

    /**
     * @notice Set base URI for all tokens
     */
    function setURI(string memory newuri) public onlyRole(URI_SETTER_ROLE) {
        _setURI(newuri);
    }

    /**
     * @notice Set URI for specific token
     */
    function setTokenURI(uint256 tokenId, string memory tokenURI_) public onlyRole(URI_SETTER_ROLE) {
        _tokenURIs[tokenId] = tokenURI_;
        emit TokenURISet(tokenId, tokenURI_);
    }

    /**
     * @notice Get URI for specific token
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory tokenURI_ = _tokenURIs[tokenId];
        if (bytes(tokenURI_).length > 0) {
            return tokenURI_;
        }
        return super.uri(tokenId);
    }

    /**
     * @notice Mint tokens
     */
    function mint(address to, uint256 id, uint256 amount, bytes memory data)
        public
        onlyRole(MINTER_ROLE)
    {
        _mint(to, id, amount, data);
    }

    /**
     * @notice Batch mint tokens
     */
    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
        onlyRole(MINTER_ROLE)
    {
        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @notice Set default royalty for all tokens
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /**
     * @notice Set token-specific royalty
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ Required Overrides ============

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Pausable, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
