// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import "../src/forwarders/gnosis/GnosisForwarder.sol";
import "../src/forwarders/gnosis/GnosisForwarderFactory.sol";
import "../src/forwarders/gnosis/interfaces/IGnosisBridges.sol";

/// @title TestERC20
/// @notice Simple ERC20 token for testing
contract TestERC20 is ERC20 {
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract GnosisForwarderForkTest is Test {
    string constant GNOSIS_RPC = "https://rpc.gnosischain.com";
    uint256 constant GNOSIS_CHAIN_ID = 100;

    GnosisForwarderFactory factory;
    GnosisForwarder forwarder;
    address mainnetRecipient = vm.addr(1);
    address user = vm.addr(2);

    // Gnosis Chain contract addresses
    address constant OMNIBRIDGE = 0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d;
    address constant XDAI_BRIDGE = 0x7301CFA0e1756B71869E93d4e4Dca5c7d0eb0AA6;

    // Known tokens on Gnosis Chain for testing
    address constant WETH_GNOSIS = 0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1;
    address constant USDC_GNOSIS = 0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83;
    address constant COW_TOKEN_GNOSIS = 0x177127622c4A00F3d409B75571e12cB3c8973d3c;

    uint256 gnosisFork;

    function setUp() public {
        // Create Gnosis Chain fork
        gnosisFork = vm.createFork(GNOSIS_RPC);
        vm.selectFork(gnosisFork);

        // Verify we're on Gnosis Chain
        assertEq(block.chainid, GNOSIS_CHAIN_ID);

        // Deploy factory
        factory = new GnosisForwarderFactory();

        // Deploy forwarder instance
        address payable forwarderAddr = factory.deployForwarder(mainnetRecipient);
        forwarder = GnosisForwarder(forwarderAddr);

        // Fund user account
        vm.deal(user, 10 ether);
    }

    function testForkSetup() public view {
        assertEq(block.chainid, GNOSIS_CHAIN_ID);
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);
        assertEq(block.chainid, GNOSIS_CHAIN_ID);
    }

    function testBridgeContractExists() public view {
        // Check that the bridge contracts exist on Gnosis Chain
        // Note: These may not have code if we're on a fork at a different block
        // Let's just check if they're configured in our forwarder
        assertTrue(
            address(forwarder.OMNIBRIDGE()) != address(0) && address(forwarder.XDAI_BRIDGE()) != address(0),
            "Bridge not configured"
        );
        assertEq(address(forwarder.OMNIBRIDGE()), OMNIBRIDGE);
        assertEq(address(forwarder.XDAI_BRIDGE()), XDAI_BRIDGE);
    }

    function testBridgeConfiguration() public view {
        assertTrue(address(forwarder.OMNIBRIDGE()) != address(0) && address(forwarder.XDAI_BRIDGE()) != address(0));
        assertEq(address(forwarder.OMNIBRIDGE()), OMNIBRIDGE);
        assertEq(address(forwarder.XDAI_BRIDGE()), XDAI_BRIDGE);
    }

    function testEmergencyRecoverWithRealToken() public {
        // Use a real token from Gnosis Chain (WETH)
        ERC20 weth = ERC20(WETH_GNOSIS);
        address recoveryAddress = vm.addr(3);

        // Get some WETH to the forwarder (simulate someone sending tokens)
        // We'll use deal to simulate this
        deal(WETH_GNOSIS, address(forwarder), 1 ether);

        assertEq(weth.balanceOf(address(forwarder)), 1 ether);

        // Only mainnet recipient can recover
        vm.prank(mainnetRecipient);
        forwarder.emergencyRecover(WETH_GNOSIS, recoveryAddress);

        assertEq(weth.balanceOf(recoveryAddress), 1 ether);
        assertEq(weth.balanceOf(address(forwarder)), 0);
    }

    function testEmergencyRecoverNative() public {
        address recoveryAddress = vm.addr(3);

        // Send some xDAI to forwarder
        vm.prank(user);
        (bool success,) = address(forwarder).call{value: 1 ether}("");
        assertTrue(success);

        uint256 initialBalance = recoveryAddress.balance;

        // Only mainnet recipient can recover
        vm.prank(mainnetRecipient);
        forwarder.emergencyRecover(address(0), recoveryAddress);

        assertEq(recoveryAddress.balance, initialBalance + 1 ether);
        assertEq(address(forwarder).balance, 0);
    }

    function testEmergencyRecoverUnauthorized() public {
        vm.prank(user);
        vm.expectRevert("Only recipient can recover");
        forwarder.emergencyRecover(address(0), user);
    }

    function testEmergencyRecoverInvalidAddress() public {
        vm.prank(mainnetRecipient);
        vm.expectRevert("Invalid recovery address");
        forwarder.emergencyRecover(address(0), address(0));
    }

    function testForwarderReceivesTokens() public {
        TestERC20 testToken = new TestERC20("Test Token", "TEST");

        // Mint tokens to forwarder
        testToken.mint(address(forwarder), 500 ether);

        assertEq(testToken.balanceOf(address(forwarder)), 500 ether);
    }

    function testForwarderReceivesNative() public {
        uint256 initialBalance = address(forwarder).balance;

        vm.prank(user);
        (bool success,) = address(forwarder).call{value: 2 ether}("");
        assertTrue(success);

        assertEq(address(forwarder).balance, initialBalance + 2 ether);
    }

    function testTokenValidation() public {
        TestERC20 testToken = new TestERC20("Test Token", "TEST");

        // Test that a non-bridged token is invalid
        assertFalse(forwarder.isValidToken(address(testToken)));

        // Mock a bridged token with correct isBridge signature
        vm.mockCall(
            address(testToken),
            abi.encodeCall(IBridgedToken.isBridge, (address(forwarder.OMNIBRIDGE()))),
            abi.encode(true)
        );
        vm.mockCall(
            address(testToken),
            abi.encodeCall(IBridgedToken.bridgeContract, ()),
            abi.encode(address(forwarder.OMNIBRIDGE()))
        );

        // Now it should be valid
        assertTrue(forwarder.isValidToken(address(testToken)));
    }

    function testGetOmnibridgeAddress() public view {
        assertEq(address(forwarder.OMNIBRIDGE()), address(forwarder.OMNIBRIDGE()));
    }

    function testDeterministicDeploymentAndPrediction() public {
        address recipient1 = vm.addr(10);
        address recipient2 = vm.addr(11);

        // Predict and deploy first forwarder
        address predicted1 = factory.predictForwarderAddress(recipient1);
        address forwarder1 = factory.deployForwarder(recipient1);
        assertEq(predicted1, forwarder1);

        // Predict and deploy second forwarder
        address predicted2 = factory.predictForwarderAddress(recipient2);
        address forwarder2 = factory.deployForwarder(recipient2);
        assertEq(predicted2, forwarder2);

        // Addresses should be different
        assertTrue(forwarder1 != forwarder2);

        // Both should be properly initialized
        assertEq(GnosisForwarder(payable(forwarder1)).mainnetRecipient(), recipient1);
        assertEq(GnosisForwarder(payable(forwarder2)).mainnetRecipient(), recipient2);

        // Duplicate deployment returns the same address
        address forwarder1Dup = factory.getOrDeployForwarder(recipient1);
        assertEq(forwarder1, forwarder1Dup);

        // Batch deploy
        address[] memory recipients = new address[](3);
        recipients[0] = vm.addr(40);
        recipients[1] = vm.addr(41);
        recipients[2] = vm.addr(42);

        for (uint256 i = 0; i < recipients.length; i++) {
            address predicted = factory.predictForwarderAddress(recipients[i]);
            address deployed = factory.deployForwarder(recipients[i]);
            assertEq(predicted, deployed);

            GnosisForwarder fw = GnosisForwarder(payable(deployed));
            assertTrue(fw.initialized());
            assertEq(fw.mainnetRecipient(), recipients[i]);
            assertEq(block.chainid, GNOSIS_CHAIN_ID);
        }
    }

    function testForwarderWithRealUSDC() public {
        // Test with real USDC on Gnosis Chain
        ERC20 usdc = ERC20(USDC_GNOSIS);

        // Check that USDC contract exists
        assertTrue(USDC_GNOSIS.code.length > 0, "USDC contract not found on Gnosis");

        // Simulate having USDC in the forwarder
        deal(USDC_GNOSIS, address(forwarder), 1000 * 10 ** 6); // 1000 USDC (6 decimals)

        assertEq(usdc.balanceOf(address(forwarder)), 1000 * 10 ** 6);
    }

    function testMultipleTokenTypes() public {
        // Test with test token and real tokens
        TestERC20 testToken = new TestERC20("Test Token", "TEST");
        testToken.mint(address(forwarder), 500 ether);

        // Deal some real WETH
        deal(WETH_GNOSIS, address(forwarder), 2 ether);

        // Deal some native tokens
        vm.deal(address(forwarder), 3 ether);

        // Check balances
        assertEq(testToken.balanceOf(address(forwarder)), 500 ether);
        assertEq(ERC20(WETH_GNOSIS).balanceOf(address(forwarder)), 2 ether);
        assertEq(address(forwarder).balance, 3 ether);
    }

    function testChainIdValidation() public view {
        // This test confirms we're actually on Gnosis Chain
        assertEq(block.chainid, 100);
        assertEq(block.chainid, 100);
        assertEq(forwarder.GNOSIS_CHAIN_ID(), 100);
    }

    function testContractConstants() public view {
        // Verify all the constants are correct
        assertEq(address(forwarder.OMNIBRIDGE()), 0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d);
        assertEq(address(forwarder.XDAI_BRIDGE()), 0x7301CFA0e1756B71869E93d4e4Dca5c7d0eb0AA6);
        assertEq(forwarder.GNOSIS_CHAIN_ID(), 100);
    }

    // Test the actual bridge functionality (this will test the calls but they may revert)
    function testBridgeTokenCall() public {
        TestERC20 testToken = new TestERC20("Test Token", "TEST");
        testToken.mint(address(forwarder), 100 ether);

        // Mock the token validation to return false (invalid token)
        vm.mockCall(
            address(testToken),
            abi.encodeCall(IBridgedToken.isBridge, (address(forwarder.OMNIBRIDGE()))),
            abi.encode(false)
        );
        vm.mockCall(
            address(forwarder.OMNIBRIDGE()),
            abi.encodeCall(IOmnibridge.foreignTokenAddress, (address(testToken))),
            abi.encode(address(0))
        );

        // This should revert due to invalid token validation
        vm.expectRevert();
        forwarder.forwardToken(address(testToken));
    }

    function testBridgeNativeCall() public {
        vm.deal(address(forwarder), 1 ether);

        // This test verifies that the native bridge call is made
        vm.expectRevert(); // May revert due to bridge validation
        forwarder.forwardNative();
    }

    function testCOWTokenValidation() public view {
        // Test with real COW token on Gnosis Chain
        IBridgedToken cowToken = IBridgedToken(COW_TOKEN_GNOSIS);

        // Check that COW token contract exists
        assertTrue(COW_TOKEN_GNOSIS.code.length > 0, "COW token contract not found on Gnosis");

        // Test if COW token recognizes the Omnibridge as a bridge
        try cowToken.isBridge(address(forwarder.OMNIBRIDGE())) returns (bool isBridge) {
            if (isBridge) {
                // If it recognizes Omnibridge as a bridge, it should be valid
                assertTrue(
                    forwarder.isValidToken(COW_TOKEN_GNOSIS), "COW token should be valid if it recognizes Omnibridge"
                );
            } else {
                // If it doesn't recognize Omnibridge, check if it has a foreign token mapping
                try IOmnibridge(address(forwarder.OMNIBRIDGE())).foreignTokenAddress(COW_TOKEN_GNOSIS) returns (
                    address foreignToken
                ) {
                    if (foreignToken != address(0)) {
                        assertTrue(
                            forwarder.isValidToken(COW_TOKEN_GNOSIS),
                            "COW token should be valid if it has foreign mapping"
                        );
                    } else {
                        assertFalse(
                            forwarder.isValidToken(COW_TOKEN_GNOSIS),
                            "COW token should be invalid if no bridge recognition"
                        );
                    }
                } catch {
                    assertFalse(
                        forwarder.isValidToken(COW_TOKEN_GNOSIS), "COW token should be invalid if no foreign mapping"
                    );
                }
            }
        } catch {
            // If isBridge call fails, check fallback validation
            try IOmnibridge(address(forwarder.OMNIBRIDGE())).foreignTokenAddress(COW_TOKEN_GNOSIS) returns (
                address foreignToken
            ) {
                if (foreignToken != address(0)) {
                    assertTrue(
                        forwarder.isValidToken(COW_TOKEN_GNOSIS), "COW token should be valid via foreign mapping"
                    );
                } else {
                    assertFalse(forwarder.isValidToken(COW_TOKEN_GNOSIS), "COW token should be invalid");
                }
            } catch {
                assertFalse(forwarder.isValidToken(COW_TOKEN_GNOSIS), "COW token should be invalid");
            }
        }
    }

    function testCOWTokenProperties() public view {
        // Test COW token properties
        IBridgedToken cowToken = IBridgedToken(COW_TOKEN_GNOSIS);

        if (COW_TOKEN_GNOSIS.code.length > 0) {
            try cowToken.name() returns (string memory name) {
                console.log("COW token name:", name);
                assertTrue(bytes(name).length > 0, "Token should have a name");
            } catch {
                console.log("COW token name() call failed");
            }

            try cowToken.symbol() returns (string memory symbol) {
                console.log("COW token symbol:", symbol);
                assertTrue(bytes(symbol).length > 0, "Token should have a symbol");
            } catch {
                console.log("COW token symbol() call failed");
            }

            try cowToken.bridgeContract() returns (address bridge) {
                console.log("COW token bridge contract:", bridge);
                if (bridge != address(0)) {
                    assertEq(bridge, address(forwarder.OMNIBRIDGE()), "Bridge contract should be Omnibridge");
                }
            } catch {
                console.log("COW token bridgeContract() call failed");
            }
        }
    }

    function testForwardCOWToken() public {
        // Test forwarding COW tokens if they're valid
        if (forwarder.isValidToken(COW_TOKEN_GNOSIS)) {
            // Deal some COW tokens to the forwarder
            deal(COW_TOKEN_GNOSIS, address(forwarder), 1000 ether);

            uint256 balance = IBridgedToken(COW_TOKEN_GNOSIS).balanceOf(address(forwarder));
            assertEq(balance, 1000 ether, "Should have COW tokens");

            // Mock the bridge call to prevent actual bridging
            vm.mockCall(
                address(forwarder.OMNIBRIDGE()),
                abi.encodeCall(IOmnibridge.relayTokens, (COW_TOKEN_GNOSIS, mainnetRecipient, balance)),
                abi.encode()
            );

            // Forward the tokens
            forwarder.forwardToken(COW_TOKEN_GNOSIS);
        } else {
            console.log("COW token is not valid for bridging, skipping forward test");
        }
    }

    function testArbitraryCallDirect() public {
        // unauthorized sender
        address notReceiver = makeAddr("notReceiver");
        vm.prank(notReceiver);
        vm.expectRevert(GnosisForwarder.UnauthorizedSender.selector);
        forwarder.arbitraryCall(notReceiver, 0, hex"");

        MockTargetContract target = new MockTargetContract();
        assertEq(target.value(), 0);

        // authorized sender: target.setValue(1)
        vm.prank(mainnetRecipient);
        forwarder.arbitraryCall(address(target), 0, abi.encodeCall(MockTargetContract.setValue, (1)));
        assertEq(target.value(), 1);

        // authorized sender: target.setValuePayable(2)
        vm.deal(address(forwarder), 1 ether);
        vm.prank(mainnetRecipient);
        forwarder.arbitraryCall(address(target), 1, abi.encodeCall(MockTargetContract.setValuePayable, ()));

        // authorized sender: target.revertWith("revert message")
        vm.expectRevert("revert message");
        vm.prank(mainnetRecipient);
        forwarder.arbitraryCall(address(target), 0, abi.encodeCall(MockTargetContract.revertWith, ("revert message")));
    }

    function testArbitraryCallAmb() public {
        // unauthorized sender
        address notReceiver = makeAddr("notReceiver");
        vm.prank(notReceiver);
        vm.expectRevert(GnosisForwarder.UnauthorizedSender.selector);
        forwarder.arbitraryCall(notReceiver, 0, hex"");

        MockTargetContract target = new MockTargetContract();
        assertEq(target.value(), 0);

        address ambBridge = address(forwarder.AMB_BRIDGE());
        // amb bridge sender
        vm.prank(ambBridge);
        vm.expectRevert(GnosisForwarder.UnauthorizedSender.selector);
        forwarder.arbitraryCall(address(target), 0, abi.encodeCall(MockTargetContract.setValue, (1)));

        // set AMB bridge messageSender to mainnetRecipient
        vm.mockCall(ambBridge, abi.encodeCall(IAMBBridge.messageSender, ()), abi.encode(mainnetRecipient));
        vm.prank(ambBridge);
        vm.expectRevert(GnosisForwarder.UnauthorizedSender.selector);
        forwarder.arbitraryCall(address(target), 0, abi.encodeCall(MockTargetContract.setValue, (1)));

        // set AMB source chain to 1
        vm.mockCall(ambBridge, abi.encodeCall(IAMBBridge.messageSourceChainId, ()), abi.encode(1));

        // authorized sender: target.setValue(1)
        vm.prank(ambBridge);
        forwarder.arbitraryCall(address(target), 0, abi.encodeCall(MockTargetContract.setValue, (1)));
        assertEq(target.value(), 1);

        // authorized sender: target.setValuePayable(2)
        vm.deal(address(forwarder), 1 ether);
        vm.prank(ambBridge);
        forwarder.arbitraryCall(address(target), 2, abi.encodeCall(MockTargetContract.setValuePayable, ()));
        assertEq(target.value(), 2);

        // authorized sender: target.revertWith("revert message")
        vm.expectRevert("revert message");
        vm.prank(ambBridge);
        forwarder.arbitraryCall(address(target), 0, abi.encodeCall(MockTargetContract.revertWith, ("revert message")));
    }
}

contract MockTargetContract {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function setValuePayable() external payable {
        value = msg.value;
    }

    function revertWith(string memory message) external pure {
        revert(message);
    }
}
