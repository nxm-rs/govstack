// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

/// @title IForwarder
/// @notice Interface for Forwarder contracts
/// @dev Used to interact with forwarder implementations in a type-safe manner
interface IForwarder {
    /// @notice Initialize the forwarder contract
    /// @param mainnetRecipient The address on mainnet that will receive forwarded tokens
    function initialize(address mainnetRecipient) external;

    /// @notice Forward all balance of a specific ERC20 token to mainnet
    /// @param token The address of the ERC20 token to forward
    function forwardToken(address token) external;

    /// @notice Forward a specific amount of ERC20 tokens to mainnet
    /// @param token The address of the ERC20 token to forward
    /// @param amount The amount of tokens to forward
    function forwardToken(address token, uint256 amount) external;

    /// @notice Forward all native token balance to mainnet
    function forwardNative() external;

    /// @notice Forward a specific amount of native tokens to mainnet
    /// @param amount The amount of native tokens to forward
    function forwardNative(uint256 amount) external;

    /// @notice Batch forward multiple ERC20 tokens
    /// @param tokens Array of token addresses to forward
    function batchForwardTokens(address[] calldata tokens) external;

    /// @notice Get the balance of a specific token
    /// @param token The token address (use address(0) for native token)
    /// @return The balance of the token
    function getBalance(address token) external view returns (uint256);

    /// @notice Get the mainnet recipient address
    /// @return The mainnet recipient address
    function mainnetRecipient() external view returns (address);

    /// @notice Check if the contract is initialized
    /// @return True if initialized
    function initialized() external view returns (bool);

    /// @notice Events
    event TokensForwarded(address indexed token, uint256 amount, address indexed recipient);
    event NativeForwarded(uint256 amount, address indexed recipient);
    event Initialized(address indexed mainnetRecipient);
}