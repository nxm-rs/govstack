// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

/// @title IOmnibridge
/// @notice Interface for the Omnibridge contract on Gnosis Chain
/// @dev Used for bridging ERC20 tokens between Gnosis Chain and Ethereum mainnet
interface IOmnibridge {
    /// @notice Bridge ERC20 tokens to the other chain
    /// @param token The token contract address
    /// @param receiver The recipient address on the destination chain
    /// @param value The amount of tokens to bridge
    function relayTokens(address token, address receiver, uint256 value) external;

    /// @notice Get the corresponding token address on the other chain
    /// @param token The token address on the current chain
    /// @return The corresponding token address on the other chain
    function foreignTokenAddress(address token) external view returns (address);

    /// @notice Get the corresponding token address on the home chain
    /// @param token The token address on the foreign chain
    /// @return The corresponding token address on the home chain
    function homeTokenAddress(address token) external view returns (address);
}

/// @title IxDaiBridge
/// @notice Interface for the xDAI bridge contract on Gnosis Chain
/// @dev Used for bridging native tokens (xDAI) between Gnosis Chain and Ethereum mainnet
interface IxDaiBridge {
    /// @notice Bridge native tokens to mainnet
    /// @param receiver The recipient address on mainnet
    function relayTokens(address receiver) external payable;

    /// @notice Get the minimum amount required for bridging
    /// @return The minimum bridge amount
    function minPerTx() external view returns (uint256);

    /// @notice Get the maximum amount allowed for bridging
    /// @return The maximum bridge amount
    function maxPerTx() external view returns (uint256);
}

/// @title IBridgedToken
/// @notice Interface for ERC677 bridged tokens on Gnosis Chain (Permittable tokens)
/// @dev Used to validate that tokens are legitimate bridged tokens
interface IBridgedToken {
    /// @notice Check if the given address is a bridge contract for this token
    /// @param _address The address to check
    /// @return True if the address is a bridge for this token
    function isBridge(address _address) external view returns (bool);

    /// @notice Get the bridge contract address that manages this token
    /// @return The address of the bridge contract
    function bridgeContract() external view returns (address);

    /// @notice Transfer tokens and call a function on the receiver
    /// @param _to The recipient address
    /// @param _value The amount to transfer
    /// @param _data Additional data to pass to the receiver
    /// @return True if successful
    function transferAndCall(address _to, uint256 _value, bytes calldata _data) external returns (bool);

    /// @notice Standard ERC20 functions
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
    function allowance(address _owner, address _spender) external view returns (uint256);
}

interface IAMBBridge {
    /// @notice Foreign chain message sender.
    function messageSender() external view returns (address);
}
