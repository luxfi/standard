# Lux Standard — Foundry + Security Tooling

-include .env

VENV := .venv
UV := uv
PYTHON := $(VENV)/bin/python
SLITHER := $(VENV)/bin/slither
SEMGREP := $(VENV)/bin/semgrep
ADERYN := $(HOME)/.cyfrin/bin/aderyn

.PHONY: all build test clean deploy lint fmt audit security venv halmos

# ═══════════════════════════════════════════════════════════════════
# Build & Test
# ═══════════════════════════════════════════════════════════════════

build:
	forge build

clean:
	forge clean
	rm -rf cache_forge out

test:
	forge test --summary

test-v:
	forge test -vvvv

test-gas:
	forge test --gas-report

test-fuzz:
	forge test --match-path "test/foundry/fuzz/*.sol" --fuzz-runs 1000

coverage:
	forge coverage --ir-minimum --report summary

coverage-lcov:
	forge coverage --ir-minimum --report lcov --report-file lcov.info

# ═══════════════════════════════════════════════════════════════════
# Format & Lint
# ═══════════════════════════════════════════════════════════════════

fmt:
	forge fmt

lint:
	forge fmt --check
	forge lint contracts/

# ═══════════════════════════════════════════════════════════════════
# Security (Python tools via uv virtualenv)
# ═══════════════════════════════════════════════════════════════════

venv: $(VENV)/.installed

$(VENV)/.installed:
	$(UV) venv $(VENV)
	$(UV) pip install --python $(VENV)/bin/python slither-analyzer semgrep
	@touch $@

slither: venv
	$(SLITHER) contracts/ \
		--exclude-dependencies \
		--exclude-informational \
		--filter-paths "test/,mocks/,script/" \
		--json slither-report.json || true
	@echo "Report: slither-report.json"

semgrep: venv
	$(SEMGREP) scan --config p/solidity --config p/smart-contracts \
		contracts/ --sarif -o semgrep-results.sarif || true
	@echo "Report: semgrep-results.sarif"

aderyn:
	@if [ ! -f "$(ADERYN)" ]; then \
		echo "Installing aderyn..."; \
		curl -L https://raw.githubusercontent.com/Cyfrin/aderyn/main/cyfrinup/install | bash; \
		$(HOME)/.cyfrin/bin/cyfrinup; \
	fi
	$(ADERYN) . --src contracts/ --output aderyn-report.md || true
	@echo "Report: aderyn-report.md"

# Run ALL security tools
security: slither semgrep aderyn
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  Security Audit Complete"
	@echo "═══════════════════════════════════════════"
	@echo "  Slither:  slither-report.json"
	@echo "  Semgrep:  semgrep-results.sarif"
	@echo "  Aderyn:   aderyn-report.md"
	@echo "═══════════════════════════════════════════"

# Full audit: lint + test + security
audit: lint test security
	@echo "Full audit complete."

# ═══════════════════════════════════════════════════════════════════
# Symbolic Execution (Halmos)
# ═══════════════════════════════════════════════════════════════════

HALMOS := $(VENV)/bin/halmos

halmos: venv
	$(HALMOS) --solver-timeout-branching 10s --solver-timeout-assertion 300s --function check

# ═══════════════════════════════════════════════════════════════════
# Deploy
# ═══════════════════════════════════════════════════════════════════

deploy-devnet:
	forge script script/DeployFullStack.s.sol:DeployFullStack \
		--rpc-url https://api.lux-dev.network/ext/bc/C/rpc \
		--mnemonics "$$LUX_MNEMONIC" --broadcast -vvv

deploy-testnet:
	forge script script/DeployFullStack.s.sol:DeployFullStack \
		--rpc-url https://api.lux-test.network/ext/bc/C/rpc \
		--mnemonics "$$LUX_MNEMONIC" --broadcast -vvv

deploy-mainnet:
	forge script script/DeployFullStack.s.sol:DeployFullStack \
		--rpc-url https://api.lux.network/ext/bc/C/rpc \
		--mnemonics "$$LUX_MNEMONIC" --broadcast -vvv

deploy-all: deploy-devnet deploy-testnet deploy-mainnet

# ═══════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════

snapshot:
	forge snapshot

sizes:
	forge build --sizes

anvil:
	anvil --chain-id 96369 --mnemonic "$$LUX_MNEMONIC" --balance 10000000000

update:
	forge update

install:
	forge install

help:
	@echo "Build & Test:"
	@echo "  make build         Build contracts"
	@echo "  make test          Run all tests"
	@echo "  make test-v        Tests with full traces"
	@echo "  make test-fuzz     Fuzz tests (1000 runs)"
	@echo "  make coverage      Coverage summary"
	@echo ""
	@echo "Security:"
	@echo "  make security      Run slither + semgrep + aderyn"
	@echo "  make slither       Slither static analysis"
	@echo "  make semgrep       Semgrep SAST"
	@echo "  make aderyn        Aderyn Solidity analyzer"
	@echo "  make audit         Full: lint + test + security"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy-devnet   Deploy to devnet"
	@echo "  make deploy-testnet  Deploy to testnet"
	@echo "  make deploy-mainnet  Deploy to mainnet"
	@echo "  make deploy-all      Deploy to all networks"
	@echo ""
	@echo "Other:"
	@echo "  make fmt           Format code"
	@echo "  make lint          Check formatting + lint"
	@echo "  make sizes         Contract sizes"
	@echo "  make anvil         Start local node"
