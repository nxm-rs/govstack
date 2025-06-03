// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LibClone} from "solady/utils/LibClone.sol";
import "./Forwarder.sol";

/// @title ForwarderFactory
/// @notice Factory contract for deterministic deployment of Forwarder contracts using Solady's LibClone
/// @dev Uses CREATE2 to ensure the same mainnet recipient always gets the same forwarder address
contract ForwarderFactory {
    using LibClone for address;

    /// @notice Mapping to track deployed forwarders
    mapping(address => mapping(address => address)) public forwarders;

    /// @notice Event emitted when a new forwarder is deployed
    event ForwarderDeployed(
        address indexed implementation, address indexed mainnetRecipient, address indexed forwarder, bytes32 salt
    );

    /// @notice Error thrown when forwarder already exists
    error ForwarderAlreadyExists();

    /// @notice Error thrown when deployment fails
    error DeploymentFailed();

    /// @notice Deploy a new forwarder contract deterministically using LibClone
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return forwarder The address of the deployed forwarder contract
    function deployForwarder(address implementation, address mainnetRecipient)
        external
        returns (address payable forwarder)
    {
        require(implementation != address(0), "Invalid implementation");
        require(mainnetRecipient != address(0), "Invalid recipient");

        // Check if forwarder already exists
        if (forwarders[implementation][mainnetRecipient] != address(0)) {
            revert ForwarderAlreadyExists();
        }

        // Generate deterministic salt based on mainnet recipient
        bytes32 salt = keccak256(abi.encodePacked(mainnetRecipient));

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSignature("initialize(address)", mainnetRecipient);

        // Deploy using LibClone's cloneDeterministic with immutable args
        forwarder = payable(LibClone.cloneDeterministic(implementation, initData, salt));

        if (forwarder == address(0)) revert DeploymentFailed();

        // Initialize the deployed forwarder
        Forwarder(forwarder).initialize(mainnetRecipient);

        // Store the deployed forwarder
        forwarders[implementation][mainnetRecipient] = forwarder;

        emit ForwarderDeployed(implementation, mainnetRecipient, forwarder, salt);
    }

    /// @notice Predict the address of a forwarder contract
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return The predicted address of the forwarder contract
    function predictForwarderAddress(address implementation, address mainnetRecipient)
        external
        view
        returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(mainnetRecipient));
        bytes memory initData = abi.encodeWithSignature("initialize(address)", mainnetRecipient);

        return LibClone.predictDeterministicAddress(implementation, initData, salt, address(this));
    }

    /// @notice Get the deployed forwarder address for a given implementation and recipient
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address
    /// @return The forwarder address, or address(0) if not deployed
    function getForwarder(address implementation, address mainnetRecipient) external view returns (address) {
        return forwarders[implementation][mainnetRecipient];
    }

    /// @notice Check if a forwarder exists for the given parameters
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address
    /// @return True if the forwarder exists
    function forwarderExists(address implementation, address mainnetRecipient) external view returns (bool) {
        return forwarders[implementation][mainnetRecipient] != address(0);
    }

    /// @notice Deploy forwarder if it doesn't exist, otherwise return existing address
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return forwarder The address of the forwarder contract
    function getOrDeployForwarder(address implementation, address mainnetRecipient)
        external
        returns (address payable forwarder)
    {
        forwarder = payable(forwarders[implementation][mainnetRecipient]);

        if (forwarder == address(0)) {
            forwarder = this.deployForwarder(implementation, mainnetRecipient);
        }
    }

    /// @notice Batch deploy multiple forwarders
    /// @param implementations Array of implementation addresses
    /// @param mainnetRecipients Array of mainnet recipient addresses
    /// @return forwarderAddresses Array of deployed forwarder addresses
    function batchDeployForwarders(address[] calldata implementations, address[] calldata mainnetRecipients)
        external
        returns (address payable[] memory forwarderAddresses)
    {
        require(implementations.length == mainnetRecipients.length, "Array length mismatch");

        forwarderAddresses = new address payable[](implementations.length);

        for (uint256 i = 0; i < implementations.length; i++) {
            forwarderAddresses[i] = this.deployForwarder(implementations[i], mainnetRecipients[i]);
        }
    }

    /// @notice Deploy forwarder using CREATE2 directly (alternative method)
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return forwarder The address of the deployed forwarder contract
    function deployForwarderDirect(address implementation, address mainnetRecipient)
        external
        returns (address payable forwarder)
    {
        require(implementation != address(0), "Invalid implementation");
        require(mainnetRecipient != address(0), "Invalid recipient");

        // Check if forwarder already exists
        if (forwarders[implementation][mainnetRecipient] != address(0)) {
            revert ForwarderAlreadyExists();
        }

        // Generate deterministic salt based on mainnet recipient
        bytes32 salt = keccak256(abi.encodePacked(mainnetRecipient));

        // Deploy using LibClone's cloneDeterministic (simple clone)
        forwarder = payable(LibClone.cloneDeterministic(implementation, salt));

        if (forwarder == address(0)) revert DeploymentFailed();

        // Initialize the deployed forwarder
        Forwarder(forwarder).initialize(mainnetRecipient);

        // Store the deployed forwarder
        forwarders[implementation][mainnetRecipient] = forwarder;

        emit ForwarderDeployed(implementation, mainnetRecipient, forwarder, salt);
    }

    /// @notice Predict the address of a forwarder contract (direct method)
    /// @param implementation The forwarder implementation contract address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @return The predicted address of the forwarder contract
    function predictForwarderAddressDirect(address implementation, address mainnetRecipient)
        external
        view
        returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(mainnetRecipient));

        return LibClone.predictDeterministicAddress(implementation, salt, address(this));
    }
}
