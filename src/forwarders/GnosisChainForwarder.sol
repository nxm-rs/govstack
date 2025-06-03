// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../Forwarder.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title GnosisChainForwarder
/// @notice Concrete implementation of Forwarder for Gnosis Chain using Omnibridge/AMB
/// @dev Forwards tokens from Gnosis Chain to Ethereum mainnet via the canonical bridge
contract GnosisChainForwarder is Forwarder {
    using SafeTransferLib for address;

    /// @notice The Omnibridge contract address on Gnosis Chain
    /// @dev This is the canonical bridge for ERC20 tokens
    address public constant OMNIBRIDGE = 0x88ad09518695c6c3712AC10a214bE5109a655671;

    /// @notice The AMB (Arbitrary Message Bridge) contract address on Gnosis Chain
    /// @dev This is used for native token bridging (xDAI)
    address public constant AMB_BRIDGE = 0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59;

    /// @notice The xDAI bridge contract for native token transfers
    address public constant XDAI_BRIDGE = 0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016;

    /// @notice Gnosis Chain ID
    uint256 public constant GNOSIS_CHAIN_ID = 100;

    /// @notice Event emitted when tokens are bridged via Omnibridge
    event OmnibridgeTransfer(address indexed token, uint256 amount, address indexed recipient);

    /// @notice Event emitted when native tokens are bridged via xDAI bridge
    event XDaiBridgeTransfer(uint256 amount, address indexed recipient);

    /// @notice Error thrown when bridge contract call fails
    error BridgeCallFailed();

    /// @notice Error thrown when contract is deployed on wrong chain
    error InvalidChain();

    /// @notice Initialize the Gnosis Chain forwarder
    /// @param _mainnetRecipient The address on mainnet that will receive forwarded tokens
    function initialize(address _mainnetRecipient) external override {
        // Verify we're on Gnosis Chain
        if (block.chainid != GNOSIS_CHAIN_ID) revert InvalidChain();
        
        // Check if already initialized
        if (initialized) revert AlreadyInitialized();
        require(_mainnetRecipient != address(0), "Invalid recipient");
        
        // Set state variables
        mainnetRecipient = _mainnetRecipient;
        initialized = true;
        
        emit Initialized(_mainnetRecipient);
    }

    /// @notice Bridge ERC20 tokens to mainnet via Omnibridge
    /// @dev Implements the abstract _bridgeToken function
    /// @param token The token address to bridge
    /// @param amount The amount to bridge
    /// @param recipient The recipient address on mainnet
    function _bridgeToken(address token, uint256 amount, address recipient) internal override {
        // Transfer tokens to this contract if not already here
        uint256 balanceBefore = ERC20(token).balanceOf(address(this));
        if (balanceBefore < amount) {
            revert TransferFailed();
        }

        // Approve Omnibridge to spend tokens
        token.safeApprove(OMNIBRIDGE, amount);

        // Bridge tokens via Omnibridge
        // The Omnibridge relayTokens function signature: relayTokens(address token, address receiver, uint256 value)
        (bool success, ) = OMNIBRIDGE.call(
            abi.encodeWithSignature("relayTokens(address,address,uint256)", token, recipient, amount)
        );

        if (!success) {
            // Reset approval on failure
            token.safeApprove(OMNIBRIDGE, 0);
            revert BridgeCallFailed();
        }

        emit OmnibridgeTransfer(token, amount, recipient);
    }

    /// @notice Bridge native tokens (xDAI) to mainnet
    /// @dev Implements the abstract _bridgeNative function
    /// @param amount The amount to bridge
    /// @param recipient The recipient address on mainnet
    function _bridgeNative(uint256 amount, address recipient) internal override {
        // Bridge native tokens via xDAI bridge
        // The xDAI bridge relayTokens function for native tokens
        (bool success, ) = XDAI_BRIDGE.call{value: amount}(
            abi.encodeWithSignature("relayTokens(address)", recipient)
        );

        if (!success) revert BridgeCallFailed();

        emit XDaiBridgeTransfer(amount, recipient);
    }

    /// @notice Get the current chain ID for verification
    /// @return The current chain ID
    function getChainId() external view returns (uint256) {
        return block.chainid;
    }

    /// @notice Check if Omnibridge is properly configured
    /// @return True if bridge addresses are set
    function isBridgeConfigured() external pure returns (bool) {
        return OMNIBRIDGE != address(0) && XDAI_BRIDGE != address(0);
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
}