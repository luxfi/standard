# Test Migration and Organization Plan

## Overview

This document outlines the plan to migrate all tests to Foundry and ensure comprehensive test coverage for the Lux Standard repository.

## Current State

### Testing Frameworks
- **Hardhat** (TypeScript): Primary framework for most tests
- **Foundry** (Solidity): Limited adoption, only 3-4 test files

### Test Coverage
- ✅ Core contracts have TypeScript tests
- ⚠️ Protocol integrations have mixed coverage
- ❌ Many contracts lack Foundry tests
- ❌ No systematic gas optimization tests

## Migration Strategy

### Phase 1: Core Contract Migration (Week 1-2)

#### Priority 1 - Token Contracts
```solidity
// Migrate these tests first:
- test/LUX.test.ts → test/foundry/LUX.t.sol ✅ (Done)
- test/DLUX.test.ts → test/foundry/DLUX.t.sol
- test/LuxNFT.ts → test/foundry/LuxNFT.t.sol
```

#### Priority 2 - DeFi Core
```solidity
// Critical DeFi infrastructure:
- test/Farm.test.ts → test/foundry/Farm.t.sol
- test/Market.test.ts → test/foundry/Market.t.sol
- test/Auction.test.ts → test/foundry/Auction.t.sol
```

#### Priority 3 - Infrastructure
```solidity
// System contracts:
- test/Bridge.test.ts → test/foundry/Bridge.t.sol
- test/Drop.test.ts → test/foundry/Drop.t.sol
- test/LuxDAO.test.ts → test/foundry/LuxDAO.t.sol
```

### Phase 2: Protocol Integration Tests (Week 3-4)

#### Create New Tests
```solidity
// Missing protocol tests:
- test/foundry/protocols/Aave.t.sol (for aave3 integration)
- test/foundry/protocols/Alchemix.t.sol (for alcx2)
- test/foundry/protocols/GMX.t.sol (for gmx2)
- test/foundry/protocols/Uniswap.t.sol (comprehensive)
```

#### Integration Tests
```solidity
// Cross-protocol interactions:
- test/foundry/integration/DeFiIntegration.t.sol
- test/foundry/integration/BridgeIntegration.t.sol
- test/foundry/integration/FullProtocol.t.sol
```

### Phase 3: Advanced Testing (Week 5-6)

#### Security Tests
```solidity
// Security-focused tests:
- test/foundry/security/Reentrancy.t.sol
- test/foundry/security/AccessControl.t.sol
- test/foundry/security/Overflow.t.sol
```

#### Gas Optimization Tests
```solidity
// Gas benchmarks:
- test/foundry/gas/TokenGas.t.sol
- test/foundry/gas/DeFiGas.t.sol
- test/foundry/gas/BridgeGas.t.sol
```

#### Fuzz Tests
```solidity
// Property-based testing:
- test/foundry/fuzz/TokenFuzz.t.sol
- test/foundry/fuzz/AMMFuzz.t.sol
- test/foundry/fuzz/BridgeFuzz.t.sol
```

## Test Structure

### Directory Organization
```
test/
├── foundry/
│   ├── core/           # Core contract tests
│   ├── protocols/      # Protocol integration tests
│   ├── integration/    # Cross-contract integration
│   ├── security/       # Security-focused tests
│   ├── gas/            # Gas optimization tests
│   ├── fuzz/           # Fuzz testing
│   └── utils/          # Test helpers and utilities
├── legacy/             # Old TypeScript tests (to be removed)
└── fixtures/           # Test data and fixtures
```

### Test Template

```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/ContractName.sol";

contract ContractNameTest is Test {
    ContractName public contractInstance;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    function setUp() public {
        // Deploy contracts
        contractInstance = new ContractName();
        
        // Setup initial state
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }
    
    // State tests
    function test_InitialState() public {
        // Test initial values
    }
    
    // Happy path tests
    function test_NormalOperation() public {
        // Test expected behavior
    }
    
    // Edge case tests
    function test_EdgeCases() public {
        // Test boundary conditions
    }
    
    // Failure tests
    function testFail_InvalidOperation() public {
        // Test expected failures
    }
    
    // Fuzz tests
    function testFuzz_Operation(uint256 amount) public {
        // Property-based tests
    }
    
    // Gas tests
    function test_GasUsage() public {
        // Measure gas consumption
    }
}
```

## Migration Checklist

### For Each Test File:
- [ ] Create Foundry test file with same coverage
- [ ] Port all test cases
- [ ] Add gas measurements
- [ ] Add fuzz tests where applicable
- [ ] Verify test passes
- [ ] Compare coverage with original
- [ ] Remove TypeScript test
- [ ] Update documentation

### Test Categories to Include:

#### 1. State Tests
- Initial state verification
- State transitions
- State consistency

#### 2. Functional Tests
- Happy path scenarios
- Edge cases
- Failure cases
- Revert reasons

#### 3. Security Tests
- Access control
- Reentrancy
- Integer overflow/underflow
- Front-running

#### 4. Integration Tests
- Cross-contract calls
- Protocol interactions
- End-to-end scenarios

#### 5. Performance Tests
- Gas consumption
- Storage optimization
- Computational efficiency

## Testing Best Practices

### 1. Test Naming
```solidity
// Format: test_[State]_[Action]_[Expectation]
function test_WhenPaused_Transfer_Reverts() public {}
function test_WithBalance_Withdraw_UpdatesBalance() public {}
```

### 2. Test Organization
- One test contract per source contract
- Group related tests with comments
- Use descriptive function names

### 3. Assertions
```solidity
// Use specific assertions
assertEq(balance, expectedBalance, "Balance mismatch");
assertGt(newValue, oldValue, "Value did not increase");
assertLe(gasUsed, maxGas, "Gas limit exceeded");
```

### 4. Events Testing
```solidity
// Test event emissions
vm.expectEmit(true, true, false, true);
emit Transfer(alice, bob, amount);
contract.transfer(bob, amount);
```

### 5. Error Testing
```solidity
// Test specific errors
vm.expectRevert("Insufficient balance");
contract.transfer(bob, tooMuch);
```

## Coverage Requirements

### Minimum Coverage Targets
- Core contracts: 95%
- DeFi protocols: 90%
- Utility contracts: 85%
- Integration tests: 80%

### Critical Paths
Must have 100% coverage:
- Fund transfers
- Access control
- Emergency functions
- Bridge operations

## Continuous Integration

### GitHub Actions Workflow
```yaml
name: Foundry Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: foundry-rs/foundry-toolchain@v1
      - run: forge build
      - run: forge test -vvv
      - run: forge coverage --report lcov
      - uses: codecov/codecov-action@v3
```

## Timeline

| Week | Tasks | Deliverables |
|------|-------|--------------|
| 1-2 | Core contract migration | All token and DeFi tests in Foundry |
| 3-4 | Protocol integration tests | Complete protocol coverage |
| 5-6 | Advanced testing | Security, gas, and fuzz tests |
| 7 | Cleanup and documentation | Remove legacy tests, update docs |
| 8 | CI/CD integration | Automated testing pipeline |

## Success Metrics

1. **Coverage**: >90% overall, 100% for critical paths
2. **Gas**: All operations optimized and benchmarked
3. **Security**: All known attack vectors tested
4. **Performance**: Tests run in <2 minutes
5. **Documentation**: Every contract has test documentation

## Next Steps

1. Start with LUX token test migration (already done ✅)
2. Create test helper utilities
3. Migrate high-value contracts first
4. Add gas benchmarking to all tests
5. Implement continuous coverage reporting

This migration will result in:
- 🚀 Faster test execution
- 📊 Better gas optimization
- 🔒 Enhanced security testing
- 📈 Improved coverage metrics
- 🧪 Standardized testing approach