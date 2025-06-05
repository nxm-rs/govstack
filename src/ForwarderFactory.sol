// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import {LibClone} from "solady/utils/LibClone.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
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
        address indexed implementation, address indexed mainnetRecipient, address indexed forwarder
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
    /// @param salt The salt used for deterministic deployment
    /// @return forwarder The address of the deployed forwarder contract
    function deployForwarder(address mainnetRecipient, bytes32 salt) public returns (address payable forwarder) {
        require(mainnetRecipient != address(0), "Invalid recipient");

        /// Deploy using LibClone's cloneDeterministic (minimal proxy)
        forwarder = payable(LibClone.cloneDeterministic(implementation, calculateSalt(mainnetRecipient, salt)));

        require(forwarder != address(0), DeploymentFailed());

        /// Initialize the deployed forwarder
        IForwarder(forwarder).initialize(mainnetRecipient);

        emit ForwarderDeployed(implementation, mainnetRecipient, forwarder);
    }

    /// @notice Predict the address of a forwarder contract
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @param salt The salt used for deterministic address prediction
    /// @return The predicted address of the forwarder contract
    function predictForwarderAddress(address mainnetRecipient, bytes32 salt) public view returns (address) {
        return
            LibClone.predictDeterministicAddress(implementation, calculateSalt(mainnetRecipient, salt), address(this));
    }

    /// @notice Deploy forwarder if it doesn't exist, otherwise return existing address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @param salt The salt used for deterministic address prediction
    /// @return forwarder The address of the forwarder contract
    function getOrDeployForwarder(address mainnetRecipient, bytes32 salt)
        external
        returns (address payable forwarder)
    {
        forwarder = payable(predictForwarderAddress(mainnetRecipient, salt));

        /// Check if forwarder already exists by checking if it has code
        if (forwarder.code.length == 0) {
            forwarder = deployForwarder(mainnetRecipient, salt);
        }
    }

    /// @notice Batch deploy multiple forwarders
    /// @param mainnetRecipients Array of mainnet recipient addresses
    /// @return forwarderAddresses Array of deployed forwarder addresses
    function batchDeployForwarders(address[] calldata mainnetRecipients, bytes32[] calldata salts)
        external
        returns (address payable[] memory forwarderAddresses)
    {
        require(mainnetRecipients.length == salts.length, "Mismatched arrays");

        forwarderAddresses = new address payable[](mainnetRecipients.length);

        for (uint256 i = 0; i < mainnetRecipients.length;) {
            forwarderAddresses[i] = deployForwarder(mainnetRecipients[i], salts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the implementation contract address
    /// @return The implementation contract address
    function getImplementation() external view returns (address) {
        return implementation;
    }

    /// @notice Struct to define forwarder deployment and token forwarding configuration
    struct ForwarderConfig {
        bytes32 salt;
        address[] tokens;
    }

    /// @notice Deploy multiple forwarders and immediately forward specified tokens from each
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @param configs Array of ForwarderConfig structs, each containing salt and tokens to forward
    /// @return forwarders Array of deployed forwarder addresses
    function deployAndForwardTokens(address mainnetRecipient, ForwarderConfig[] calldata configs)
        external
        returns (address payable[] memory forwarders)
    {
        forwarders = new address payable[](configs.length);

        for (uint256 i = 0; i < configs.length;) {
            ForwarderConfig calldata config = configs[i];

            // Deploy the forwarder
            address payable forwarder = deployForwarder(mainnetRecipient, config.salt);
            forwarders[i] = forwarder;

            // Forward each specified token from this forwarder
            for (uint256 j = 0; j < config.tokens.length;) {
                address token = config.tokens[j];

                if (token == address(0)) {
                    // Forward native token if it has a balance
                    if (forwarder.balance > 0) {
                        IForwarder(forwarder).forwardNative();
                    }
                } else {
                    // Forward ERC20 token if it has a balance
                    // Use try/catch to handle invalid tokens gracefully
                    try ERC20(token).balanceOf(forwarder) returns (uint256 balance) {
                        if (balance > 0) {
                            try IForwarder(forwarder).forwardToken(token) {
                                // Token forwarded successfully
                            } catch {
                                // Failed to forward token - continue with next token
                            }
                        }
                    } catch {
                        // Failed to get balance - continue with next token
                    }
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Calculate the salt used for deterministic address prediction
    /// @param mainnetRecipient The mainnet address that will receive tokens
    /// @param salt The salt used for deterministic address prediction
    /// @return The salt used for deterministic address prediction
    function calculateSalt(address mainnetRecipient, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(mainnetRecipient, salt));
    }
}
