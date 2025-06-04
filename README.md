# Governance Stack Deployment System

A comprehensive Solidity-based governance system built with Foundry, featuring configurable governance tokens, DAO governors, and dividend splitters with atomic deployment capabilities.

## Overview

This system provides a complete governance infrastructure consisting of three main contracts deployed atomically:

1. **Token.sol** - ERC20 governance token with voting capabilities (ERC20Votes)
2. **Governor.sol** - OpenZeppelin-based governor contract for DAO governance
3. **Splitter.sol** - Revenue/dividend distribution contract among stakeholders

All contracts are deployed through a single `Deploy.s.sol` script that uses TOML configuration files for complete customization. The deployment system supports time-based governance parameters with millisecond precision for accurate cross-network deployment.

## Features

### 🏛️ Complete Governance Stack
- **ERC20 Governance Token** with built-in voting capabilities
- **DAO Governor** with configurable voting periods, delays, and quorum
- **Token Splitter** for automated revenue/dividend distribution
- **Atomic Deployment** - All contracts deployed in a single transaction

### ⚙️ Advanced Configuration
- **TOML-based Configuration** for all deployment parameters
- **Time-based Parameters** with automatic block conversion
- **Multiple Distribution Scenarios** (default, startup, DAO, test)
- **Multiple Splitter Scenarios** for different revenue sharing models
- **Network-specific Optimization** with proper gas settings

### 🔧 Developer Experience
- **Comprehensive Test Suite** with 87 tests and 100% pass rate
- **Rich Helper Utilities** for testing governance scenarios
- **Gas Optimization** with detailed gas reporting
- **Automated Deployment Artifacts** saved to `deployments/` directory

### 🌐 Multi-Network Support
- **Ethereum Mainnet** (12s blocks) - Primary deployment target
- **Sepolia Testnet** (12s blocks) - For testing

## Quick Deploy

```bash
# 1. Install and build
forge install && forge build

# 2. Configure deployment
# Edit config/deployment.toml with your settings

# 3. Deploy interactively
./deploy.sh
```

The script guides you through selecting configuration files and scenarios, then prompts securely for your RPC URL, Etherscan API key, and private key.

## Quick Start

### 1. Install Dependencies

```bash
# Clone the repository
git clone <repository-url>
cd governance

# Install Foundry dependencies
forge install

# Verify installation
forge build
forge test
```

### 2. Deployment Options

**Interactive (Recommended)**
```bash
./deploy.sh
```

**Direct Forge Script**
```bash
# Set environment variables
export ETH_RPC_URL="your_rpc_url"
export ETHERSCAN_API_KEY="your_api_key"

# Deploy with interactive scenario selection
forge script script/Deploy.s.sol:Deploy \
  --sig "runInteractiveWithScenario()" \
  --rpc-url $ETH_RPC_URL \
  --broadcast \
  --verify
```

## Configuration

Edit `config/deployment.toml` to customize your deployment:

```toml
[token]
name = "My Governance Token"
symbol = "MGT"
initial_supply = 0

[governor]
name = "My DAO Governor"
voting_delay_time = "2 days"
voting_period_time = "1 week"
late_quorum_extension_time = "6 hours"
quorum_numerator = 5  # 5% quorum

[treasury]
address = "0x1234567890123456789012345678901234567890"

[deployment]
scenario = "default"          # Distribution scenario
splitter_scenario = "default" # Revenue splitter scenario
verify = true
save_artifacts = true
```

The interactive deployment will show available scenarios from your config files and let you select them dynamically. See the `config/` directory for example configurations and scenario definitions.

## Deployment

### Prerequisites

1. **Configure**: Edit `config/deployment.toml` with your settings
2. **API Keys**: Get RPC URL and Etherscan API key
3. **Test First**: Deploy on Sepolia testnet before mainnet

### Deploy to Mainnet

```bash
# Interactive deployment (recommended)
./deploy.sh

# When prompted:
# - RPC URL: https://eth.merkle.io
# - Etherscan API key: YOUR_ETHERSCAN_KEY
# - Select config/deployment.toml
# - Choose your desired scenarios
# - Enter private key securely
```

Deployment artifacts are saved to `deployments/` and contracts are automatically verified.

## Contract Interactions

### Token Contract

```solidity
// Basic ERC20 operations
token.balanceOf(account);
token.transfer(to, amount);
token.approve(spender, amount);

// Governance features
token.delegate(delegatee);          // Delegate voting power
token.getPastVotes(account, blockNumber);  // Historical voting power

// Treasury-only functions (requires treasury address)
token.mint(to, amount);             // Mint new tokens
token.burn(from, amount);           // Burn tokens
```

### Governor Contract

```solidity
// Create proposal
uint256 proposalId = governor.propose(
    targets,     // Contract addresses to call
    values,      // ETH values for each call
    calldatas,   // Function call data
    description  // Proposal description
);

// Vote on proposal
governor.castVote(proposalId, support);  // 0=Against, 1=For, 2=Abstain

// Execute proposal (after successful vote)
governor.execute(targets, values, calldatas, descriptionHash);

// Check proposal state
IGovernor.ProposalState state = governor.state(proposalId);
```

### Splitter Contract

```solidity
// Split specific token among payees
splitter.splitToken(tokenAddress);

// Split all supported tokens
splitter.splitAllTokens();

// Check pending distributions
uint256 pending = splitter.pendingTokens(tokenAddress, payeeAddress);

// View payee information
address[] memory payees = splitter.getAllPayees();
```

## Built-in Scenarios

The deployment system automatically discovers scenarios from your config files. The interactive deployment lists available options with descriptions and lets you select by number.

Example scenarios in `config/deployment.toml`:
- **default** - Balanced governance distribution
- **startup** - Startup-focused allocation
- **dao** - DAO-centric distribution
- **test** - Development testing

For revenue splitting:
- **default** - Balanced operations split
- **simple** - 50/50 partnership split
- **revenue_share** - Investor-focused distribution
- **none** - Skip splitter deployment

Add new scenarios to config files and they automatically appear in the interactive selection.

## Testing

### Run Test Suite

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test contract
forge test --match-contract TokenTest

# Generate gas report
forge test --gas-report

# Run with coverage
forge coverage
```

### Test Results

- **162 total tests** across 5 test suites
- **100% pass rate**
- **Comprehensive coverage** of all governance scenarios
- **Time-based testing** with millisecond precision
- **Cross-network validation**

## Network Configuration

### Supported Networks

| Network | Chain ID | Block Time | Gas Price | Description |
|---------|----------|------------|-----------|-------------|
| Ethereum Mainnet | 1 | 12s | 20 gwei | Primary deployment |
| Sepolia Testnet | 11155111 | 12s | 10 gwei | Recommended testnet |

### Time Conversion Examples

| Time Period | Ethereum (12s) | Fast L2 (2s) |
|-------------|----------------|---------------|
| 1 hour | 300 blocks | 1,800 blocks |
| 1 day | 7,200 blocks | 43,200 blocks |
| 1 week | 50,400 blocks | 302,400 blocks |

## Security Features

### Access Control
- **Treasury-controlled minting/burning** on Token contract
- **Governor-controlled parameters** (voting delay, period, quorum)
- **Splitter owned by Governor** for decentralized revenue management

### Validation
- **Distribution validation** prevents duplicate recipients and zero amounts
- **Splitter validation** ensures shares total exactly 100%
- **Time parameter validation** prevents invalid governance configurations
- **Address validation** prevents zero address assignments

### Deployment Security
- **CREATE2 deployment** with unique salts for predictable addresses
- **Atomic deployment** ensures all-or-nothing contract creation
- **Comprehensive testing** with edge case coverage

## :warning: Security Notes

> **Warning**
>
> These contracts have **not been audited**. Use at your own risk.
>
> - The code is provided as-is and may contain bugs or vulnerabilities.
> - Do not use in production or with mainnet funds unless you have performed your own thorough security review and/or audit.
> - The Nexum Contributors and maintainers take no responsibility for any loss of funds or damages resulting from the use of this code.

## Deployment Artifacts

After deployment, artifacts are saved to `deployments/chainId_timestamp.json`:

```json
{
  "chainId": 1,
  "timestamp": 1234567890,
  "salt": "0x123...",
  "deployer": "0xabc...",
  "token": "0xdef...",
  "governor": "0x456...",
  "splitter": "0x789...",
  "gasUsed": {
    "total": 5234567,
    "token": 1234567,
    "governor": 2345678,
    "splitter": 1654322
  }
}
```

## Gas Costs

Typical gas costs on Ethereum mainnet:
- Full Deployment: ~5.2M gas
- Create Proposal: ~250K gas
- Cast Vote: ~80K gas

## Troubleshooting

**Common Issues:**
- **Gas Failed**: Ensure sufficient ETH balance and reasonable gas limits
- **Invalid Config**: Check addresses and amounts in config files
- **Verification Failed**: Verify Etherscan API key and network support

**Debug Commands:**
```bash
# Preview without broadcasting
forge script script/Deploy.s.sol:Deploy

# Verbose output
forge script script/Deploy.s.sol:Deploy -vvv
```



## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes and add tests
4. Ensure all tests pass: `forge test`
5. Submit a pull request

### Development Workflow

```bash
# Install dependencies
forge install

# Run tests during development
forge test --watch

# Check gas usage
forge test --gas-report

# Run specific tests
forge test --match-test testProposalCreation

# Format code
forge fmt
```

## License

This project is licensed under the AGPL-3.0-or-later license.
See the [LICENCE](./LICENCE) file for the full license text.

## Support

For questions, issues, or feature requests:
- Open an issue in the repository
- Review test files for usage examples
- Contact the development team

---

## Forwarder System

For details on the deterministic token forwarding system and cross-chain bridging, see [src/forwarders/README.md](src/forwarders/README.md).
