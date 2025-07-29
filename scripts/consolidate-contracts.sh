#!/bin/bash

# Script to identify and help consolidate duplicate contracts in the Lux Standard repository

echo "🔍 Analyzing duplicate contracts in Lux Standard repository..."
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/Users/z/work/lux/standard"

# Find all Solidity files and extract contract names
echo -e "${BLUE}Scanning for Solidity contracts...${NC}"

# Create temporary directory for analysis
TEMP_DIR=$(mktemp -d)
CONTRACTS_FILE="$TEMP_DIR/contracts.txt"
DUPLICATES_FILE="$TEMP_DIR/duplicates.txt"

# Find all .sol files and extract contract/interface/library names
find "$BASE_DIR/src" -name "*.sol" -type f | while read -r file; do
    # Extract contract, interface, and library names
    grep -E "^(contract|interface|library)\s+" "$file" | \
    sed -E 's/(contract|interface|library)\s+([A-Za-z0-9_]+).*/\2/' | \
    while read -r contract_name; do
        echo "$contract_name:$file" >> "$CONTRACTS_FILE"
    done
done

# Sort and find duplicates
echo -e "${BLUE}Analyzing duplicates...${NC}"
sort "$CONTRACTS_FILE" | awk -F: '{
    contracts[$1] = contracts[$1] ? contracts[$1] "," $2 : $2
    count[$1]++
}
END {
    for (c in contracts) {
        if (count[c] > 1) {
            print c ":" contracts[c]
        }
    }
}' > "$DUPLICATES_FILE"

# Display results
if [ -s "$DUPLICATES_FILE" ]; then
    echo -e "${RED}Found duplicate contracts:${NC}"
    echo "=================================================="
    
    while IFS=: read -r contract_name files; do
        echo -e "${YELLOW}Contract: $contract_name${NC}"
        echo "$files" | tr ',' '\n' | while read -r file; do
            echo "  - $file"
            # Show file size and last modified
            if [ -f "$file" ]; then
                size=$(wc -c < "$file")
                modified=$(date -r "$file" "+%Y-%m-%d %H:%M")
                echo "    Size: $size bytes, Modified: $modified"
            fi
        done
        echo ""
    done < "$DUPLICATES_FILE"
    
    # Count total duplicates
    DUPLICATE_COUNT=$(wc -l < "$DUPLICATES_FILE")
    echo -e "${RED}Total duplicate contracts found: $DUPLICATE_COUNT${NC}"
else
    echo -e "${GREEN}No duplicate contracts found!${NC}"
fi

# Analyze import patterns
echo ""
echo -e "${BLUE}Analyzing import patterns...${NC}"
echo "=================================================="

# Common imports that might need consolidation
COMMON_IMPORTS=(
    "@openzeppelin/contracts"
    "@openzeppelin/contracts-upgradeable"
    "solmate"
    "@rari-capital"
    "@uniswap"
)

for import_pattern in "${COMMON_IMPORTS[@]}"; do
    count=$(grep -r "import.*$import_pattern" "$BASE_DIR/src" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        echo -e "${YELLOW}$import_pattern${NC}: $count imports"
        # Show different versions
        grep -r "import.*$import_pattern" "$BASE_DIR/src" 2>/dev/null | \
        sed -E "s/.*($import_pattern[^\"';]*).*/\1/" | \
        sort | uniq -c | sort -rn | head -5 | \
        while read -r line; do
            echo "  $line"
        done
    fi
done

# Suggest consolidation strategy
echo ""
echo -e "${BLUE}Consolidation Recommendations:${NC}"
echo "=================================================="

echo "1. Create a shared 'common' directory for utility contracts:"
echo "   - src/common/access/Ownable.sol"
echo "   - src/common/math/SafeMath.sol"
echo "   - src/common/security/ReentrancyGuard.sol"
echo "   - src/common/token/ERC20Base.sol"
echo ""

echo "2. Standardize OpenZeppelin imports:"
echo "   - Use consistent version (recommend v4.9.3)"
echo "   - Create remappings for easy updates"
echo ""

echo "3. Protocol-specific contracts should extend common base:"
echo "   - Avoid copying entire contracts"
echo "   - Use inheritance for customization"
echo ""

echo "4. Remove obsolete implementations:"
echo "   - SafeMath (not needed in Solidity ^0.8.0)"
echo "   - Old protocol versions"
echo ""

# Generate consolidation script
CONSOLIDATION_SCRIPT="$BASE_DIR/scripts/execute-consolidation.sh"
echo -e "${BLUE}Generating consolidation script...${NC}"

cat > "$CONSOLIDATION_SCRIPT" << 'EOF'
#!/bin/bash

# Consolidation execution script
echo "Starting contract consolidation..."

# Create common directories
mkdir -p src/common/{access,math,security,token,utils}

# TODO: Add specific consolidation commands based on analysis
# Example:
# mv src/tokens/SafeMath.sol src/common/math/
# find . -name "*.sol" -exec sed -i '' 's|import.*SafeMath.sol|import "../common/math/SafeMath.sol"|g' {} \;

echo "Consolidation complete!"
echo "Please review changes and run tests."
EOF

chmod +x "$CONSOLIDATION_SCRIPT"

echo -e "${GREEN}Analysis complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Review the duplicate contracts list above"
echo "2. Edit $CONSOLIDATION_SCRIPT with specific consolidation commands"
echo "3. Run the consolidation script"
echo "4. Update import statements"
echo "5. Run all tests to ensure nothing broke"

# Cleanup
rm -rf "$TEMP_DIR"