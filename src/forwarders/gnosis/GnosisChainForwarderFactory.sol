// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "../../ForwarderFactory.sol";
import "./GnosisChainForwarder.sol";

/// @title GnosisChainForwarderFactory
/// @notice Factory contract for deploying GnosisChainForwarder contracts
/// @dev Inherits from ForwarderFactory and deploys GnosisChainForwarder implementation
contract GnosisChainForwarderFactory is ForwarderFactory {
    /// @notice Gnosis Chain ID
    uint256 public constant GNOSIS_CHAIN_ID = 100;

    /// @notice Constructor deploys the GnosisChainForwarder implementation
    constructor() ForwarderFactory(address(new GnosisChainForwarder())) {
        // Verify we're on Gnosis Chain
        require(block.chainid == GNOSIS_CHAIN_ID, Forwarder.InvalidChain());
    }


}