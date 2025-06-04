// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "../../Forwarder.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IOmnibridge, IxDaiBridge, IBridgedToken, IAMBBridge} from "./interfaces/IGnosisBridges.sol";

/// @title GnosisChainForwarder
/// @notice Concrete implementation of Forwarder for Gnosis Chain using Omnibridge/AMB
/// @dev Forwards tokens from Gnosis Chain to Ethereum mainnet via the canonical bridge
contract GnosisChainForwarder is Forwarder {
    using SafeTransferLib for address;

    /// @notice The Omnibridge contract address on Gnosis Chain
    /// @dev This is the canonical bridge for ERC20 tokens
    IOmnibridge public constant OMNIBRIDGE = IOmnibridge(0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d);

    /// @notice The xDAI bridge contract address on Gnosis Chain
    /// @dev This is used for native token bridging (xDAI)
    IxDaiBridge public constant XDAI_BRIDGE = IxDaiBridge(0x7301CFA0e1756B71869E93d4e4Dca5c7d0eb0AA6);

    /// @notice The AMB bridge contract on Gnosis Chain
    IAMBBridge public constant AMB_BRIDGE = IAMBBridge(0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59);

    /// @notice Gnosis Chain ID
    uint256 public constant GNOSIS_CHAIN_ID = 100;

    /// @notice Error thrown when token is not a valid bridged token
    error InvalidToken();
    /// @notice Unauthorized sender
    error UnauthorizedSender();

    /// @notice Initialize the Gnosis Chain forwarder
    /// @param _mainnetRecipient The address on mainnet that will receive forwarded tokens
    function initialize(address _mainnetRecipient) external override {
        // Verify we're on Gnosis Chain
        require(block.chainid == GNOSIS_CHAIN_ID, InvalidChain());

        // Check if already initialized
        require(!initialized, AlreadyInitialized());
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
        // Validate that the token is a legitimate bridged token
        require(_isValidBridgedToken(token), InvalidToken());

        // Transfer tokens to this contract if not already here
        uint256 balanceBefore = ERC20(token).balanceOf(address(this));
        require(balanceBefore >= amount, TransferFailed());

        // Approve Omnibridge to spend tokens
        token.safeApprove(address(OMNIBRIDGE), amount);

        // Bridge tokens via Omnibridge using relayTokens
        OMNIBRIDGE.relayTokens(token, recipient, amount);
    }

    /// @notice Bridge native tokens (xDAI) to mainnet
    /// @dev Implements the abstract _bridgeNative function
    /// @param amount The amount to bridge
    /// @param recipient The recipient address on mainnet
    function _bridgeNative(uint256 amount, address recipient) internal override {
        // Bridge native tokens via xDAI bridge using relayTokens
        XDAI_BRIDGE.relayTokens{value: amount}(recipient);
    }

    /// @notice Check if a token is a valid bridged token that can be forwarded
    /// @dev A token is valid if it's a bridged token with the correct bridge contract
    /// @param token The token address to validate
    /// @return True if the token is valid for bridging
    function _isValidBridgedToken(address token) internal view returns (bool) {
        // Try to call the bridged token interface functions
        try IBridgedToken(token).isBridge(address(OMNIBRIDGE)) returns (bool isBridgeToken) {
            if (!isBridgeToken) {
                return false;
            }

            // Check if the bridge contract is the correct Omnibridge
            try IBridgedToken(token).bridgeContract() returns (address bridgeContract) {
                return bridgeContract == address(OMNIBRIDGE);
            } catch {
                return false;
            }
        } catch {
            // If the token doesn't implement the bridged token interface,
            // check if it has a foreign token mapping (indicating it's bridged)
            try OMNIBRIDGE.foreignTokenAddress(token) returns (address foreignToken) {
                return foreignToken != address(0);
            } catch {
                return false;
            }
        }
    }

    /// @notice Check if a token is valid for bridging (external view function)
    /// @param token The token address to validate
    /// @return True if the token is valid for bridging
    function isValidToken(address token) external view returns (bool) {
        return _isValidBridgedToken(token);
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

    /// @notice Allow arbitrary calls to be made by authorized senders.
    function arbitraryCall(address sender, uint256 value, bytes calldata callData) external onlyInitialized {
        if (
            msg.sender == mainnetRecipient
                || (
                    msg.sender == address(AMB_BRIDGE) && AMB_BRIDGE.messageSender() == mainnetRecipient
                        && AMB_BRIDGE.messageSourceChainId() == 1
                )
        ) {
            (bool success, bytes memory returnData) = sender.call{value: value}(callData);
            if (!success) {
                // bubble up the revert
                assembly ("memory-safe") {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        } else {
            revert UnauthorizedSender();
        }
    }
}
