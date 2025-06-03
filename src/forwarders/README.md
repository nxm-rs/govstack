# Token Forwarder System

A deterministic token forwarding system that allows tokens to be automatically bridged from L2 chains to Ethereum mainnet through various bridge implementations.

## Overview

The Token Forwarder system consists of:

1. **Abstract Forwarder Contract**: Base contract that defines the forwarding interface
2. **Concrete Implementations**: Chain-specific forwarder implementations (e.g., GnosisChainForwarder)
3. **ForwarderFactory**: Factory contract for deterministic deployment
4. **ForwarderProxy**: Minimal proxy for gas-efficient deployments

## Key Features

- **Deterministic Deployment**: Forwarder contracts deploy to the same address across different L2 chains when forwarding to the same mainnet recipient
- **Multi-Token Support**: Forward both ERC20 tokens and native tokens
- **Batch Operations**: Forward multiple tokens in a single transaction
- **Emergency Recovery**: Mainnet recipient can recover stuck tokens
- **Gas Efficient**: Uses minimal proxy pattern for deployments

## Architecture

### Abstract Forwarder Contract

The base `Forwarder` contract provides:
- Token forwarding functionality
- Batch operations
- Balance queries
- Abstract bridge methods that must be implemented

### Concrete Implementations

#### GnosisChainForwarder

Implements bridging for Gnosis Chain using:
- **Omnibridge** (`0x88ad09518695c6c3712AC10a214bE5109a655671`) for ERC20 tokens
- **xDAI Bridge** (`0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016`) for native tokens

### ForwarderFactory

Handles deterministic deployment using CREATE2 with:
- Salt based on mainnet recipient address
- Minimal proxy pattern for gas efficiency
- Address prediction capabilities

## Usage

### 1. Deploy Implementation and Factory

```solidity
// Deploy the implementation contract
GnosisChainForwarder implementation = new GnosisChainForwarder(address(0));

// Deploy the factory
ForwarderFactory factory = new ForwarderFactory();
```

### 2. Deploy Forwarder Instance

```solidity
address mainnetRecipient = 0x1234567890123456789012345678901234567890;
address forwarderAddress = factory.deployForwarder(
    address(implementation),
    mainnetRecipient
);
```

### 3. Forward Tokens

```solidity
Forwarder forwarder = Forwarder(forwarderAddress);

// Forward all balance of a specific token
forwarder.forwardToken(tokenAddress);

// Forward specific amount
forwarder.forwardToken(tokenAddress, amount);

// Forward native tokens
forwarder.forwardNative();

// Batch forward multiple tokens
address[] memory tokens = [token1, token2, token3];
forwarder.batchForwardTokens(tokens);
```

### 4. Predict Addresses

```solidity
// Predict forwarder address before deployment
address predictedAddress = factory.predictForwarderAddress(
    implementationAddress,
    mainnetRecipient
);
```

## Deterministic Deployment

The system ensures that the same mainnet recipient will always get the same forwarder address on any L2 chain by:

1. Using CREATE2 with a salt derived from the mainnet recipient address
2. Using identical bytecode across all deployments
3. Using the same factory deployment process

This means:
- `mainnetRecipient` → Always same `forwarderAddress` on any L2
- Users can safely send tokens to the forwarder address even before deployment
- Cross-chain address consistency

## Security Features

### Access Control
- Only initialized forwarders can forward tokens
- Emergency recovery only available to mainnet recipient

### Bridge Safety
- Validates bridge contract addresses
- Handles bridge call failures gracefully
- Includes emergency recovery mechanisms

### Validation
- Prevents zero-amount transfers
- Validates recipient addresses
- Checks sufficient balances

## Gas Optimization

- Uses Solady libraries for gas-efficient operations
- Minimal proxy pattern reduces deployment costs
- Batch operations reduce transaction costs
- Optimized for high-frequency forwarding

## Deployment Scripts

### Deploy on Gnosis Chain

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export RPC_URL=https://rpc.gnosischain.com

# Deploy implementation and factory
forge script script/DeployGnosisForwarder.s.sol:DeployGnosisForwarder --rpc-url $RPC_URL --broadcast

# Deploy specific forwarder instance
forge script script/DeployGnosisForwarder.s.sol:DeployGnosisForwarder \
  --sig "deployForwarderInstance(address,address,address)" \
  $IMPLEMENTATION_ADDRESS $FACTORY_ADDRESS $MAINNET_RECIPIENT \
  --rpc-url $RPC_URL --broadcast
```

## Testing

Run the test suite:

```bash
forge test --match-contract ForwarderTest -v
forge test --match-contract GnosisChainForwarderTest -v
```

## Adding New Chain Support

To add support for a new L2 chain:

1. Create a new forwarder contract inheriting from `Forwarder`
2. Implement the abstract `_bridgeToken` and `_bridgeNative` methods
3. Set appropriate bridge contract addresses for the chain
4. Add chain ID validation in the constructor
5. Create deployment scripts for the new chain

Example:

```solidity
contract NewChainForwarder is Forwarder {
    address constant BRIDGE_CONTRACT = 0x...;
    uint256 constant CHAIN_ID = 123;
    
    constructor(address _mainnetRecipient) Forwarder(_mainnetRecipient) {
        require(block.chainid == CHAIN_ID, "Invalid chain");
    }
    
    function _bridgeToken(address token, uint256 amount, address recipient) 
        internal override 
    {
        // Implement chain-specific token bridging
    }
    
    function _bridgeNative(uint256 amount, address recipient) 
        internal override 
    {
        // Implement chain-specific native token bridging
    }
}
```

## Bridge Contract Addresses

### Gnosis Chain (Chain ID: 100)
- **Omnibridge**: `0x88ad09518695c6c3712AC10a214bE5109a655671`
- **xDAI Bridge**: `0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016`
- **AMB Bridge**: `0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59`

## Events

```solidity
// Forwarder events
event TokensForwarded(address indexed token, uint256 amount, address indexed recipient);
event NativeForwarded(uint256 amount, address indexed recipient);
event Initialized(address indexed mainnetRecipient);

// Factory events
event ForwarderDeployed(
    address indexed implementation,
    address indexed mainnetRecipient,
    address indexed forwarder,
    bytes32 salt
);

// Gnosis-specific events
event OmnibridgeTransfer(address indexed token, uint256 amount, address indexed recipient);
event XDaiBridgeTransfer(uint256 amount, address indexed recipient);
```

## Error Handling

```solidity
error AlreadyInitialized();
error TransferFailed();
error BridgeFailed();
error ZeroAmount();
error Unauthorized();
error ForwarderAlreadyExists();
error DeploymentFailed();
error BridgeCallFailed();
error InvalidChain();
```

## License

MIT License - see LICENSE file for details.