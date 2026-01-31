# Security Audit Report: DID Contracts

**Audited Contracts:**
- `contracts/did/Registry.sol`
- `contracts/did/IdentityNFT.sol`

**Audit Date:** 2026-01-30
**Auditor:** Trail of Bits-level Review
**Solidity Version:** ^0.8.31

---

## Executive Summary

The DID (Decentralized Identifier) contracts implement a multi-chain identity registry with stake-based registration, NFT-bound ownership, and delegation capabilities. The audit identified **2 Critical**, **4 High**, **5 Medium**, **4 Low**, and **6 Informational** issues.

### Findings Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 2 | Must Fix |
| High | 4 | Must Fix |
| Medium | 5 | Should Fix |
| Low | 4 | Consider Fixing |
| Informational | 6 | Best Practice |

---

## Critical Issues

### C-01: Reentrancy in `unclaim()` - Stake Returned Before State Cleared

**File:** `Registry.sol:251-272`

**Description:**
The `unclaim()` function transfers staked tokens to the caller before clearing state. If the staking token is a malicious ERC20 with a callback (e.g., ERC777), an attacker can re-enter and exploit inconsistent state.

```solidity
function unclaim(string calldata did) external {
    _requireOwner(did);

    IdentityData storage data = _data[did];
    uint256 nftId = data.boundNft;

    // VULNERABILITY: External call before state changes
    if (data.stakedTokens > 0) {
        stakingToken.transfer(msg.sender, data.stakedTokens);  // <-- External call
    }

    identityNft.burn(nftId);  // <-- Another external call

    // State cleared AFTER external calls
    delete _owners[did];
    delete tokenToDID[nftId];
    delete _data[did];
    delete _delegatees[did];
}
```

**Attack Scenario:**
1. Attacker claims DID with malicious ERC777-like token as staking token
2. Attacker calls `unclaim()`
3. On `transfer()`, token triggers callback to attacker
4. Attacker re-enters via another function while `_owners[did]` still points to them
5. Attacker can manipulate data or double-spend

**Recommendation:**
Apply Checks-Effects-Interactions pattern:

```solidity
function unclaim(string calldata did) external {
    _requireOwner(did);

    IdentityData storage data = _data[did];
    uint256 nftId = data.boundNft;
    uint256 stakeToReturn = data.stakedTokens;

    // Effects FIRST
    delete _owners[did];
    delete tokenToDID[nftId];
    delete _data[did];
    delete _delegatees[did];

    emit IdentityUnclaimed(did, nftId);

    // Interactions LAST
    identityNft.burn(nftId);
    if (stakeToReturn > 0) {
        stakingToken.transfer(msg.sender, stakeToReturn);
    }
}
```

Also consider adding `ReentrancyGuard` from OpenZeppelin.

---

### C-02: NFT Transfer Desynchronizes DID Ownership

**File:** `Registry.sol:229-230`, `IdentityNFT.sol:64-69`

**Description:**
The `_owners[did]` mapping in Registry and actual NFT ownership can become desynchronized. The NFT is transferable, but when transferred, the Registry's `_owners` mapping is not updated.

```solidity
// Registry stores owner separately
_owners[did] = params.owner;

// IdentityNFT is a standard ERC721 - fully transferable
_safeMint(to, tokenId);
```

**Attack Scenario:**
1. Alice claims `did:lux:alice`, becomes owner in both Registry and NFT
2. Alice transfers NFT to Bob via standard ERC721 `transferFrom()`
3. Registry still shows `_owners["did:lux:alice"] = Alice`
4. Alice can still call `unclaim()`, `setKeys()`, etc. even though Bob owns the NFT
5. Alice steals staked tokens; Bob loses NFT when Alice calls `unclaim()`

**Impact:** Complete identity theft, stake drainage, unauthorized identity modifications.

**Recommendation:**

Option A - Override NFT transfer to sync Registry:
```solidity
// In IdentityNFT.sol
function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
    address from = super._update(to, tokenId, auth);
    if (from != address(0) && to != address(0)) {
        // Notify registry of ownership change
        IRegistry(registry).syncOwnership(tokenId, to);
    }
    return from;
}
```

Option B - Make `_requireOwner()` check NFT ownership:
```solidity
function _requireOwner(string memory did) internal view {
    IdentityData storage data = _data[did];
    address nftOwner = identityNft.ownerOf(data.boundNft);
    if (nftOwner != msg.sender) revert Unauthorized();
}
```

Option B is simpler and recommended. The `_owners` mapping can be deprecated in favor of NFT ownership as the source of truth.

---

## High Severity Issues

### H-01: Missing Return Value Check on ERC20 Transfers

**File:** `Registry.sol:224, 259, 320`

**Description:**
The contract calls `transferFrom()` and `transfer()` without checking return values. Some ERC20 tokens (USDT, BNB) return `false` instead of reverting on failure.

```solidity
// Line 224 - No return check
stakingToken.transferFrom(msg.sender, address(this), params.stakeAmount);

// Line 259 - No return check
stakingToken.transfer(msg.sender, data.stakedTokens);

// Line 320 - No return check
stakingToken.transferFrom(msg.sender, address(this), amount);
```

**Impact:** Silent transfer failures leading to:
- Claims without actual stake being deposited
- State inconsistency between recorded stake and actual balance

**Recommendation:**
Use OpenZeppelin's `SafeERC20`:

```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

// Then use:
stakingToken.safeTransferFrom(msg.sender, address(this), params.stakeAmount);
stakingToken.safeTransfer(msg.sender, data.stakedTokens);
```

---

### H-02: Delegation Data Not Cleared on Unclaim - Delegation Accounting Corruption

**File:** `Registry.sol:269`

**Description:**
The `unclaim()` function deletes `_delegatees[did]` but does NOT clear the individual `delegations[did][delegatee]` mappings. This leaves orphaned delegation records.

```solidity
// Line 269 - Only clears the array, not the mapping entries
delete _delegatees[did];

// delegations[did][*] entries remain!
```

**Impact:**
- If the same DID is later reclaimed, old delegation amounts may be accessible
- Corrupts delegation accounting for governance calculations
- Could be exploited to resurrect old voting power

**Recommendation:**
Clear delegation mappings before deleting the array:

```solidity
string[] memory dels = _delegatees[did];
for (uint256 i = 0; i < dels.length; i++) {
    delete delegations[did][dels[i]];
}
delete _delegatees[did];
```

---

### H-03: Front-Running on `claim()` - Name Squatting

**File:** `Registry.sol:205-245`

**Description:**
The `claim()` function is vulnerable to front-running. An attacker monitoring the mempool can see a pending claim transaction and submit their own with higher gas price to steal the desired name.

**Attack Scenario:**
1. Alice submits `claim("valuable_name")`
2. Attacker sees transaction in mempool
3. Attacker submits same claim with higher gas price
4. Attacker's transaction executes first, stealing the name
5. Alice's transaction reverts with `IdentityNotAvailable`

**Impact:** Valuable names can be systematically front-run and held for ransom.

**Recommendation:**
Implement commit-reveal scheme:

```solidity
mapping(bytes32 => uint256) public commitments;

function commit(bytes32 commitment) external {
    commitments[commitment] = block.timestamp;
}

function claim(ClaimParams calldata params, bytes32 secret) external {
    bytes32 commitment = keccak256(abi.encodePacked(params.name, params.owner, secret));
    require(commitments[commitment] != 0, "No commitment");
    require(block.timestamp >= commitments[commitment] + 1 minutes, "Too early");
    require(block.timestamp <= commitments[commitment] + 24 hours, "Expired");

    delete commitments[commitment];
    // ... rest of claim logic
}
```

---

### H-04: `_validName()` Allows Confusable Characters - Homograph Attacks

**File:** `Registry.sol:435-448`

**Description:**
The name validation allows uppercase letters, enabling homograph attacks with visually similar names:

```solidity
bool valid = (c >= 0x30 && c <= 0x39) ||  // 0-9
            (c >= 0x41 && c <= 0x5A) ||   // A-Z  <-- Uppercase allowed
            (c >= 0x61 && c <= 0x7A) ||   // a-z
            (c == 0x5F);                   // _
```

**Attack Scenario:**
- Attacker registers `ALICE` (all uppercase)
- User thinks they're interacting with `alice`
- Two different DIDs: `did:lux:ALICE` vs `did:lux:alice`
- Phishing and confusion attacks possible

Additional concerns:
- `_` can be confused with `-` or space
- `l` (lowercase L) vs `1` (one) vs `I` (uppercase i)
- `0` (zero) vs `O` (uppercase o)

**Recommendation:**
Enforce lowercase-only names and normalize on storage:

```solidity
function _validName(string calldata name) internal pure returns (bool) {
    bytes memory b = bytes(name);
    if (b.length == 0 || b.length > 63) return false;

    for (uint256 i = 0; i < b.length; i++) {
        bytes1 c = b[i];
        // Only lowercase and digits
        bool valid = (c >= 0x30 && c <= 0x39) ||  // 0-9
                    (c >= 0x61 && c <= 0x7A);      // a-z only
        if (!valid) return false;
    }
    return true;
}
```

---

## Medium Severity Issues

### M-01: `IdentityNFT.mint()` Uses `_safeMint()` - Callback Risk

**File:** `IdentityNFT.sol:68`

**Description:**
The `mint()` function uses `_safeMint()` which calls `onERC721Received()` on the recipient if it's a contract. This external call happens before the Registry completes its state updates in `claim()`.

```solidity
// In IdentityNFT.mint()
_safeMint(to, tokenId);  // Calls external contract

// Back in Registry.claim(), state updates happen AFTER mint returns
_owners[did] = params.owner;
tokenToDID[nftId] = did;
_data[did] = IdentityData({...});
```

**Impact:** A malicious recipient contract could re-enter the Registry during the callback with inconsistent state.

**Recommendation:**
Either use `_mint()` instead of `_safeMint()`, or ensure Registry state is set before calling `identityNft.mint()`.

---

### M-02: No Stake Decrease Function - Locked Tokens Beyond Minimum

**File:** `Registry.sol:317-327`

**Description:**
Users can only increase stake via `increaseStake()`. There is no mechanism to withdraw excess stake above the minimum requirement.

```solidity
function increaseStake(string calldata did, uint256 amount) external {
    _requireOwner(did);
    stakingToken.transferFrom(msg.sender, address(this), amount);
    IdentityData storage data = _data[did];
    data.stakedTokens += amount;
    // ... no way to decrease
}
```

**Impact:** Users who overstake (intentionally or accidentally) can only recover tokens by completely unclaiming their identity.

**Recommendation:**
Add `decreaseStake()` function with minimum stake enforcement:

```solidity
function decreaseStake(string calldata did, uint256 amount) external {
    _requireOwner(did);
    IdentityData storage data = _data[did];

    // Extract name from DID for requirement calculation
    uint256 minimum = stakeRequirement(...);
    require(data.stakedTokens - amount >= minimum, "Below minimum");

    data.stakedTokens -= amount;
    stakingToken.transfer(msg.sender, amount);
}
```

---

### M-03: `_delegatees` Array Can Grow Unbounded - DoS Vector

**File:** `Registry.sol:101`

**Description:**
The `_delegatees` array has no size limit. While there's no `delegate()` function visible in the audited code, the struct and storage exist. If delegation is implemented, unbounded array growth could cause gas limit issues.

**Impact:** Potential denial-of-service if delegation is added without bounds.

**Recommendation:**
- Implement maximum delegatee limit (e.g., 100)
- Use enumerable set pattern for O(1) removal
- Consider removing unused delegation storage if not needed

---

### M-04: Owner Can Change Pricing to Zero - Free Identity Claims

**File:** `Registry.sol:410-422`

**Description:**
The `setPricing()` function allows setting prices to zero with no lower bound validation:

```solidity
function setPricing(
    uint256 p1, uint256 p2, uint256 p3, uint256 p4, uint256 p5,
    uint256 discountBps
) external onlyOwner {
    require(discountBps <= 10000, "Invalid discount");
    // No minimum price validation
    price1Char = p1;  // Can be 0
    // ...
}
```

**Impact:** Admin error or compromised owner could set prices to 0, enabling mass squatting of valuable names.

**Recommendation:**
Add minimum price validation:

```solidity
require(p1 > 0 && p2 > 0 && p3 > 0 && p4 > 0 && p5 > 0, "Invalid price");
```

---

### M-05: `records` Mapping Cleanup Missing on Unclaim

**File:** `Registry.sol:95, 266-268`

**Description:**
The `records[did]` mapping is not cleared when a DID is unclaimed:

```solidity
// Line 95
mapping(string => mapping(string => string)) public records;

// Line 266-268 - records NOT deleted
delete _owners[did];
delete tokenToDID[nftId];
delete _data[did];
delete _delegatees[did];
// Missing: records[did] not cleared
```

**Impact:**
- Old records persist and may be associated with a new owner if DID is reclaimed
- Privacy leak - old data remains accessible
- Storage bloat

**Recommendation:**
Note: Clearing a nested mapping is expensive. Consider:
1. Version number per DID to invalidate old records
2. Explicit key tracking for cleanup
3. Accept the limitation and document it

---

## Low Severity Issues

### L-01: Missing Events in `IdentityNFT`

**File:** `IdentityNFT.sol:64-78`

**Description:**
The `mint()` and `burn()` functions don't emit custom events. While ERC721 emits `Transfer` events, custom events would improve off-chain indexing.

**Recommendation:**
Add dedicated events:
```solidity
event IdentityMinted(address indexed to, uint256 indexed tokenId);
event IdentityBurned(uint256 indexed tokenId);
```

---

### L-02: `IdentityNFT` Registry Can Be Set to Zero After Initial Setup

**File:** `IdentityNFT.sol:46-49`

**Description:**
The `setRegistry()` function validates against zero address, but can be called multiple times. Once set, changing the registry could break the system.

```solidity
function setRegistry(address registry_) external onlyOwner {
    if (registry_ == address(0)) revert ZeroAddress();
    registry = registry_;  // Can be changed after deployment
}
```

**Recommendation:**
Make registry immutable after first set, or remove setter entirely:

```solidity
function setRegistry(address registry_) external onlyOwner {
    if (registry != address(0)) revert RegistryAlreadySet();
    if (registry_ == address(0)) revert ZeroAddress();
    registry = registry_;
}
```

---

### L-03: No Timelock on Admin Functions

**File:** `Registry.sol:402-422`

**Description:**
Critical admin functions like `setChain()` and `setPricing()` execute immediately without timelock. Users have no warning before parameter changes.

**Recommendation:**
Implement timelock for sensitive operations or use OpenZeppelin's TimelockController.

---

### L-04: `claim()` Allows Zero-Address Owner

**File:** `Registry.sol:227`

**Description:**
The `params.owner` is not validated before minting NFT:

```solidity
uint256 nftId = identityNft.mint(params.owner);  // params.owner could be address(0)
```

While `IdentityNFT.mint()` checks for zero address, the revert message would be confusing.

**Recommendation:**
Validate owner in Registry before calling mint:

```solidity
if (params.owner == address(0)) revert ZeroAddress();
```

---

## Informational / Gas Optimizations

### I-01: String Comparison Gas Optimization

**File:** `Registry.sol:210, 216, 219`

**Description:**
Multiple string operations use `bytes()` conversion. Consider caching:

```solidity
// Current - multiple conversions
if (bytes(methods[params.chainId]).length == 0) revert InvalidChain(params.chainId);
```

**Recommendation:**
Cache method once and reuse.

---

### I-02: Use Custom Errors Throughout

**File:** `Registry.sol:414`

**Description:**
Mix of `require` with string and custom errors:

```solidity
require(discountBps <= 10000, "Invalid discount");  // String error
```

**Recommendation:**
Use custom error for consistency:
```solidity
error InvalidDiscount();
if (discountBps > 10000) revert InvalidDiscount();
```

---

### I-03: Consider `bytes32` for DIDs

**Description:**
Storing DIDs as strings is expensive. For fixed-format DIDs, consider hashing to `bytes32`:

```solidity
mapping(bytes32 => address) private _owners;  // Hash of DID

function _didHash(string memory did) internal pure returns (bytes32) {
    return keccak256(bytes(did));
}
```

---

### I-04: Unused `Delegation` Struct

**File:** `Registry.sol:64-67`

**Description:**
The `Delegation` struct is defined but only used in event parameter. The actual delegation storage uses separate mappings.

**Recommendation:**
Remove if unused, or restructure delegation storage to use the struct.

---

### I-05: Missing NatSpec Documentation

**File:** Both contracts

**Description:**
Several functions lack NatSpec documentation, particularly:
- `_authorizeUpgrade()`
- Internal functions
- Event parameters

**Recommendation:**
Add comprehensive NatSpec for all public/external functions.

---

### I-06: Token Counter Could Use Unchecked Increment

**File:** `IdentityNFT.sol:67`

**Description:**
The token counter increment can use unchecked math since overflow is practically impossible:

```solidity
// Current
uint256 tokenId = _tokenIdCounter++;

// Optimized
uint256 tokenId;
unchecked { tokenId = _tokenIdCounter++; }
```

---

## Upgrade Safety Analysis (UUPS)

### Storage Layout

The Registry contract uses UUPS upgrade pattern correctly:
- `_disableInitializers()` in constructor prevents implementation initialization
- `_authorizeUpgrade()` restricted to owner
- Inherits from OpenZeppelin upgradeable contracts

**Recommendations:**
1. Add storage gap for future upgrades:
```solidity
uint256[50] private __gap;
```

2. Document storage layout for upgrade safety
3. Consider adding upgrade timelock

### Storage Collision Risk

Current storage order is safe, but new variables MUST be added at the end. Document variable positions:

```solidity
// Slot 0: stakingToken (inherited)
// Slot 1: identityNft
// Slot 2: methods mapping
// ... etc
```

---

## Cross-Chain Security Considerations

1. **Chain ID Spoofing:** The contract trusts `params.chainId` input. On L2s or bridges, verify against `block.chainid`.

2. **Replay Protection:** DIDs include chain-specific method (did:lux:, did:zoo:), providing natural replay protection.

3. **Oracle Dependencies:** No external oracle dependencies found - good.

4. **Bridge Interactions:** If DIDs are bridged, ensure ownership proof travels with the message.

---

## Recommendations Summary

### Must Fix (Critical/High)

1. **C-01:** Apply CEI pattern in `unclaim()`, add ReentrancyGuard
2. **C-02:** Derive ownership from NFT, not stored mapping
3. **H-01:** Use SafeERC20 for all token transfers
4. **H-02:** Clear delegation mappings on unclaim
5. **H-03:** Implement commit-reveal for claims
6. **H-04:** Normalize names to lowercase only

### Should Fix (Medium)

1. **M-01:** Use `_mint()` or reorder state updates
2. **M-02:** Add `decreaseStake()` function
3. **M-03:** Bound delegatee array size
4. **M-04:** Add minimum price validation
5. **M-05:** Handle records cleanup or version

### Consider Fixing (Low)

1. **L-01:** Add custom events for mint/burn
2. **L-02:** Make registry immutable after set
3. **L-03:** Add timelock for admin functions
4. **L-04:** Validate owner address in claim

---

## Test Vectors

### C-01 Reentrancy Test
```solidity
contract MaliciousToken {
    Registry registry;

    function transfer(address, uint256) external returns (bool) {
        // Re-enter while owner still set
        registry.setKeys("did:lux:attacker", "evil", "evil");
        return true;
    }
}
```

### C-02 Ownership Desync Test
```solidity
function testOwnershipDesync() public {
    // Alice claims
    registry.claim(params);

    // Alice transfers NFT to Bob
    identityNft.transferFrom(alice, bob, tokenId);

    // Alice can still unclaim and steal stake
    vm.prank(alice);
    registry.unclaim("did:lux:alice");  // Should fail but doesn't
}
```

---

**End of Audit Report**
