governance/src/forwarders/README.md
```
# Token Forwarder System

A deterministic token forwarding system for bridging tokens from Gnosis Chain (and other L2s) to Ethereum mainnet, using canonical bridges and minimal proxy deployment.

## Overview

This system provides:

- **Abstract Forwarder Contract**: Defines the forwarding interface and core logic.
- **GnosisChainForwarder**: Concrete implementation for Gnosis Chain, supporting ERC20 and native token bridging.
- **ForwarderFactory**: Deterministic deployment of forwarders using CREATE2 and minimal proxies.
- **GnosisChainForwarderFactory**: Factory for GnosisChainForwarder contracts, ensuring correct deployment on Gnosis Chain.

## Gnosis Chain Implementation

### Bridge Addresses (Gnosis Chain, Chain ID: 100)

- **Omnibridge** (ERC20): `0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d`
- **xDAI Bridge** (native): `0x7301CFA0e1756B71869E93d4e4Dca5c7d0eb0AA6`
- **AMB Bridge** (messaging): `0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59`

These addresses are hardcoded in the `GnosisChainForwarder` contract.

## Key Features

- **Deterministic Deployment**: Forwarders are deployed to the same address for a given mainnet recipient.
- **Multi-Token Support**: Forward both ERC20 tokens and native xDAI.
- **Batch Operations**: Forward multiple tokens in a single transaction.
- **Emergency Recovery**: Mainnet recipient can recover stuck tokens.
- **Access Control**: Only the mainnet recipient or authorized bridge can perform sensitive operations.

## Usage

### Deploying the Factory

Deploy the factory on Gnosis Chain:

```solidity
GnosisChainForwarderFactory factory = new GnosisChainForwarderFactory();
```

### Deploying a Forwarder

```solidity
address mainnetRecipient = 0xYourMainnetRecipient;
address forwarder = factory.deployForwarder(mainnetRecipient);
```

### Forwarding Tokens

```solidity
Forwarder fwd = Forwarder(forwarder);

// Forward all balance of a specific ERC20 token
fwd.forwardToken(tokenAddress);

// Forward a specific amount
fwd.forwardToken(tokenAddress, amount);

// Forward native xDAI
fwd.forwardNative();
```

### Emergency Recovery

The mainnet recipient can recover tokens if bridging fails:

```solidity
fwd.emergencyRecover(tokenAddress, recoveryAddress);
```

## Security

- Only the mainnet recipient (or authorized bridge) can call emergency recovery or arbitrary calls.
- Only valid bridged tokens can be forwarded.
- Chain ID checks prevent deployment on the wrong network.

## Extending to Other Chains

To add a new chain, implement a new Forwarder contract with the appropriate bridge logic and deploy a corresponding factory.

## License

AGPL-3.0-or-later. See the main project [LICENCE](../../LICENCE) file.