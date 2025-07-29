# Foundry Tests for Lux Standard

This directory contains Foundry tests for the Lux Standard contracts.

## Setup

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```bash
forge install foundry-rs/forge-std
```

## Running Tests

Run all tests:
```bash
forge test
```

Run specific test file:
```bash
forge test --match-path test/foundry/LUX.t.sol
```

Run specific test function:
```bash
forge test --match-test testTokenMetadata
```

Run with verbosity:
```bash
forge test -vvvv
```

## Gas Reports

Generate gas reports:
```bash
forge test --gas-report
```

## Coverage

Generate coverage report:
```bash
forge coverage
```

## Test Structure

- `LUX.t.sol` - Tests for the LUX token contract
- `Lamport.t.sol` - Tests for Lamport signature implementation
- `TestHelpers.sol` - Common test utilities and helpers

## Writing Tests

Example test:
```solidity
function testExample() public {
    // Setup
    address user = makeAddr("user");
    
    // Action
    token.transfer(user, 100e18);
    
    // Assert
    assertEq(token.balanceOf(user), 100e18);
}
```

## Fuzzing

Foundry supports property-based testing with fuzzing:
```solidity
function testFuzz_Transfer(address to, uint256 amount) public {
    vm.assume(to != address(0));
    amount = bound(amount, 0, token.totalSupply());
    
    token.transfer(to, amount);
    assertEq(token.balanceOf(to), amount);
}
```