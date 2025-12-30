#!/bin/bash
# Deploy Hanzo chains and AI token to all networks

set -e

echo "==========================================="
echo "  LUX FULL DEPLOYMENT SCRIPT"
echo "==========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check networks are running
check_network() {
    local port=$1
    local name=$2
    if curl -s http://127.0.0.1:$port/ext/health | grep -q '"healthy":true'; then
        echo -e "${GREEN}✓${NC} $name running on port $port"
        return 0
    else
        echo -e "${RED}✗${NC} $name NOT running on port $port"
        return 1
    fi
}

echo "Checking network status..."
check_network 9630 "Mainnet" || exit 1
check_network 9640 "Testnet" || exit 1
check_network 9650 "Devnet" || exit 1
echo ""

# Deploy Hanzo chains
echo "==========================================="
echo "  DEPLOYING HANZO CHAINS"
echo "==========================================="

deploy_chain() {
    local chain=$1
    local network=$2
    local flag=$3
    
    echo ""
    echo -e "${YELLOW}Deploying $chain to $network...${NC}"
    
    # Check if already deployed
    local port
    case $network in
        mainnet) port=9630 ;;
        testnet) port=9640 ;;
        devnet) port=9650 ;;
    esac
    
    local existing=$(curl -s -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"platform.getBlockchains","params":{},"id":1}' \
        http://127.0.0.1:$port/ext/bc/P | jq -r ".result.blockchains[] | select(.name==\"$chain\") | .id")
    
    if [ -n "$existing" ]; then
        echo -e "${GREEN}✓${NC} $chain already deployed: $existing"
        return 0
    fi
    
    # Deploy
    echo "y" | lux chain deploy $chain $flag 2>&1
    
    # Verify
    sleep 2
    local newid=$(curl -s -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"platform.getBlockchains","params":{},"id":1}' \
        http://127.0.0.1:$port/ext/bc/P | jq -r ".result.blockchains[] | select(.name==\"$chain\") | .id")
    
    if [ -n "$newid" ]; then
        echo -e "${GREEN}✓${NC} $chain deployed: $newid"
    else
        echo -e "${RED}✗${NC} Failed to deploy $chain"
        return 1
    fi
}

deploy_chain "hanzo" "mainnet" "--mainnet"
deploy_chain "hanzotest" "testnet" "--testnet"
deploy_chain "hanzo" "devnet" "--devnet"

echo ""
echo "==========================================="
echo "  DEPLOYED CHAINS"
echo "==========================================="

# Get all blockchain IDs
echo ""
echo "Mainnet chains:"
curl -s -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"platform.getBlockchains","params":{},"id":1}' \
    http://127.0.0.1:9630/ext/bc/P | jq -r '.result.blockchains[] | "  \(.name): \(.id)"'

echo ""
echo "Testnet chains:"
curl -s -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"platform.getBlockchains","params":{},"id":1}' \
    http://127.0.0.1:9640/ext/bc/P | jq -r '.result.blockchains[] | "  \(.name): \(.id)"'

echo ""
echo "Devnet chains:"
curl -s -X POST -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"platform.getBlockchains","params":{},"id":1}' \
    http://127.0.0.1:9650/ext/bc/P | jq -r '.result.blockchains[] | "  \(.name): \(.id)"'

echo ""
echo "==========================================="
echo "  DEPLOYMENT COMPLETE"
echo "==========================================="
echo ""
echo "Next: Deploy AI token to Hanzo chain"
echo ""
echo "Get the Hanzo blockchain ID and run:"
echo "  cd ~/work/lux/standard"
echo "  export LUX_MNEMONIC=\"your mnemonic\""
echo "  export HANZO_RPC=\"http://127.0.0.1:9630/ext/bc/<HANZO_ID>/rpc\""
echo "  forge script script/DeployAI.s.sol --rpc-url \$HANZO_RPC --broadcast"
