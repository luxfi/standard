// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IIdentity } from "./interfaces/IIdentity.sol";
import { IClaimIssuer } from "./interfaces/IClaimIssuer.sol";
import { IdentityStorage } from "./storage/IdentityStorage.sol";

/// @title Identity — ERC-734 + ERC-735 (ONCHAINID) UUPS-upgradeable.
/// @notice Ported from the OnchainID reference impl v2.2.1 and adapted to:
///         - OpenZeppelin v5 upgradeable primitives (`Initializable`, `UUPSUpgradeable`)
///         - Solidity ^0.8.20 (custom errors instead of revert strings where it
///           matters; events + storage layout preserved)
///         - UUPS upgrade gating: management keys (purpose 1) authorize.
contract Identity is Initializable, UUPSUpgradeable, IdentityStorage, IIdentity {
    /// @custom:storage-location erc7201:lux.identity.canInteract
    bool internal _canInteract;

    error CallToImplementationForbidden();
    error PermissionsManagementKey();
    error PermissionsClaimKey();
    error ZeroAddress();

    modifier delegatedOnly() {
        if (!_canInteract) revert CallToImplementationForbidden();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != address(this) && !keyHasPurpose(keccak256(abi.encode(msg.sender)), 1)) {
            revert PermissionsManagementKey();
        }
        _;
    }

    modifier onlyClaimKey() {
        if (msg.sender != address(this) && !keyHasPurpose(keccak256(abi.encode(msg.sender)), 3)) {
            revert PermissionsClaimKey();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the identity for the first time on a fresh proxy.
    /// @param initialManagementKey Address whose hashed form (`keccak256(abi.encode(addr))`)
    ///        becomes the seed MANAGEMENT (purpose 1) key. Required by ERC-734.
    function initialize(address initialManagementKey) public initializer {
        if (initialManagementKey == address(0)) revert ZeroAddress();
        // UUPSUpgradeable v5 has no init function
        _canInteract = true;

        bytes32 _key = keccak256(abi.encode(initialManagementKey));
        _keys[_key].key = _key;
        _keys[_key].purposes = [uint256(1)];
        _keys[_key].keyType = 1;
        _keysByPurpose[1].push(_key);
        emit KeyAdded(_key, 1, 1);
    }

    /// @dev Only a MANAGEMENT key (purpose 1) holder may upgrade. This is the
    ///      same trust boundary that controls the rest of the identity.
    function _authorizeUpgrade(address) internal view override onlyManager {}

    // -------- ERC-734 --------

    function execute(address _to, uint256 _value, bytes memory _data)
        external
        payable
        override
        delegatedOnly
        returns (uint256 executionId)
    {
        uint256 _executionId = _executionNonce;
        _executions[_executionId].to = _to;
        _executions[_executionId].value = _value;
        _executions[_executionId].data = _data;
        unchecked {
            _executionNonce = _executionId + 1;
        }
        emit ExecutionRequested(_executionId, _to, _value, _data);

        if (keyHasPurpose(keccak256(abi.encode(msg.sender)), 1)) {
            approve(_executionId, true);
        } else if (_to != address(this) && keyHasPurpose(keccak256(abi.encode(msg.sender)), 2)) {
            approve(_executionId, true);
        }
        return _executionId;
    }

    function approve(uint256 _id, bool _approve) public override delegatedOnly returns (bool success) {
        require(_id < _executionNonce, "Cannot approve a non-existing execution");
        require(!_executions[_id].executed, "Request already executed");

        if (_executions[_id].to == address(this)) {
            require(keyHasPurpose(keccak256(abi.encode(msg.sender)), 1), "Sender does not have management key");
        } else {
            require(keyHasPurpose(keccak256(abi.encode(msg.sender)), 2), "Sender does not have action key");
        }

        emit Approved(_id, _approve);

        if (_approve) {
            _executions[_id].approved = true;
            // solhint-disable-next-line avoid-low-level-calls
            (success,) = _executions[_id].to.call{ value: _executions[_id].value }(_executions[_id].data);
            if (success) {
                _executions[_id].executed = true;
                emit Executed(_id, _executions[_id].to, _executions[_id].value, _executions[_id].data);
                return true;
            } else {
                emit ExecutionFailed(_id, _executions[_id].to, _executions[_id].value, _executions[_id].data);
                return false;
            }
        } else {
            _executions[_id].approved = false;
        }
        return false;
    }

    function addKey(bytes32 _key, uint256 _purpose, uint256 _type)
        public
        override
        delegatedOnly
        onlyManager
        returns (bool)
    {
        if (_keys[_key].key == _key) {
            uint256[] memory purposes = _keys[_key].purposes;
            for (uint256 i = 0; i < purposes.length; i++) {
                if (purposes[i] == _purpose) revert("Conflict: Key already has purpose");
            }
            _keys[_key].purposes.push(_purpose);
        } else {
            _keys[_key].key = _key;
            _keys[_key].purposes = _arr(_purpose);
            _keys[_key].keyType = _type;
        }
        _keysByPurpose[_purpose].push(_key);
        emit KeyAdded(_key, _purpose, _type);
        return true;
    }

    function removeKey(bytes32 _key, uint256 _purpose)
        public
        override
        delegatedOnly
        onlyManager
        returns (bool)
    {
        require(_keys[_key].key == _key, "NonExisting: Key isn't registered");
        uint256[] memory purposes = _keys[_key].purposes;
        uint256 purposeIndex;
        while (purposes[purposeIndex] != _purpose) {
            purposeIndex++;
            if (purposeIndex == purposes.length) revert("NonExisting: Key doesn't have such purpose");
        }
        purposes[purposeIndex] = purposes[purposes.length - 1];
        _keys[_key].purposes = purposes;
        _keys[_key].purposes.pop();

        uint256 keyIndex;
        uint256 arrayLength = _keysByPurpose[_purpose].length;
        while (_keysByPurpose[_purpose][keyIndex] != _key) {
            keyIndex++;
            if (keyIndex >= arrayLength) break;
        }
        _keysByPurpose[_purpose][keyIndex] = _keysByPurpose[_purpose][arrayLength - 1];
        _keysByPurpose[_purpose].pop();

        uint256 keyType = _keys[_key].keyType;
        if (purposes.length - 1 == 0) delete _keys[_key];
        emit KeyRemoved(_key, _purpose, keyType);
        return true;
    }

    function getKey(bytes32 _key)
        external
        view
        override
        returns (uint256[] memory purposes, uint256 keyType, bytes32 key)
    {
        return (_keys[_key].purposes, _keys[_key].keyType, _keys[_key].key);
    }

    function getKeyPurposes(bytes32 _key) external view override returns (uint256[] memory) {
        return _keys[_key].purposes;
    }

    function getKeysByPurpose(uint256 _purpose) external view override returns (bytes32[] memory) {
        return _keysByPurpose[_purpose];
    }

    function keyHasPurpose(bytes32 _key, uint256 _purpose) public view override returns (bool) {
        Key memory key = _keys[_key];
        if (key.key == 0) return false;
        for (uint256 i = 0; i < key.purposes.length; i++) {
            uint256 purpose = key.purposes[i];
            if (purpose == 1 || purpose == _purpose) return true;
        }
        return false;
    }

    // -------- ERC-735 --------

    function addClaim(
        uint256 _topic,
        uint256 _scheme,
        address _issuer,
        bytes memory _signature,
        bytes memory _data,
        string memory _uri
    ) public override delegatedOnly onlyClaimKey returns (bytes32) {
        if (_issuer != address(this)) {
            require(
                IClaimIssuer(_issuer).isClaimValid(IIdentity(address(this)), _topic, _signature, _data),
                "invalid claim"
            );
        }
        bytes32 claimId = keccak256(abi.encode(_issuer, _topic));
        _claims[claimId].topic = _topic;
        _claims[claimId].scheme = _scheme;
        _claims[claimId].signature = _signature;
        _claims[claimId].data = _data;
        _claims[claimId].uri = _uri;

        if (_claims[claimId].issuer != _issuer) {
            _claimsByTopic[_topic].push(claimId);
            _claims[claimId].issuer = _issuer;
            emit ClaimAdded(claimId, _topic, _scheme, _issuer, _signature, _data, _uri);
        } else {
            emit ClaimChanged(claimId, _topic, _scheme, _issuer, _signature, _data, _uri);
        }
        return claimId;
    }

    function removeClaim(bytes32 _claimId) public override delegatedOnly onlyClaimKey returns (bool) {
        uint256 _topic = _claims[_claimId].topic;
        if (_topic == 0) revert("NonExisting: There is no claim with this ID");

        uint256 claimIndex;
        uint256 arrayLength = _claimsByTopic[_topic].length;
        while (_claimsByTopic[_topic][claimIndex] != _claimId) {
            claimIndex++;
            if (claimIndex >= arrayLength) break;
        }
        _claimsByTopic[_topic][claimIndex] = _claimsByTopic[_topic][arrayLength - 1];
        _claimsByTopic[_topic].pop();

        emit ClaimRemoved(
            _claimId,
            _topic,
            _claims[_claimId].scheme,
            _claims[_claimId].issuer,
            _claims[_claimId].signature,
            _claims[_claimId].data,
            _claims[_claimId].uri
        );
        delete _claims[_claimId];
        return true;
    }

    function getClaim(bytes32 _claimId)
        public
        view
        override
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        )
    {
        return (
            _claims[_claimId].topic,
            _claims[_claimId].scheme,
            _claims[_claimId].issuer,
            _claims[_claimId].signature,
            _claims[_claimId].data,
            _claims[_claimId].uri
        );
    }

    function getClaimIdsByTopic(uint256 _topic) external view override returns (bytes32[] memory) {
        return _claimsByTopic[_topic];
    }

    /// @notice Self-attested claims (`issuer == this`) are valid as long as
    ///         their signature recovers to a key with CLAIM purpose (3).
    function isClaimValid(IIdentity _identity, uint256 claimTopic, bytes memory sig, bytes memory data)
        public
        view
        virtual
        override
        returns (bool)
    {
        bytes32 dataHash = keccak256(abi.encode(_identity, claimTopic, data));
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        address recovered = getRecoveredAddress(sig, prefixedHash);
        bytes32 hashedAddr = keccak256(abi.encode(recovered));
        return keyHasPurpose(hashedAddr, 3);
    }

    function getRecoveredAddress(bytes memory sig, bytes32 dataHash) public pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(dataHash, v, r, s);
    }

    function _arr(uint256 a) private pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = a;
    }

    function version() external pure returns (string memory) {
        return "lux-onchainid-1.0.0";
    }
}
