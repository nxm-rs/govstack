// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibClone} from "solady/utils/LibClone.sol";

/// @title Forwarder
/// @author Nexum Contributors
/// @notice Abstract contract for forwarding tokens from L2 to mainnet through bridges
/// @dev This contract is designed to be deterministically deployed to the same address
///      on any L2 chain when forwarding to the same mainnet address
abstract contract Forwarder {
    using SafeTransferLib for address;

    /// @notice The mainnet address that will receive all forwarded tokens
    address public mainnetRecipient;

    /// @notice The chain ID of the destination chain (mainnet)
    uint256 public constant DESTINATION_CHAIN_ID = 1;

    /// @notice Whether the contract has been initialized
    bool public initialized;

    /// @notice Emitted when ERC20 tokens are forwarded
    event TokensForwarded(address indexed token, uint256 amount, address indexed recipient);

    /// @notice Emitted when native tokens are forwarded
    event NativeForwarded(uint256 amount, address indexed recipient);

    /// @notice Emitted when the contract is initialized
    event Initialized(address indexed mainnetRecipient);

    /// @notice Error thrown when contract is already initialized
    error AlreadyInitialized();

    /// @notice Error thrown when token transfer fails
    error TransferFailed();

    /// @notice Error thrown when bridging fails
    error BridgeFailed();

    /// @notice Error thrown when trying to forward zero amount
    error ZeroAmount();

    /// @notice Error thrown when caller is not authorized
    error Unauthorized();

    /// @notice Error thrown when contract is deployed on wrong chain
    error InvalidChain();

    /// @notice Initialize the forwarder contract
    /// @param _mainnetRecipient The address on mainnet that will receive forwarded tokens
    function initialize(address _mainnetRecipient) external virtual {
        require(!initialized, AlreadyInitialized());
        require(_mainnetRecipient != address(0), "Invalid recipient");

        mainnetRecipient = _mainnetRecipient;
        initialized = true;

        emit Initialized(_mainnetRecipient);
    }

    /// @notice Modifier to ensure contract is initialized
    modifier onlyInitialized() {
        require(initialized, "Not initialized");
        _;
    }

    /// @notice Forward all balance of a specific ERC20 token to mainnet
    /// @param token The address of the ERC20 token to forward
    function forwardToken(address token) external onlyInitialized {
        uint256 balance = ERC20(token).balanceOf(address(this));
        require(balance > 0, ZeroAmount());

        _bridgeToken(token, balance, mainnetRecipient);

        emit TokensForwarded(token, balance, mainnetRecipient);
    }

    /// @notice Forward a specific amount of ERC20 tokens to mainnet
    /// @param token The address of the ERC20 token to forward
    /// @param amount The amount of tokens to forward
    function forwardToken(address token, uint256 amount) external onlyInitialized {
        require(amount > 0, ZeroAmount());

        uint256 balance = ERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        _bridgeToken(token, amount, mainnetRecipient);

        emit TokensForwarded(token, amount, mainnetRecipient);
    }

    /// @notice Forward all native token balance to mainnet
    function forwardNative() external onlyInitialized {
        uint256 balance = address(this).balance;
        require(balance > 0, ZeroAmount());

        _bridgeNative(balance, mainnetRecipient);

        emit NativeForwarded(balance, mainnetRecipient);
    }

    /// @notice Forward a specific amount of native tokens to mainnet
    /// @param amount The amount of native tokens to forward
    function forwardNative(uint256 amount) external onlyInitialized {
        require(amount > 0, ZeroAmount());
        require(address(this).balance >= amount, "Insufficient balance");

        _bridgeNative(amount, mainnetRecipient);

        emit NativeForwarded(amount, mainnetRecipient);
    }

    /// @notice Batch forward multiple ERC20 tokens
    /// @param tokens Array of token addresses to forward
    function batchForwardTokens(address[] calldata tokens) external onlyInitialized {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = ERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                _bridgeToken(tokens[i], balance, mainnetRecipient);
                emit TokensForwarded(tokens[i], balance, mainnetRecipient);
            }
        }
    }

    /// @notice Get the balance of a specific token
    /// @param token The token address (use address(0) for native token)
    /// @return The balance of the token
    function getBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return ERC20(token).balanceOf(address(this));
    }

    /// @notice Emergency function to recover tokens if bridge fails
    /// @dev Only callable by the mainnet recipient (acts as admin)
    /// @param token The token to recover
    /// @param to The address to send recovered tokens to
    function emergencyRecover(address token, address to) external onlyInitialized {
        require(msg.sender == mainnetRecipient, "Only recipient can recover");
        require(to != address(0), "Invalid recovery address");

        if (token == address(0)) {
            // Recover native tokens
            uint256 balance = address(this).balance;
            if (balance > 0) {
                to.safeTransferETH(balance);
            }
        } else {
            // Recover ERC20 tokens
            uint256 balance = ERC20(token).balanceOf(address(this));
            if (balance > 0) {
                token.safeTransfer(to, balance);
            }
        }
    }

    /// @notice Abstract function to bridge ERC20 tokens to mainnet
    /// @dev Must be implemented by concrete forwarder contracts
    /// @param token The token address to bridge
    /// @param amount The amount to bridge
    /// @param recipient The recipient address on mainnet
    function _bridgeToken(address token, uint256 amount, address recipient) internal virtual;

    /// @notice Abstract function to bridge native tokens to mainnet
    /// @dev Must be implemented by concrete forwarder contracts
    /// @param amount The amount to bridge
    /// @param recipient The recipient address on mainnet
    function _bridgeNative(uint256 amount, address recipient) internal virtual;

    /// @notice Allow contract to receive native tokens
    receive() external payable {}

    /// @notice Fallback function to handle any other calls
    fallback() external payable {}
}
