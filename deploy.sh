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

# Function to prompt for Etherscan API key
prompt_etherscan_key() {
    print_header "Etherscan Configuration"
    print_info "Etherscan API key is required for contract verification."
    print_info "Get your free API key from: https://etherscan.io/apis"
    echo

    read -p "Enter Etherscan API key (or press Enter to skip verification): " etherscan_key

    if [[ -n "$etherscan_key" ]]; then
        export ETHERSCAN_API_KEY="$etherscan_key"
        print_success "Etherscan API key configured for contract verification."
    else
        print_warning "No Etherscan API key provided. Contract verification will be skipped."
        print_info "You can manually verify contracts later using:"
        print_info "forge verify-contract <address> <contract> --etherscan-api-key <key>"
    fi
    echo
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

    # Run the interactive deployment
    local forge_args=(
        "script/Deploy.s.sol:Deploy"
        "--sig" "runInteractiveWithScenario()"
        "--rpc-url" "$RPC_URL"
        "--broadcast"
    )
    
    # Add verification if Etherscan API key is provided
    if [[ -n "$ETHERSCAN_API_KEY" ]]; then
        forge_args+=("--verify" "--etherscan-api-key" "$ETHERSCAN_API_KEY")
    fi
    
    forge script "${forge_args[@]}"
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
    prompt_etherscan_key

    # Run deployment
    run_deployment

    # Check result
    if [[ $? -eq 0 ]]; then
        print_success "Deployment completed!"
        print_info "Check the output above for deployed contract addresses."
        print_info "Deployment artifacts are saved in the 'deployments/' directory."
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
    echo "  2. Etherscan API key for contract verification (optional)"
    echo "  3. Configuration file (dynamically discovered from config/)"
    echo "  4. Distribution and splitter scenarios (parsed from your config)"
    echo "  5. Private key (securely via Solidity prompts)"
    echo
    echo "The script automatically sets required environment variables and calls"
    echo "the interactive Solidity deployment script."
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
