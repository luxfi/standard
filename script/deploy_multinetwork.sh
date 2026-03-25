#!/bin/bash
# Deploy Lux standard contracts to all three networks
#
# Requirements:
#   export LUX_MNEMONIC="<your-mnemonic>"
#
# Networks use public DNS endpoints (not raw IPs)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Require mnemonic from environment
if [ -z "$LUX_MNEMONIC" ]; then
    echo -e "${RED}ERROR: LUX_MNEMONIC not set${NC}"
    echo "  export LUX_MNEMONIC=\"<your-mnemonic>\""
    exit 1
fi

# Network configurations — public DNS only
MAINNET_RPC="https://api.lux.network/ext/bc/C/rpc"
TESTNET_RPC="https://api.lux-test.network/ext/bc/C/rpc"
DEVNET_RPC="https://api.lux-dev.network/ext/bc/C/rpc"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  LUX MULTI-NETWORK DEPLOYMENT${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

deploy_to_network() {
    local rpc=$1
    local name=$2

    echo -e "${YELLOW}--- Deploying to $name ---${NC}"

    forge script script/DeployFullStack.s.sol:DeployFullStack \
        --rpc-url "$rpc" \
        --mnemonics "$LUX_MNEMONIC" \
        --broadcast \
        -vvv 2>&1 | tee "broadcast/${name}_$(date +%Y%m%d_%H%M%S).log"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}$name deployment SUCCESSFUL${NC}"
    else
        echo -e "${RED}$name deployment FAILED${NC}"
    fi
}

deploy_to_network "$DEVNET_RPC" "devnet"
deploy_to_network "$TESTNET_RPC" "testnet"
deploy_to_network "$MAINNET_RPC" "mainnet"

echo ""
echo -e "${BLUE}  DEPLOYMENT COMPLETE${NC}"
