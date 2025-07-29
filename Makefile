# Lux Standard Makefile for Foundry

-include .env

.PHONY: all test clean deploy

# Build
build:
	forge build

# Clean
clean:
	forge clean
	rm -rf cache_forge

# Test
test:
	forge test

test-verbose:
	forge test -vvvv

test-gas:
	forge test --gas-report

# Coverage
coverage:
	forge coverage

coverage-report:
	forge coverage --report lcov

# Format
format:
	forge fmt

# Lint
lint:
	forge fmt --check

# Deploy with CREATE2 for deterministic addresses
deploy-local:
	forge script script/DeployWithCreate2.s.sol:DeployWithCreate2 --rpc-url localhost --broadcast

deploy-testnet:
	forge script script/DeployWithCreate2.s.sol:DeployWithCreate2 --rpc-url testnet --broadcast --verify

deploy-mainnet:
	forge script script/DeployWithCreate2.s.sol:DeployWithCreate2 --rpc-url mainnet --broadcast --verify

# Compute addresses before deployment
compute-addresses:
	forge script script/DeployWithCreate2.s.sol:ComputeCreate2Addresses

# Install
install:
	forge install foundry-rs/forge-std --no-commit
	forge install openzeppelin/openzeppelin-contracts@v4.9.3 --no-commit

# Update
update:
	forge update

# Snapshot
snapshot:
	forge snapshot

# Anvil
anvil:
	anvil

anvil-fork-mainnet:
	anvil --fork-url ${RPC_MAINNET}

anvil-fork-testnet:
	anvil --fork-url ${RPC_TESTNET}

# Verify
verify:
	forge verify-contract ${contract} ${address} --chain-id ${chain} --etherscan-api-key ${ETHERSCAN_API_KEY}

# Slither
slither:
	slither src/

# Help
help:
	@echo "Usage:"
	@echo "  make build          - Build contracts"
	@echo "  make test           - Run tests"
	@echo "  make test-verbose   - Run tests with verbose output"
	@echo "  make test-gas       - Run tests with gas report"
	@echo "  make coverage       - Generate coverage report"
	@echo "  make format         - Format code"
	@echo "  make lint           - Check code formatting"
	@echo "  make deploy-local   - Deploy to local network"
	@echo "  make deploy-testnet - Deploy to testnet"
	@echo "  make deploy-mainnet - Deploy to mainnet"
	@echo "  make install        - Install dependencies"
	@echo "  make anvil          - Start local Anvil node"
	@echo "  make snapshot       - Create gas snapshot"