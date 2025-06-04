// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import {LibClone} from "solady/utils/LibClone.sol";
import "./interfaces/IForwarder.sol";

/// @title ForwarderFactory
/// @author Nexum Contributors
/// @notice Abstract factory contract for deterministic deployment of Forwarder contracts using Solady's LibClone
/// @dev Uses CREATE2 to ensure the same mainnet recipient always gets the same forwarder address.
/// Concrete implementations should deploy their specific forwarder type.
abstract contract ForwarderFactory {
    using LibClone for address;

    /// @notice The immutable forwarder implementation contract address
    address public immutable implementation;

    /// @notice Event emitted when a new forwarder is deployed
    event ForwarderDeployed(
        address indexed implementation, address indexed mainnetRecipient, address indexed forwarder, bytes32 salt
    );

    /// @notice Error thrown when deployment fails
    error DeploymentFailed();

    /// @notice Constructor stores the forwarder implementation address as immutable
    /// @param _implementation The address of the forwarder implementation contract
    constructor(address _implementation) {
        require(_implementation != address(0), DeploymentFailed());
        implementation = _implementation;
    }

    /// @notice Deploy a new forwarder contract deterministically using LibClone
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return forwarder The address of the deployed forwarder contract
    function deployForwarder(address mainnetRecipient) public returns (address payable forwarder) {
        require(mainnetRecipient != address(0), "Invalid recipient");

        /// Generate deterministic salt based on mainnet recipient
        bytes32 salt = keccak256(abi.encodePacked(mainnetRecipient));

        /// Deploy using LibClone's cloneDeterministic (minimal proxy)
        forwarder = payable(LibClone.cloneDeterministic(implementation, salt));

        require(forwarder != address(0), DeploymentFailed());

        /// Initialize the deployed forwarder
        IForwarder(forwarder).initialize(mainnetRecipient);

        emit ForwarderDeployed(implementation, mainnetRecipient, forwarder, salt);
    }

    /// @notice Predict the address of a forwarder contract
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return The predicted address of the forwarder contract
    function predictForwarderAddress(address mainnetRecipient) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(mainnetRecipient));
        return LibClone.predictDeterministicAddress(implementation, salt, address(this));
    }

    /// @notice Check if a forwarder exists for the given recipient
    /// @param mainnetRecipient The mainnet address
    /// @return True if the forwarder exists (has code deployed)
    function forwarderExists(address mainnetRecipient) external view returns (bool) {
        address predicted = predictForwarderAddress(mainnetRecipient);
        return predicted.code.length > 0;
    }

    /// @notice Deploy forwarder if it doesn't exist, otherwise return existing address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return forwarder The address of the forwarder contract
    function getOrDeployForwarder(address mainnetRecipient) external returns (address payable forwarder) {
        forwarder = payable(predictForwarderAddress(mainnetRecipient));

        /// Check if forwarder already exists by checking if it has code
        if (forwarder.code.length == 0) {
            forwarder = this.deployForwarder(mainnetRecipient);
        }
    }

    /// @notice Batch deploy multiple forwarders
    /// @param mainnetRecipients Array of mainnet recipient addresses
    /// @return forwarderAddresses Array of deployed forwarder addresses
    function batchDeployForwarders(address[] calldata mainnetRecipients)
        external
        returns (address payable[] memory forwarderAddresses)
    {
        require(mainnetRecipients.length > 0, "Empty recipients array");

        forwarderAddresses = new address payable[](mainnetRecipients.length);

        for (uint256 i = 0; i < mainnetRecipients.length; i++) {
            forwarderAddresses[i] = this.deployForwarder(mainnetRecipients[i]);
        }
    }

    /// @notice Get the implementation contract address
    /// @return The implementation contract address
    function getImplementation() external view returns (address) {
        return implementation;
    }
}
