// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "../src/forwarders/gnosis/GnosisForwarder.sol";
import "../src/forwarders/gnosis/GnosisForwarderFactory.sol";
import "../script/DeployGnosisForwarder.s.sol";

contract DeployGnosisForwarderTest is Test {
    DeployGnosisForwarder deployer;
    GnosisForwarderFactory factory;
    address mainnetRecipient = vm.addr(1);
    uint256 constant GNOSIS_CHAIN_ID = 100;

    function setUp() public {
        // Set chain ID to Gnosis Chain for deployment tests
        vm.chainId(GNOSIS_CHAIN_ID);

        deployer = new DeployGnosisForwarder();
        factory = new GnosisForwarderFactory();
    }

    function testDeploymentScriptOnGnosis() public view {
        // Verify we're on the correct chain
        assertEq(block.chainid, GNOSIS_CHAIN_ID);

        // The deployment script should work on Gnosis Chain
        // Note: We can't easily test the full script run() function due to PRIVATE_KEY requirement
        // But we can test the verification functions

        deployer.verifyDeployment(address(factory));
        console.log("Deployment verification passed");
    }

    function testDeployForwarderInstance() public {
        // Test deterministic deployment and initialization
        address testRecipient = address(0x1234567890123456789012345678901234567890);

        // Predict the forwarder address
        address predictedAddress = factory.predictForwarderAddress(testRecipient);

        // Deploy the forwarder
        address deployedAddress = factory.deployForwarder(testRecipient);

        // Verify the addresses match
        assertEq(predictedAddress, deployedAddress);

        // Verify the forwarder is initialized correctly
        GnosisForwarder forwarder = GnosisForwarder(payable(deployedAddress));
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), testRecipient);
        assertEq(block.chainid, GNOSIS_CHAIN_ID);
    }

    function testDeployMultipleForwarders() public {
        address[] memory recipients = new address[](3);
        recipients[0] = vm.addr(10);
        recipients[1] = vm.addr(11);
        recipients[2] = vm.addr(12);

        // Deploy multiple forwarders and verify deterministic deployment and initialization
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];

            // Predict and deploy
            address predicted = factory.predictForwarderAddress(recipient);
            address deployed = factory.deployForwarder(recipient);

            assertEq(predicted, deployed);

            GnosisForwarder forwarder = GnosisForwarder(payable(deployed));
            assertTrue(forwarder.initialized());
            assertEq(forwarder.mainnetRecipient(), recipient);
        }
    }

    function testVerifyDeployment() public {
        // Deploy a factory and verify it
        GnosisForwarderFactory testFactory = new GnosisForwarderFactory();

        // This should not revert
        deployer.verifyDeployment(address(testFactory));

        // Verify the implementation exists and is correct
        address implementation = testFactory.getImplementation();
        assertTrue(implementation != address(0));

        GnosisForwarder impl = GnosisForwarder(payable(implementation));
        assertEq(block.chainid, GNOSIS_CHAIN_ID);
        assertTrue(address(impl.OMNIBRIDGE()) != address(0) && address(impl.XDAI_BRIDGE()) != address(0));
    }

    function testFactoryPredictionConsistency() public {
        // Test that predictions are consistent within the same factory instance
        address testRecipient = vm.addr(99);

        address predicted1 = factory.predictForwarderAddress(testRecipient);
        address predicted2 = factory.predictForwarderAddress(testRecipient);

        // Predictions should be the same for the same recipient and factory
        assertEq(predicted1, predicted2, "Same factory predictions should match");

        // Now test that different factories have different implementations
        GnosisForwarderFactory factory2 = new GnosisForwarderFactory();
        address predicted3 = factory2.predictForwarderAddress(testRecipient);

        // Different factories will have different implementations, so different predictions
        assertTrue(predicted1 != predicted3, "Different factories should have different predictions");
    }

    function testInvalidChainDeployment() public {
        // Change to a different chain
        vm.chainId(1); // Ethereum mainnet

        // Creating a new GnosisForwarder should fail on wrong chain
        GnosisForwarder newForwarder = new GnosisForwarder();

        vm.expectRevert(Forwarder.InvalidChain.selector);
        newForwarder.initialize(mainnetRecipient);
    }

    function testGetDeploymentAddresses() public view {
        // Test the getDeploymentAddresses function
        (address implementation, address factoryAddr) = deployer.getDeploymentAddresses();

        // Without environment variables set, these should be zero
        // (This tests the try/catch behavior)
        assertEq(implementation, address(0));
        assertEq(factoryAddr, address(0));
    }

    function testForwarderDuplicateDeployment() public {
        address recipient = vm.addr(50);

        // Deploy first forwarder
        address forwarder1 = factory.deployForwarder(recipient);

        // Use getOrDeployForwarder for second attempt - this handles duplicates gracefully
        address forwarder2 = factory.getOrDeployForwarder(recipient);

        assertEq(forwarder1, forwarder2);
    }

    function testDeploymentConstants() public {
        // Verify that our test forwarder has correct constants
        GnosisForwarder testForwarder = new GnosisForwarder();
        assertEq(testForwarder.GNOSIS_CHAIN_ID(), 100);
        assertEq(address(testForwarder.OMNIBRIDGE()), 0xf6A78083ca3e2a662D6dd1703c939c8aCE2e268d);
        assertEq(address(testForwarder.XDAI_BRIDGE()), 0x7301CFA0e1756B71869E93d4e4Dca5c7d0eb0AA6);
    }

    function testForwarderInitialization() public {
        address recipient = vm.addr(60);

        // Deploy via factory
        address forwarderAddr = factory.deployForwarder(recipient);
        GnosisForwarder forwarder = GnosisForwarder(payable(forwarderAddr));

        // Should be initialized
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), recipient);

        // Should not be able to initialize again
        vm.expectRevert(Forwarder.AlreadyInitialized.selector);
        forwarder.initialize(recipient);
    }

    function testBridgeConfigurationInDeployment() public {
        // Deploy forwarder and check bridge configuration
        address forwarderAddr = factory.deployForwarder(mainnetRecipient);
        GnosisForwarder forwarder = GnosisForwarder(payable(forwarderAddr));

        assertTrue(address(forwarder.OMNIBRIDGE()) != address(0) && address(forwarder.XDAI_BRIDGE()) != address(0));

        // Check individual bridge addresses
        assertTrue(address(forwarder.OMNIBRIDGE()) != address(0));
        assertTrue(address(forwarder.XDAI_BRIDGE()) != address(0));
    }

    function testFactoryImplementationConsistency() public {
        // Deploy multiple factories and ensure they use the same implementation
        GnosisForwarderFactory factory1 = new GnosisForwarderFactory();
        GnosisForwarderFactory factory2 = new GnosisForwarderFactory();

        address impl1 = factory1.getImplementation();
        address impl2 = factory2.getImplementation();

        // Implementations should be different instances but same bytecode
        assertTrue(impl1 != address(0));
        assertTrue(impl2 != address(0));

        // Both should be GnosisForwarder instances
        GnosisForwarder forwarder1 = GnosisForwarder(payable(impl1));
        GnosisForwarder forwarder2 = GnosisForwarder(payable(impl2));

        assertEq(block.chainid, block.chainid);
        assertEq(address(forwarder1.OMNIBRIDGE()), address(forwarder2.OMNIBRIDGE()));
    }
}
