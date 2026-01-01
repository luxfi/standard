// SPDX-License-Identifier: MIT
// IFHE.sol - Lux Network FHE Interface Definitions
// All FHE precompile interfaces and type definitions
pragma solidity >=0.8.13 <0.9.0;

// ===== Precompile Addresses =====
// FHE precompiles are deployed in the 0x80+ (128+) address range

library Precompiles {
    //solhint-disable const-name-snakecase
    /// @notice Main FHE operations precompile (in Lux reserved range 0x02...)
    address public constant Fheos = 0x0200000000000000000000000000000000000080;
    /// @notice Access Control List precompile
    address public constant ACL = 0x0200000000000000000000000000000000000081;
    /// @notice Input Verifier precompile
    address public constant InputVerifier = 0x0200000000000000000000000000000000000082;
    /// @notice Decryption Gateway precompile
    address public constant Gateway = 0x0200000000000000000000000000000000000083;
}

// ===== FHE Operations Interface =====
// Low-level interface to the FHE precompile at address 128 (0x80)

interface IFheOps {
    function log(string memory s) external pure;
    function add(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function verify(uint8 utype, bytes memory input, int32 securityZone) external pure returns (bytes memory);
    function sealOutput(uint8 utype, bytes memory ctHash, bytes memory pk) external pure returns (string memory);
    function decrypt(uint8 utype, bytes memory input, uint256 defaultValue) external pure returns (uint256);
    function lte(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function sub(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function mul(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function lt(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function select(uint8 utype, bytes memory controlHash, bytes memory ifTrueHash, bytes memory ifFalseHash) external pure returns (bytes memory);
    function req(uint8 utype, bytes memory input) external pure returns (bytes memory);
    function cast(uint8 utype, bytes memory input, uint8 toType) external pure returns (bytes memory);
    function trivialEncrypt(bytes memory input, uint8 toType, int32 securityZone) external pure returns (bytes memory);
    function div(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function gt(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function gte(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function rem(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function and(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function or(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function xor(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function eq(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function ne(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function min(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function max(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function shl(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function shr(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function rol(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function ror(uint8 utype, bytes memory lhsHash, bytes memory rhsHash) external pure returns (bytes memory);
    function not(uint8 utype, bytes memory value) external pure returns (bytes memory);
    function random(uint8 utype, uint64 seed, int32 securityZone) external pure returns (bytes memory);
    function getNetworkPublicKey(int32 securityZone) external pure returns (bytes memory);
    function square(uint8 utype, bytes memory value) external pure returns (bytes memory);
}

// ===== Encrypted Input Types =====

struct EncryptedInput {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

// Sealed output types for typed decryption
struct SealedBool {
    bytes data;
}

struct SealedUint {
    bytes data;
    uint8 utype;
}

struct SealedAddress {
    bytes data;
}

// Encrypted input structs (PascalCase)
struct Ebool {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Euint8 {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Euint16 {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Euint32 {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Euint64 {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Euint128 {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Euint256 {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

struct Eaddress {
    uint256 ctHash;
    uint8 securityZone;
    uint8 utype;
    bytes signature;
}

// Order is set as in fheos/precompiles/types/types.go
enum FunctionId {
    _0,             // 0 - GetNetworkKey
    _1,             // 1 - Verify
    cast,           // 2
    sealoutput,     // 3
    select,         // 4 - select
    _5,             // 5 - req
    decrypt,        // 6
    sub,            // 7
    add,            // 8
    xor,            // 9
    and,            // 10
    or,             // 11
    not,            // 12
    div,            // 13
    rem,            // 14
    mul,            // 15
    shl,            // 16
    shr,            // 17
    gte,            // 18
    lte,            // 19
    lt,             // 20
    gt,             // 21
    min,            // 22
    max,            // 23
    eq,             // 24
    ne,             // 25
    trivialEncrypt, // 26
    random,         // 27
    rol,            // 28
    ror,            // 29
    square,         // 30
    _31             // 31
}

interface IFHENetwork {
    function createTask(uint8 returnType, FunctionId funcId, uint256[] memory encryptedInputs, uint256[] memory extraInputs) external returns (uint256);
    function createRandomTask(uint8 returnType, uint256 seed, int32 securityZone) external returns (uint256);

    function createDecryptTask(uint256 ctHash, address requestor) external;
    function verifyInput(EncryptedInput memory input, address sender) external returns (uint256);

    function allow(uint256 ctHash, address account) external;
    function isAllowed(uint256 ctHash, address account) external returns (bool);
    function allowGlobal(uint256 ctHash) external;
    function allowTransient(uint256 ctHash, address account) external;
    function revealSafe(uint256 ctHash) external view returns (uint256, bool);
    function reveal(uint256 ctHash) external view returns (uint256);
}

library Utils {
    // Values used to communicate types to the runtime.
    // Must match values defined in warp-drive protobufs for everything to
    uint8 internal constant EUINT8_TFHE = 2;
    uint8 internal constant EUINT16_TFHE = 3;
    uint8 internal constant EUINT32_TFHE = 4;
    uint8 internal constant EUINT64_TFHE = 5;
    uint8 internal constant EUINT128_TFHE = 6;
    uint8 internal constant EUINT256_TFHE = 8;
    uint8 internal constant EADDRESS_TFHE = 7;
    uint8 internal constant EBOOL_TFHE = 0;

    function functionIdToString(FunctionId _functionId) internal pure returns (string memory) {
        if (_functionId == FunctionId.cast) return "cast";
        if (_functionId == FunctionId.sealoutput) return "sealOutput";
        if (_functionId == FunctionId.select) return "select";
        if (_functionId == FunctionId.decrypt) return "decrypt";
        if (_functionId == FunctionId.sub) return "sub";
        if (_functionId == FunctionId.add) return "add";
        if (_functionId == FunctionId.xor) return "xor";
        if (_functionId == FunctionId.and) return "and";
        if (_functionId == FunctionId.or) return "or";
        if (_functionId == FunctionId.not) return "not";
        if (_functionId == FunctionId.div) return "div";
        if (_functionId == FunctionId.rem) return "rem";
        if (_functionId == FunctionId.mul) return "mul";
        if (_functionId == FunctionId.shl) return "shl";
        if (_functionId == FunctionId.shr) return "shr";
        if (_functionId == FunctionId.gte) return "gte";
        if (_functionId == FunctionId.lte) return "lte";
        if (_functionId == FunctionId.lt) return "lt";
        if (_functionId == FunctionId.gt) return "gt";
        if (_functionId == FunctionId.min) return "min";
        if (_functionId == FunctionId.max) return "max";
        if (_functionId == FunctionId.eq) return "eq";
        if (_functionId == FunctionId.ne) return "ne";
        if (_functionId == FunctionId.trivialEncrypt) return "trivialEncrypt";
        if (_functionId == FunctionId.random) return "random";
        if (_functionId == FunctionId.rol) return "rol";
        if (_functionId == FunctionId.ror) return "ror";
        if (_functionId == FunctionId.square) return "square";

        return "";
    }

    function inputFromEbool(Ebool memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EBOOL_TFHE,
            signature: input.signature
        });
    }

    function inputFromEuint8(Euint8 memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EUINT8_TFHE,
            signature: input.signature
        });
    }

    function inputFromEuint16(Euint16 memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EUINT16_TFHE,
            signature: input.signature
        });
    }

    function inputFromEuint32(Euint32 memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EUINT32_TFHE,
            signature: input.signature
        });
    }

    function inputFromEuint64(Euint64 memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EUINT64_TFHE,
            signature: input.signature
        });
    }

    function inputFromEuint128(Euint128 memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EUINT128_TFHE,
            signature: input.signature
        });
    }

    function inputFromEuint256(Euint256 memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EUINT256_TFHE,
            signature: input.signature
        });
    }

    function inputFromEaddress(Eaddress memory input) internal pure returns (EncryptedInput memory) {
        return EncryptedInput({
            ctHash: input.ctHash,
            securityZone: input.securityZone,
            utype: EADDRESS_TFHE,
            signature: input.signature
        });
    }
}