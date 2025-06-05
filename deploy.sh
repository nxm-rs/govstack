#!/bin/bash

# Governance Stack Interactive Deployment Script
# This script sets up environment variables and calls the interactive deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${BLUE}"
    echo "======================================"
    echo "$1"
    echo "======================================"
    echo -e "${NC}"
}

# Function to prompt for RPC URL
prompt_rpc_url() {
    print_header "RPC Configuration"
    print_info "Please provide an RPC URL for blockchain connection:"
    echo
    print_info "Examples:"
    echo "  Mainnet: https://mainnet.infura.io/v3/YOUR_PROJECT_ID"
    echo "  Mainnet: https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
    echo "  Sepolia: https://sepolia.infura.io/v3/YOUR_PROJECT_ID"
    echo "  Local:   http://localhost:8545"
    echo

    while true; do
        read -p "Enter RPC URL: " rpc_url

        if [[ -z "$rpc_url" ]]; then
            print_error "RPC URL cannot be empty. Please enter a valid URL."
            continue
        fi

        if [[ "$rpc_url" =~ ^https?:// ]]; then
            export RPC_URL="$rpc_url"
            print_success "RPC URL set: $rpc_url"
            break
        else
            print_error "Please enter a valid HTTP/HTTPS URL."
        fi
    done
    echo
}



# Function to show verification commands for a specific contract
show_contract_verification() {
    local contract_name="$1"
    local contract_address="$2"
    
    print_info "To verify the $contract_name contract on Sourcify:"
    echo "  forge verify-contract --rpc-url $RPC_URL $contract_address"
    echo
    print_info "To verify the $contract_name contract on Etherscan:"
    echo "  forge verify-contract --rpc-url $RPC_URL --etherscan-api-key <YOUR_API_KEY> $contract_address"
    echo
}

# Function to provide manual verification guidance
show_verification_guidance() {
    print_header "Contract Verification"
    print_info "To verify your deployed contracts, you can use the following commands:"
    echo

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Contract addresses will need to be extracted manually from deployment output."
        print_info "Install jq to automatically extract addresses: apt-get install jq (or brew install jq on macOS)"
        echo
    fi

    # Find the most recent broadcast file
    local broadcast_dir="broadcast/Deploy.s.sol"
    local chain_id=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || echo "unknown")
    local broadcast_file
    
    if [[ -f "$broadcast_dir/$chain_id/runInteractiveWithScenario-latest.json" ]]; then
        broadcast_file="$broadcast_dir/$chain_id/runInteractiveWithScenario-latest.json"
    else
        # Look for any recent broadcast file as fallback
        broadcast_file=$(find "$broadcast_dir" -name "*latest.json" -type f 2>/dev/null | head -1)
    fi

    if [[ -f "$broadcast_file" ]] && command -v jq &> /dev/null; then
        print_info "Extracting contract addresses from broadcast file..."
        
        # Extract contract addresses from transaction logs using event topic hashes
        local token_address=$(jq -r '.receipts[0]?.logs[]? | select(.topics[0] == "0xcbceb2a71186186f122db5bab7bde42a9ae01fdb01216247c5532f66cea8aaef") | .topics[1] // empty' "$broadcast_file" 2>/dev/null | head -1)
        local governor_address=$(jq -r '.receipts[0]?.logs[]? | select(.topics[0] == "0x48dde23f2c9b4f804a9531f4c202bad0ecc19810335bbe6c775acb078ab76aae") | .topics[1] // empty' "$broadcast_file" 2>/dev/null | head -1)
        local splitter_address=$(jq -r '.receipts[0]?.logs[]? | select(.topics[0] == "0x25becba37ef6dc7e3abf7e664e271f097329426ac54fb5c5987ebc84452b650e") | .topics[1] // empty' "$broadcast_file" 2>/dev/null | head -1)

        # Convert from padded hex to address format
        if [[ -n "$token_address" && "$token_address" != "null" ]]; then
            token_address="0x${token_address:26}"
            print_success "Token contract: $token_address"
        fi
        
        if [[ -n "$governor_address" && "$governor_address" != "null" ]]; then
            governor_address="0x${governor_address:26}"
            print_success "Governor contract: $governor_address"
        fi
        
        if [[ -n "$splitter_address" && "$splitter_address" != "null" ]]; then
            splitter_address="0x${splitter_address:26}"
            print_success "Splitter contract: $splitter_address"
        fi
        echo

        # Provide specific verification commands if addresses were found
        if [[ -n "$token_address" ]]; then
            show_contract_verification "Token" "$token_address"
        fi

        if [[ -n "$governor_address" ]]; then
            show_contract_verification "Governor" "$governor_address"
        fi

        if [[ -n "$splitter_address" ]]; then
            show_contract_verification "Splitter" "$splitter_address"
        fi
    else
        print_warning "Could not automatically extract contract addresses."
        print_info "Check the deployment output above for contract addresses, then use:"
        echo
    fi

    print_info "General verification commands:"
    print_info "• For Sourcify (free, no API key needed):"
    echo "  forge verify-contract --rpc-url $RPC_URL <CONTRACT_ADDRESS>"
    echo
    print_info "• For Etherscan (requires API key from https://etherscan.io/apis):"
    echo "  forge verify-contract --rpc-url $RPC_URL --etherscan-api-key <API_KEY> <CONTRACT_ADDRESS>"
    echo
    print_info "Example with real addresses from your deployment:"
    echo "  forge verify-contract --rpc-url $RPC_URL 0xa22e305c656d3a927d1d3b81a75521e3ca59f3f5"
    echo "  forge verify-contract --rpc-url $RPC_URL --etherscan-api-key <API_KEY> 0xa22e305c656d3a927d1d3b81a75521e3ca59f3f5"
    echo
    print_info "Note: The Deployer contract self-destructs and cannot be verified."
    print_info "Only verify the Token, Governor, and Splitter contracts."
}

# Function to run interactive deployment
run_deployment() {
    print_header "Starting Interactive Deployment"

    print_warning "SECURITY REMINDERS:"
    print_warning "• Use a dedicated deployment wallet with minimal funds"
    print_warning "• Never use your main wallet's private key for production"
    print_warning "• Test on Sepolia testnet before mainnet deployment"
    print_warning "• Double-check all configuration before deployment"
    echo

    print_info "The deployment script will now:"
    print_info "• Discover and list available configuration files"
    print_info "• Parse scenarios dynamically from your selected config"
    print_info "• Show scenario descriptions from TOML files"
    print_info "• Prompt for private key (entered securely)"
    echo

    read -p "Press Enter to continue with deployment..."
    echo

    # Run the interactive deployment (first phase)
    local forge_args=(
        "script/Deploy.s.sol:Deploy"
        "--sig" "runInteractiveWithScenario()"
        "--rpc-url" "$RPC_URL"
        "--broadcast"
    )
    
    print_info "Running deployment phase..."
    if forge script "${forge_args[@]}"; then
        print_success "Deployment phase completed successfully."
    else
        print_error "Deployment phase failed."
        return 1
    fi
    
    # Wait a moment for broadcast file to be fully written
    print_info "Waiting for broadcast file to be written..."
    sleep 2
    
    # Show verification guidance
    show_verification_guidance
}

# Main function
main() {
    print_header "Governance Stack Deployment"
    print_info "This script will guide you through a secure deployment process."
    echo

    # Check if we're in the right directory
    if [[ ! -f "script/Deploy.s.sol" ]]; then
        print_error "Deploy.s.sol not found. Please run this script from the governance directory."
        exit 1
    fi

    # Build contracts first
    print_info "Building contracts..."
    if forge build; then
        print_success "Contracts built successfully."
    else
        print_error "Failed to build contracts."
        exit 1
    fi
    echo

    # Prompt for environment setup
    prompt_rpc_url

    # Run deployment
    run_deployment

    # Check result
    if [[ $? -eq 0 ]]; then
        print_success "Deployment completed!"
        print_info "Deployment artifacts are saved in the 'broadcast/' directory."
        print_info "Use the verification commands shown above to verify your contracts."
    else
        print_error "Deployment failed. Check the error messages above."
    fi
}

# Show help
show_help() {
    echo "Governance Stack Interactive Deployment Script"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo
    echo "This script provides a secure, interactive way to deploy the governance stack."
    echo "It will prompt you for:"
    echo "  1. RPC URL for blockchain connection"
    echo "  2. Configuration file (dynamically discovered from config/)"
    echo "  3. Distribution and splitter scenarios (parsed from your config)"
    echo "  4. Private key (securely via Solidity prompts)"
    echo
    echo "The script automatically sets required environment variables and calls"
    echo "the interactive Solidity deployment script, then provides guidance for manual"
    echo "contract verification."
    echo
    echo "Prerequisites:"
    echo "  • Foundry installed and configured"
    echo "  • Sufficient ETH in deployment wallet for gas fees"
    echo "  • Configuration files in the 'config/' directory"
    echo
    echo "Security Features:"
    echo "  • No sensitive data stored in files"
    echo "  • Private keys prompted securely by Foundry"
    echo "  • Dynamic discovery of config files and scenarios"
    echo "  • Clear security warnings and best practices"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information."
        exit 1
        ;;
esac
