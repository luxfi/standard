#!/bin/bash
set -e

# Simple Release Script for Lux Standard
# Bumps version and creates git tag (no build required)

echo "🚀 Lux Standard Release (Simple)"
echo "================================"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get current version from package.json
CURRENT_VERSION=$(node -p "require('./package.json').version")
echo -e "${BLUE}Current version: ${CURRENT_VERSION}${NC}"

# Parse version
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${VERSION_PARTS[2]}"

# Bump minor version
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="${MAJOR}.${NEW_MINOR}.0"

echo -e "${YELLOW}New version: ${NEW_VERSION}${NC}"

# Confirm
read -p "Continue with release v${NEW_VERSION}? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Release cancelled"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 1: Update package.json version${NC}"
node -e "
const fs = require('fs');
const pkg = require('./package.json');
pkg.version = '${NEW_VERSION}';
fs.writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');
"
echo -e "${GREEN}✓ Updated package.json${NC}"

echo ""
echo -e "${BLUE}Step 2: Create VERSION file${NC}"
echo "${NEW_VERSION}" > VERSION
echo -e "${GREEN}✓ Created VERSION file${NC}"

echo ""
echo -e "${BLUE}Step 3: Create CHANGELOG entry${NC}"
cat >> CHANGELOG.md << EOF

## [${NEW_VERSION}] - $(date +%Y-%m-%d)

### Added
- HanzoRegistry: Universal identity registry (EVM-agnostic)
- HanzoRegistrySimple: Lightweight registry implementation
- OmnichainLP: Cross-chain liquidity pools
- OmnichainLPFactory: Pool factory contract
- OmnichainLPRouter: Routing for omnichain swaps

### Changed
- Reorganized contracts: separated core infrastructure from chain-specific implementations
- Moved AI-specific contracts (AIToken, AIFaucet) to Hanzo repository
- Updated .gitignore to exclude build artifacts

### Infrastructure
- Post-quantum precompiles: ML-DSA (FIPS 204), SLH-DSA (FIPS 205)
- Deployment scripts for multiple EVM chains
- Foundry build configuration with dependency management

EOF
echo -e "${GREEN}✓ Updated CHANGELOG.md${NC}"

echo ""
echo -e "${BLUE}Step 4: Git commit${NC}"
git add package.json VERSION CHANGELOG.md
git commit -m "release: v${NEW_VERSION}

Bump minor version ${CURRENT_VERSION} → ${NEW_VERSION}

Core Infrastructure:
- HanzoRegistry (22KB): Universal identity registry
- OmnichainLP (18KB): Cross-chain liquidity pools
- Post-quantum precompiles (ML-DSA, SLH-DSA)

Deployable on ANY EVM chain:
- Hanzo, Zoo, Lux, Ethereum, Polygon, Arbitrum, etc.

See CHANGELOG.md for full details.
"
echo -e "${GREEN}✓ Committed version bump${NC}"

echo ""
echo -e "${BLUE}Step 5: Create git tag${NC}"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}

Core contracts for cross-chain infrastructure:
- Universal identity registry (HanzoRegistry)
- Omnichain liquidity pools (OmnichainLP)
- Post-quantum cryptography precompiles

Supports all EVM-compatible chains.
"
echo -e "${GREEN}✓ Created tag v${NEW_VERSION}${NC}"

echo ""
echo -e "${GREEN}✅ Release v${NEW_VERSION} complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Push to remote: ${YELLOW}git push origin main${NC}"
echo "  2. Push tags: ${YELLOW}git push origin v${NEW_VERSION}${NC}"
echo "  3. Create GitHub release: ${YELLOW}gh release create v${NEW_VERSION} --generate-notes${NC}"
echo ""
echo "Release info:"
echo "  Version: ${NEW_VERSION}"
echo "  Tag: v${NEW_VERSION}"
echo "  Date: $(date +%Y-%m-%d)"
