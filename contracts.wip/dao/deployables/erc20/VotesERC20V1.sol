// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {
    IVotesERC20V1
} from "../../interfaces/dao/deployables/IVotesERC20V1.sol";
import {IVersion} from "../../interfaces/dao/deployables/IVersion.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Permit
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IDeploymentBlock} from "../../interfaces/dao/IDeploymentBlock.sol";
import {
    DeploymentBlockInitializable
} from "../../DeploymentBlockInitializable.sol";
import {InitializerEventEmitter} from "../../InitializerEventEmitter.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    NoncesUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title VotesERC20V1
 * @author Lux Industriesn Inc
 * @notice Implementation of governance token with voting and transfer restrictions
 * @dev This contract implements IVotesERC20V1, providing a flexible governance
 * token with optional transfer locking and voting delegation features.
 *
 * Implementation details:
 * - Uses EIP-7201 namespaced storage pattern for upgradeability
 * - Implements UUPS upgradeable pattern with admin-restricted upgrades
 * - Extends ERC20Votes for governance compatibility
 * - Supports ERC20Permit for gasless approvals
 * - Role-based access control for minting and transfers
 * - Optional transfer locking with role-based overrides
 *
 * Key features:
 * - Can be locked to prevent transfers (except for whitelisted addresses)
 * - Maximum supply cap enforcement
 * - Timestamp-based voting snapshots
 * - Burn functionality available to all holders
 *
 * Roles:
 * - DEFAULT_ADMIN_ROLE: Can lock/unlock, set max supply, upgrade
 * - MINTER_ROLE: Can mint new tokens up to max supply
 * - TRANSFER_FROM_ROLE: Can transfer when locked
 * - TRANSFER_TO_ROLE: Can receive transfers when locked
 *
 * @custom:security-contact security@lux.network
 */
contract VotesERC20V1 is
    IVotesERC20V1,
    IVersion,
    ERC20VotesUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    DeploymentBlockInitializable,
    InitializerEventEmitter,
    ERC165
{
    // ======================================================================
    // STATE VARIABLES
    // ======================================================================

    /**
     * @notice Main storage struct for VotesERC20V1 following EIP-7201
     * @dev Storage struct containing token configuration state
     * @custom:storage-location erc7201:DAO.VotesERC20.main
     */
    struct VotesERC20Storage {
        /** @notice Whether token transfers are locked */
        bool locked;
        /** @notice Whether token minting is renounced */
        bool mintingRenounced;
        /** @notice Maximum total supply cap for the token */
        uint256 maxTotalSupply;
        /** @notice Timestamp when the token was last unlocked */
        uint48 unlockTime;
    }

    /**
     * @dev Storage slot for VotesERC20Storage calculated using EIP-7201 formula:
     * keccak256(abi.encode(uint256(keccak256("DAO.VotesERC20.main")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant VOTES_ERC20_STORAGE_LOCATION =
        0x57c985480a3f326e09e0fd6059ce967a04828718ff6302d3fa09f8d24851e200;

    /**
     * @dev Returns the storage struct for VotesERC20V1
     * Following the EIP-7201 namespaced storage pattern to avoid storage collisions
     * @return $ The storage struct for VotesERC20V1
     */
    function _getVotesERC20Storage()
        internal
        pure
        returns (VotesERC20Storage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VOTES_ERC20_STORAGE_LOCATION
        }
    }

    /** @notice Role that allows transferring tokens when locked */
    bytes32 public constant TRANSFER_FROM_ROLE =
        keccak256("TRANSFER_FROM_ROLE");

    /** @notice Role that allows receiving tokens when locked */
    bytes32 public constant TRANSFER_TO_ROLE = keccak256("TRANSFER_TO_ROLE");

    /** @notice Role that allows minting new tokens */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    /**
     * @notice Modifier to check if transfers are allowed
     * @dev Reverts if token is locked and neither address has transfer roles
     * @param from_ The address transferring tokens
     * @param to_ The address receiving tokens
     */
    modifier isTransferable(address from_, address to_) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        if (
            $.locked &&
            // overrides while locked
            !hasRole(TRANSFER_FROM_ROLE, from_) && // whitelisted addresses can always transfer
            !hasRole(TRANSFER_TO_ROLE, to_)
        ) {
            revert IsLocked();
        }
        _;
    }

    // ======================================================================
    // CONSTRUCTOR & INITIALIZERS
    // ======================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IVotesERC20V1
     * @dev Initializes all inherited contracts and sets up initial token distribution.
     * Grants the owner admin and minter roles. Also grants special transfer roles:
     * - Owner gets TRANSFER_FROM_ROLE to always allow transfers
     * - address(0) gets TRANSFER_FROM_ROLE to allow minting when locked
     * - address(0) gets TRANSFER_TO_ROLE to allow burning when locked
     */
    function initialize(
        Metadata calldata metadata_,
        Allocation[] calldata allocations_,
        address owner_,
        bool locked_,
        uint256 maxTotalSupply_
    ) public virtual override initializer {
        __InitializerEventEmitter_init(
            abi.encode(
                metadata_,
                allocations_,
                owner_,
                locked_,
                maxTotalSupply_
            )
        );
        __ERC20_init(metadata_.name, metadata_.symbol);
        __ERC20Permit_init(metadata_.name);
        __ERC20Votes_init();
        __UUPSUpgradeable_init();
        __DeploymentBlockInitializable_init();
        __AccessControl_init();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(MINTER_ROLE, owner_);

        // Owner can always transfer when locked
        _grantRole(TRANSFER_FROM_ROLE, owner_);

        // Allow minting when locked (from address(0))
        _grantRole(TRANSFER_FROM_ROLE, address(0));

        // Allow burning when locked (to address(0))
        _grantRole(TRANSFER_TO_ROLE, address(0));

        // Set token configuration
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        $.locked = locked_;
        $.maxTotalSupply = maxTotalSupply_;

        // Process initial allocations
        uint256 holderCount = allocations_.length;
        for (uint256 i; i < holderCount; ) {
            _mint(allocations_[i].to, allocations_[i].amount);
            unchecked {
                ++i;
            }
        }
    }

    // ======================================================================
    // UUPSUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev Restricts upgrades to DEFAULT_ADMIN_ROLE
     */
    function _authorizeUpgrade(
        address newImplementation_
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {
        // solhint-disable-previous-line no-empty-blocks
        // Intentionally empty - authorization logic handled by onlyRole modifier
    }

    // ======================================================================
    // IVotesERC20V1
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVotesERC20V1
     */
    function CLOCK_MODE()
        // solhint-disable-previous-line func-name-mixedcase
        public
        pure
        virtual
        override(IVotesERC20V1, VotesUpgradeable)
        returns (string memory)
    {
        return "mode=timestamp";
    }

    // --- View Functions ---

    /**
     * @inheritdoc IVotesERC20V1
     */
    function clock()
        public
        view
        virtual
        override(IVotesERC20V1, VotesUpgradeable)
        returns (uint48)
    {
        return uint48(block.timestamp);
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function locked() public view virtual override returns (bool) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        return $.locked;
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function mintingRenounced() public view virtual override returns (bool) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        return $.mintingRenounced;
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function maxTotalSupply() public view virtual override returns (uint256) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        return $.maxTotalSupply;
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function getUnlockTime() public view virtual override returns (uint48) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        return $.unlockTime;
    }

    // --- State-Changing Functions ---

    /**
     * @inheritdoc IVotesERC20V1
     */
    function lock(
        bool locked_
    ) public virtual override onlyRole(DEFAULT_ADMIN_ROLE) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        if (locked_ && !$.locked) {
            revert LockFromUnlockedState();
        }
        if (!locked_) {
            $.unlockTime = uint48(block.timestamp);
        }
        $.locked = locked_;
        emit Locked(locked_);
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function renounceMinting()
        public
        virtual
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        if (!$.mintingRenounced) {
            $.mintingRenounced = true;
            emit MintingRenounced();
        }
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function setMaxTotalSupply(
        uint256 newMaxTotalSupply_
    ) public virtual override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMaxTotalSupply_ < totalSupply()) {
            revert InvalidMaxTotalSupply();
        }

        VotesERC20Storage storage $ = _getVotesERC20Storage();
        $.maxTotalSupply = newMaxTotalSupply_;
        emit MaxTotalSupplyUpdated(newMaxTotalSupply_);
    }

    /**
     * @inheritdoc IVotesERC20V1
     * @dev Minted tokens are automatically delegated to the recipient
     * through the ERC20Votes _update hook.
     */
    function mint(
        address to_,
        uint256 amount_
    ) public virtual override onlyRole(MINTER_ROLE) {
        VotesERC20Storage storage $ = _getVotesERC20Storage();
        if ($.mintingRenounced) {
            revert MintingDisabled();
        }

        uint256 newTotalSupply = totalSupply() + amount_;

        if (newTotalSupply > $.maxTotalSupply) {
            revert ExceedMaxTotalSupply();
        }

        _mint(to_, amount_);
    }

    /**
     * @inheritdoc IVotesERC20V1
     */
    function burn(uint256 amount_) public virtual override {
        _burn(msg.sender, amount_);
    }

    // ======================================================================
    // ERC20VotesUpgradeable
    // ======================================================================

    // --- Internal Functions ---

    /**
     * @inheritdoc ERC20VotesUpgradeable
     * @dev Overrides both ERC20Upgradeable and ERC20VotesUpgradeable to add
     * transfer restrictions via the isTransferable modifier.
     */
    function _update(
        address from_,
        address to_,
        uint256 value_
    )
        internal
        virtual
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
        isTransferable(from_, to_)
    {
        super._update(from_, to_, value_);
    }

    // ======================================================================
    // NoncesUpgradeable
    // ======================================================================

    // --- View Functions ---

    /**
     * @notice Returns the current nonce for an address (for permit)
     * @dev Overrides both ERC20PermitUpgradeable and NoncesUpgradeable
     * @param owner_ The address to get the nonce for
     * @return The current nonce
     */
    function nonces(
        address owner_
    )
        public
        view
        virtual
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner_);
    }

    // ======================================================================
    // IVersion
    // ======================================================================

    // --- Pure Functions ---

    /**
     * @inheritdoc IVersion
     */
    function version() public pure virtual override returns (uint16) {
        return 1;
    }

    // ======================================================================
    // ERC165
    // ======================================================================

    // --- View Functions ---

    /**
     * @inheritdoc ERC165
     * @dev Supports IVotesERC20V1, IERC20, IERC20Permit, IVotes, IVersion,
     * IDeploymentBlock, IAccessControl, and IERC165
     */
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC165)
        returns (bool)
    {
        return
            interfaceId_ == type(IVotesERC20V1).interfaceId ||
            interfaceId_ == type(IERC20).interfaceId ||
            interfaceId_ == type(IERC20Permit).interfaceId ||
            interfaceId_ == type(IVotes).interfaceId ||
            interfaceId_ == type(IVersion).interfaceId ||
            interfaceId_ == type(IDeploymentBlock).interfaceId ||
            interfaceId_ == type(IAccessControl).interfaceId ||
            super.supportsInterface(interfaceId_);
    }
}
