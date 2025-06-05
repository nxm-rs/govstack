// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "../../ForwarderFactory.sol";
import "./GnosisForwarder.sol";

/// @title GnosisForwarderFactory
/// @author Nexum Contributors
/// @notice Factory contract for deploying GnosisForwarder contracts
/// @dev Inherits from ForwarderFactory and deploys GnosisForwarder implementation
contract GnosisForwarderFactory is ForwarderFactory {
    /// @notice Gnosis Chain ID
    uint256 public constant GNOSIS_CHAIN_ID = 100;

    /// @notice Constructor deploys the GnosisForwarder implementation
    constructor() ForwarderFactory(address(new GnosisForwarder())) {
        // Verify we're on Gnosis Chain
        require(block.chainid == GNOSIS_CHAIN_ID, Forwarder.InvalidChain());
    }
}
