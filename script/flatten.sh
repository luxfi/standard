#!/bin/bash
# Flatten standard repo structure for clean imports
set -e

REPO_ROOT="/Users/z/work/lux/standard"
cd "$REPO_ROOT"

echo "🧹 Flattening standard repo structure..."

# 1. Create new contracts/ structure
echo "📁 Creating contracts/ structure..."
mkdir -p contracts/{tokens,bridge,safe,governance,defi,account,precompiles,interfaces,utils}

# 2. Move token contracts
echo "📦 Moving token contracts..."
[ -f src/tokens/LRC20.sol ] && cp src/tokens/LRC20.sol contracts/tokens/
[ -f src/tokens/ERC20B.sol ] && cp src/tokens/ERC20B.sol contracts/tokens/
[ -f src/tokens/ERC721B.sol ] && cp src/tokens/ERC721B.sol contracts/tokens/
[ -f src/tokens/LETH.sol ] && cp src/tokens/LETH.sol contracts/tokens/
[ -f src/tokens/LBTC.sol ] && cp src/tokens/LBTC.sol contracts/tokens/
[ -f src/tokens/LUX.sol ] && cp src/tokens/LUX.sol contracts/tokens/
[ -f src/tokens/WETH.sol ] && cp src/tokens/WETH.sol contracts/tokens/

# 3. Move bridge contracts
echo "🌉 Moving bridge contracts..."
[ -d src/teleport ] && cp src/teleport/*.sol contracts/bridge/ 2>/dev/null || true

# 4. Move interface files
echo "📋 Moving interfaces..."
[ -d src/interfaces ] && cp src/interfaces/*.sol contracts/interfaces/ 2>/dev/null || true

# 5. Clean up nested submodules (the main problem)
echo "🗑️  Removing nested duplicate submodules..."

# Remove nested openzeppelin copies
find lib -mindepth 2 -type d -name "openzeppelin-contracts" -exec rm -rf {} + 2>/dev/null || true
find lib -mindepth 2 -type d -name "openzeppelin-contracts-upgradeable" -exec rm -rf {} + 2>/dev/null || true
find lib -mindepth 2 -type d -name "forge-std" -exec rm -rf {} + 2>/dev/null || true
find lib -mindepth 2 -type d -name "ds-test" -exec rm -rf {} + 2>/dev/null || true

# 6. Clean artifacts
echo "🧹 Cleaning build artifacts..."
rm -rf artifacts/ 2>/dev/null || true
rm -rf cache_forge/ 2>/dev/null || true
rm -rf cache_hardhat/ 2>/dev/null || true
rm -rf out/ 2>/dev/null || true

# 7. Create remappings.txt
echo "📝 Creating remappings.txt..."
cat > remappings.txt << 'EOF'
@openzeppelin/=lib/openzeppelin-contracts/contracts/
@openzeppelin-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
@account-abstraction/=lib/account-abstraction/contracts/
@solmate/=lib/solmate/src/
@uniswap/v2-core/=lib/v2-core/contracts/
@uniswap/v3-core/=lib/v3-core/contracts/
@uniswap/v3-periphery/=lib/v3-periphery/contracts/
@lux/=contracts/
forge-std/=lib/forge-std/src/
EOF

# 8. Update foundry.toml
echo "⚙️  Updating foundry.toml..."
cat > foundry.toml << 'EOF'
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
via_ir = false
solc_version = "0.8.24"

# Clean remappings
remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/contracts/",
    "@openzeppelin-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/",
    "@account-abstraction/=lib/account-abstraction/contracts/",
    "@solmate/=lib/solmate/src/",
    "@lux/=contracts/",
    "forge-std/=lib/forge-std/src/",
]

[profile.default.fmt]
line_length = 120
tab_width = 4
bracket_spacing = true

[rpc_endpoints]
lux = "https://api.lux.network/ext/bc/C/rpc"
lux_testnet = "https://api.lux-test.network/ext/bc/C/rpc"
EOF

# 9. Update .gitignore
echo "📝 Updating .gitignore..."
cat >> .gitignore << 'EOF'

# Build artifacts
out/
cache/
artifacts/
cache_forge/
cache_hardhat/

# Dependencies (use forge install)
# lib/  # Uncomment to ignore lib/
EOF

echo ""
echo "✅ Flattening complete!"
echo ""
echo "📊 New structure:"
echo "   contracts/     - All Lux contracts"
echo "   lib/           - External dependencies"
echo "   test/          - Tests"
echo "   script/        - Deployment scripts"
echo ""
echo "📦 Import examples:"
echo '   import "@openzeppelin/token/ERC20/ERC20.sol";'
echo '   import "@lux/tokens/LRC20.sol";'
echo ""
echo "🔨 Next steps:"
echo "   1. Update imports in existing contracts"
echo "   2. Run: forge build"
echo "   3. Run: forge test"
