#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════════════════
# Lux Standard Protocol - Deployment Script
# ═══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./deploy.sh <network>
#
# Networks:
#   local      - Deploy to local Anvil instance
#   testnet    - Deploy to Lux Testnet (96368)
#   mainnet    - Deploy to Lux Mainnet (96369)
#   hanzo      - Deploy to Hanzo Mainnet (36963)
#   zoo        - Deploy to Zoo Mainnet (200200)
#   all        - Deploy to all mainnets
#
# Environment:
#   PRIVATE_KEY    - Deployer private key (required for non-local)
#   RPC_URL        - Override default RPC URL
#   VERIFY         - Set to "true" to verify contracts
#   TREASURY       - Treasury/multisig address (optional)
#
# ═══════════════════════════════════════════════════════════════════════════════

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Chain configurations
declare -A CHAINS
CHAINS[local]="31337|http://localhost:8545|Local Anvil"
CHAINS[testnet]="96368|https://testnet.rpc.lux.network|Lux Testnet"
CHAINS[mainnet]="96369|https://rpc.lux.network|Lux Mainnet"
CHAINS[hanzo]="36963|https://rpc.hanzo.ai|Hanzo Mainnet"
CHAINS[zoo]="200200|https://rpc.zoo.industries|Zoo Mainnet"

# Parse chain config
get_chain_id() { echo "${CHAINS[$1]}" | cut -d'|' -f1; }
get_rpc_url() { echo "${CHAINS[$1]}" | cut -d'|' -f2; }
get_chain_name() { echo "${CHAINS[$1]}" | cut -d'|' -f3; }

# Header
print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              LUX STANDARD PROTOCOL - DEPLOYMENT                     ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check requirements
check_requirements() {
    if ! command -v forge &> /dev/null; then
        echo -e "${RED}Error: forge not found. Install foundry: https://getfoundry.sh${NC}"
        exit 1
    fi
}

# Deploy to a single network
deploy_to_network() {
    local network=$1
    local chain_id=$(get_chain_id "$network")
    local rpc_url=${RPC_URL:-$(get_rpc_url "$network")}
    local chain_name=$(get_chain_name "$network")

    echo -e "${YELLOW}Deploying to ${chain_name} (Chain ID: ${chain_id})...${NC}"
    echo ""

    # Build first
    echo "Building contracts..."
    forge build --silent

    # Select the right deployment contract
    local contract="script/DeployCreate2.s.sol:DeployCreate2Local"
    if [[ "$network" == "local" ]]; then
        contract="script/DeployCreate2.s.sol:DeployCreate2Local"
    elif [[ "$network" == "testnet" ]]; then
        contract="script/DeployCreate2.s.sol:DeployCreate2Testnet"
    else
        contract="script/DeployCreate2.s.sol:DeployCreate2Mainnet"
    fi

    # Deployment command
    local cmd="forge script $contract --rpc-url $rpc_url --broadcast"

    # Add private key for non-local
    if [[ "$network" != "local" ]]; then
        if [[ -z "$PRIVATE_KEY" ]]; then
            echo -e "${RED}Error: PRIVATE_KEY environment variable required${NC}"
            exit 1
        fi
        cmd="$cmd --private-key $PRIVATE_KEY"
    else
        # Use Anvil's default account for local
        cmd="$cmd --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    fi

    # Add verification if requested
    if [[ "$VERIFY" == "true" && "$network" != "local" ]]; then
        cmd="$cmd --verify"
    fi

    # Execute
    echo "Executing: $cmd"
    echo ""
    eval $cmd

    echo ""
    echo -e "${GREEN}✓ Deployment to ${chain_name} complete!${NC}"
    echo ""

    # Save deployment info
    mkdir -p deployments
    local timestamp=$(date +%Y%m%d_%H%M%S)
    echo "Deployment completed at $timestamp" >> "deployments/${chain_id}_history.txt"
}

# Main
main() {
    print_header
    check_requirements

    local network=${1:-help}

    case $network in
        local)
            # Start Anvil if not running
            if ! nc -z localhost 8545 2>/dev/null; then
                echo "Starting Anvil..."
                anvil &
                sleep 2
            fi
            deploy_to_network "local"
            ;;

        testnet)
            deploy_to_network "testnet"
            ;;

        mainnet)
            echo -e "${RED}⚠️  WARNING: Deploying to MAINNET${NC}"
            echo ""
            read -p "Are you sure? (type 'yes' to continue): " confirm
            if [[ "$confirm" != "yes" ]]; then
                echo "Aborted."
                exit 1
            fi
            deploy_to_network "mainnet"
            ;;

        hanzo)
            deploy_to_network "hanzo"
            ;;

        zoo)
            deploy_to_network "zoo"
            ;;

        all)
            echo -e "${RED}⚠️  WARNING: Deploying to ALL MAINNETS${NC}"
            echo ""
            read -p "Are you sure? (type 'yes' to continue): " confirm
            if [[ "$confirm" != "yes" ]]; then
                echo "Aborted."
                exit 1
            fi
            deploy_to_network "mainnet"
            deploy_to_network "hanzo"
            deploy_to_network "zoo"
            echo -e "${GREEN}✓ All mainnet deployments complete!${NC}"
            ;;

        compute)
            echo "Computing deterministic addresses..."
            forge script script/ComputeAddresses.s.sol -v
            ;;

        verify)
            local chain_id=${2:-96369}
            local address=$3
            local contract=$4
            if [[ -z "$address" || -z "$contract" ]]; then
                echo "Usage: ./deploy.sh verify <chain_id> <address> <contract>"
                exit 1
            fi
            forge verify-contract "$address" "$contract" --chain-id "$chain_id"
            ;;

        help|*)
            echo "Usage: ./deploy.sh <command>"
            echo ""
            echo "Commands:"
            echo "  local     Deploy to local Anvil instance"
            echo "  testnet   Deploy to Lux Testnet (96368)"
            echo "  mainnet   Deploy to Lux Mainnet (96369)"
            echo "  hanzo     Deploy to Hanzo Mainnet (36963)"
            echo "  zoo       Deploy to Zoo Mainnet (200200)"
            echo "  all       Deploy to all mainnets"
            echo "  compute   Compute deterministic addresses before deployment"
            echo "  verify    Verify contract on explorer"
            echo ""
            echo "Environment:"
            echo "  PRIVATE_KEY    Deployer private key (required for non-local)"
            echo "  RPC_URL        Override default RPC URL"
            echo "  VERIFY         Set to 'true' to verify contracts"
            echo "  CREATE2_FACTORY  Address of Create2Deployer (for compute)"
            echo ""
            echo "Examples:"
            echo "  ./deploy.sh local"
            echo "  PRIVATE_KEY=0x... ./deploy.sh testnet"
            echo "  PRIVATE_KEY=0x... VERIFY=true ./deploy.sh mainnet"
            echo "  CREATE2_FACTORY=0x... ./deploy.sh compute"
            ;;
    esac
}

main "$@"
