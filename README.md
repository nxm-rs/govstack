# Governance Stack Deployment System

A comprehensive Solidity-based governance system built with Foundry, featuring configurable governance tokens, DAO governors, and dividend splitters with atomic deployment capabilities.

## Overview

This system provides a complete governance infrastructure consisting of three main contracts deployed atomically:

1. **Token.sol** - ERC20 governance token with voting capabilities (ERC20Votes)
2. **TokenGovernor.sol** - OpenZeppelin-based governor contract for DAO governance
3. **TokenSplitter.sol** - Revenue/dividend distribution contract among stakeholders

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

### 2. Basic Deployment

```bash
# Deploy with default configuration to localhost
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast

# Deploy to mainnet
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### 3. Custom Deployment

```bash
# Deploy with specific distribution scenario
forge script script/Deploy.s.sol:Deploy \
  --sig "runWithDistributionScenario(string)" "dao" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# Deploy without splitter
forge script script/Deploy.s.sol:Deploy \
  --sig "runWithoutSplitter(string)" "startup" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Configuration

### Main Configuration File

Edit `config/deployment.toml` to customize your deployment:

```toml
[token]
name = "My Governance Token"
symbol = "MGT"
initial_supply = 0

[governor]
name = "My DAO Governor"
voting_delay_time = "2 days"      # Time before voting starts
voting_period_time = "1 week"     # Duration of voting period
late_quorum_extension_time = "6 hours"  # Extension if quorum reached late
quorum_numerator = 500             # 5% quorum requirement

[treasury]
address = "0x1234567890123456789012345678901234567890"  # Treasury address with minting/burning privileges

[deployment]
scenario = "default"               # Distribution scenario to use
splitter_scenario = "default"      # Splitter scenario (or "none")
verify = true                      # Verify on Etherscan
save_artifacts = true              # Save deployment info
```

### Distribution Scenarios

Define token distribution among stakeholders:

```toml
[distributions.dao]
description = "DAO-focused distribution"

[[distributions.dao.recipients]]
name = "DAO Treasury"
address = "0x1111111111111111111111111111111111111111"
amount = "5000000000000000000000000"  # 5M tokens (50%)
description = "Main DAO treasury"

[[distributions.dao.recipients]]
name = "Core Contributors"
address = "0x2222222222222222222222222222222222222222"
amount = "2500000000000000000000000"  # 2.5M tokens (25%)
description = "Core team allocation"

# Add more recipients...
```

### Revenue Splitter Configuration

Configure automated revenue distribution:

```toml
[splitter.default]
description = "Revenue sharing among stakeholders"

[[splitter.default.payees]]
account = "0x1111111111111111111111111111111111111111"
shares = 4000  # 40% to Treasury

[[splitter.default.payees]]
account = "0x2222222222222222222222222222222222222222"
shares = 3000  # 30% to Development Fund

# Total shares must equal 10000 (100%)
```

## Deployment for Mainnet

### Prerequisites

1. **Set Environment Variables**:
```bash
export MAINNET_RPC_URL="https://mainnet.infura.io/v3/YOUR_KEY"
export PRIVATE_KEY="0x..."
export ETHERSCAN_API_KEY="YOUR_ETHERSCAN_KEY"
```

2. **Configure Deployment**:
   - Edit `config/deployment.toml`
   - Set your treasury address
   - Configure distribution recipients
   - Set appropriate governance parameters

3. **Test First**:
```bash
# Test on Sepolia first
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### Mainnet Deployment Steps

1. **Preview Deployment**:
```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY
# Do not add --broadcast flag for preview
```

2. **Execute Deployment**:
```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --gas-estimate-multiplier 120
```

3. **Verify Deployment**:
   - Check `deployments/` directory for deployment artifacts
   - Verify contracts on Etherscan
   - Test basic functionality (minting, proposals, voting)

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

### TokenSplitter Contract

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

### Distribution Scenarios

| Scenario | Description | Use Case |
|----------|-------------|----------|
| `default` | Balanced governance (40% treasury, 25% contributors, 20% ecosystem, 15% community) | General DAO launches |
| `startup` | Startup-focused (30% founders, 20% team, 25% investors, 25% public) | Early-stage projects |
| `dao` | DAO-centric (50% treasury, 20% mining, 15% grants, 15% community) | Decentralized protocols |
| `test` | Small amounts for testing | Development/testing |

### Splitter Scenarios

| Scenario | Description | Use Case |
|----------|-------------|----------|
| `default` | Balanced operations (40% treasury, 30% dev, 20% marketing, 10% ops) | Standard operations |
| `simple` | 50/50 split | Partnerships |
| `revenue_share` | Investor-focused (50% investors, 30% team, 15% advisors, 5% reserve) | Revenue distribution |

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

- **87 total tests** across 5 test suites
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

| Operation | Gas Cost |
|-----------|----------|
| Full Deployment | ~5.2M gas |
| Token Deployment | ~1.2M gas |
| Governor Deployment | ~2.3M gas |
| Splitter Deployment | ~1.7M gas |
| Create Proposal | ~250K gas |
| Cast Vote | ~80K gas |
| Execute Proposal | Varies by proposal |

## Troubleshooting

### Common Issues

1. **Gas Estimation Failed**
   - Increase gas limit in network config
   - Ensure sufficient ETH balance
   - Check network congestion

2. **Invalid Distribution**
   - Verify all recipient addresses are valid
   - Check distribution amounts are reasonable
   - Ensure no duplicate recipients

3. **Deployment Verification Failed**
   - Check Etherscan API key is set
   - Verify network is supported by Etherscan
   - Wait for block confirmation before verification

4. **Time Conversion Errors**
   - Verify network block times in config
   - Check time format strings (e.g., "1 day", "2 hours")
   - Ensure realistic governance periods

### Debug Commands

```bash
# Preview deployment without broadcasting
forge script script/Deploy.s.sol:Deploy

# Verbose logging
forge script script/Deploy.s.sol:Deploy -vvv

# Estimate gas
forge script script/Deploy.s.sol:Deploy --estimate-gas

# Dry run with fork
forge script script/Deploy.s.sol:Deploy \
  --fork-url $MAINNET_RPC_URL
```

## Advanced Usage

### Custom Configuration Files

Create custom TOML files for different deployment scenarios:

```bash
# Copy default config
cp config/deployment.toml config/my-dao.toml

# Edit parameters
vim config/my-dao.toml

# Deploy with custom config
forge script script/Deploy.s.sol:Deploy \
  --sig "runWithCustomConfig(string)" "config/my-dao.toml" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
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

AGPL-3.0-or-later

## Support

For questions, issues, or feature requests:
- Open an issue in the repository
- Check existing documentation in the `README_*.md` files
- Review test files for usage examples
- Contact the development team

---

## Migration Guide

If migrating from the previous token-only system:

1. **Update Configuration**: Convert hardcoded parameters to TOML format
2. **Test Deployment**: Deploy to testnet first with new system
3. **Verify Governance**: Test proposal creation, voting, and execution
4. **Update Scripts**: Modify any existing deployment scripts

This governance stack provides a complete foundation for decentralized organizations with professional-grade deployment tools and comprehensive testing coverage.