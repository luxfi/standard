#!/bin/bash
# Deploy Lux standard contracts to all three networks
#
# Networks:
# - Mainnet: http://209.38.175.130:9630/ext/bc/C/rpc (chain-id: 1337)
# - Testnet: http://24.199.70.106:9640/ext/bc/C/rpc (chain-id: 1337)
# - Devnet: http://24.199.74.128:9650/ext/bc/C/rpc (chain-id: 1337)
#
# Funded account (from "light energy" mnemonic):
# - Primary: 0x35D64Ff3f618f7a17DF34DCb21be375A4686a8de

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Network configurations (updated 2026-02-03)
MAINNET_RPC="http://146.190.15.157:9630/ext/bc/C/rpc"
TESTNET_RPC="http://134.199.184.173:9640/ext/bc/C/rpc"
DEVNET_RPC="http://24.199.78.71:9650/ext/bc/C/rpc"

CHAIN_ID=1337

# Mnemonic for deployment
export LUX_MNEMONIC="light light light light light light light light light light light energy"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  LUX MULTI-NETWORK DEPLOYMENT${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

# Check network connectivity
check_network() {
    local rpc=$1
    local name=$2

    echo -n "Checking $name... "

    local result=$(curl -s --connect-timeout 5 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "$rpc" 2>/dev/null)

    if echo "$result" | grep -q "result"; then
        local chain_id=$(echo "$result" | jq -r '.result' 2>/dev/null)
        echo -e "${GREEN}OK${NC} (chain-id: $chain_id)"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        echo "  Response: $result"
        return 1
    fi
}

# Check deployer balance
check_balance() {
    local rpc=$1
    local name=$2
    local address="0x35D64Ff3f618f7a17DF34DCb21be375A4686a8de"

    local result=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$address\",\"latest\"],\"id\":1}" \
        "$rpc" 2>/dev/null)

    if echo "$result" | grep -q "result"; then
        local balance_hex=$(echo "$result" | jq -r '.result' 2>/dev/null)
        local balance_wei=$(printf "%d" "$balance_hex" 2>/dev/null || echo "0")
        local balance_ether=$(echo "scale=4; $balance_wei / 1000000000000000000" | bc 2>/dev/null || echo "0")
        echo "  Deployer balance on $name: $balance_ether LUX"

        if [ "$(echo "$balance_ether < 1" | bc)" -eq 1 ]; then
            echo -e "  ${RED}WARNING: Insufficient balance for deployment${NC}"
            return 1
        fi
    fi
    return 0
}

# Deploy to network
deploy_to_network() {
    local rpc=$1
    local name=$2
    local output_file=$3

    echo ""
    echo -e "${YELLOW}==========================================${NC}"
    echo -e "${YELLOW}  Deploying to $name${NC}"
    echo -e "${YELLOW}==========================================${NC}"
    echo ""

    # Run forge script
    forge script contracts/script/DeployMultiNetwork.s.sol \
        --rpc-url "$rpc" \
        --broadcast \
        --legacy \
        -vvv 2>&1 | tee "$output_file"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo ""
        echo -e "${GREEN}Deployment to $name SUCCESSFUL${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}Deployment to $name FAILED${NC}"
        return 1
    fi
}

# Extract deployed addresses from output
extract_addresses() {
    local output_file=$1
    local network=$2

    echo ""
    echo "Extracting addresses for $network..."

    # Parse the log file for contract addresses
    grep -E "^  [A-Z].*: *0x[a-fA-F0-9]{40}$" "$output_file" 2>/dev/null || true
}

# Main deployment flow
echo "Checking network connectivity..."
echo ""

mainnet_ok=false
testnet_ok=false
devnet_ok=false

if check_network "$MAINNET_RPC" "Mainnet"; then
    check_balance "$MAINNET_RPC" "Mainnet" && mainnet_ok=true
fi

if check_network "$TESTNET_RPC" "Testnet"; then
    check_balance "$TESTNET_RPC" "Testnet" && testnet_ok=true
fi

if check_network "$DEVNET_RPC" "Devnet"; then
    check_balance "$DEVNET_RPC" "Devnet" && devnet_ok=true
fi

echo ""

# Summary of network status
echo -e "${BLUE}Network Status:${NC}"
echo -e "  Mainnet: $($mainnet_ok && echo -e "${GREEN}Ready${NC}" || echo -e "${RED}Not Ready${NC}")"
echo -e "  Testnet: $($testnet_ok && echo -e "${GREEN}Ready${NC}" || echo -e "${RED}Not Ready${NC}")"
echo -e "  Devnet:  $($devnet_ok && echo -e "${GREEN}Ready${NC}" || echo -e "${RED}Not Ready${NC}")"
echo ""

# Create output directory
mkdir -p deployments/logs

# Deploy to available networks
if $mainnet_ok; then
    deploy_to_network "$MAINNET_RPC" "Mainnet" "deployments/logs/mainnet_$(date +%Y%m%d_%H%M%S).log"
fi

if $testnet_ok; then
    deploy_to_network "$TESTNET_RPC" "Testnet" "deployments/logs/testnet_$(date +%Y%m%d_%H%M%S).log"
fi

if $devnet_ok; then
    deploy_to_network "$DEVNET_RPC" "Devnet" "deployments/logs/devnet_$(date +%Y%m%d_%H%M%S).log"
fi

echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  DEPLOYMENT SUMMARY${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo "Deployment logs saved to: deployments/logs/"
echo ""
echo "To verify contracts, run:"
echo "  forge verify-contract <ADDRESS> <CONTRACT> --rpc-url <RPC>"
echo ""
