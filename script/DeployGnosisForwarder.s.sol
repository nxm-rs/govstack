// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/forwarders/GnosisChainForwarder.sol";
import "../src/ForwarderFactory.sol";

/// @title DeployGnosisForwarder
/// @notice Deployment script for GnosisChainForwarder on Gnosis Chain using LibClone
contract DeployGnosisForwarder is Script {
    /// @notice The expected Gnosis Chain ID
    uint256 constant GNOSIS_CHAIN_ID = 100;

    /// @notice Event emitted when deployment is complete
    event DeploymentComplete(address indexed implementation, address indexed factory, uint256 chainId);

    /// @notice Deploy the GnosisChainForwarder implementation and factory
    function run() external {
        // Verify we're deploying on Gnosis Chain
        require(block.chainid == GNOSIS_CHAIN_ID, "Must deploy on Gnosis Chain");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying GnosisChainForwarder...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract (no constructor args needed)
        GnosisChainForwarder implementation = new GnosisChainForwarder();
        console.log("GnosisChainForwarder implementation deployed at:", address(implementation));

        // Deploy the factory contract
        ForwarderFactory factory = new ForwarderFactory();
        console.log("ForwarderFactory deployed at:", address(factory));

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Factory:", address(factory));
        console.log("Chain ID:", block.chainid);

        emit DeploymentComplete(address(implementation), address(factory), block.chainid);
    }

    /// @notice Deploy a specific forwarder instance for a mainnet recipient
    /// @param implementationAddress The deployed implementation address
    /// @param factoryAddress The deployed factory address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    function deployForwarderInstance(address implementationAddress, address factoryAddress, address mainnetRecipient)
        external
    {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must deploy on Gnosis Chain");
        require(implementationAddress != address(0), "Invalid implementation");
        require(factoryAddress != address(0), "Invalid factory");
        require(mainnetRecipient != address(0), "Invalid recipient");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("Deploying forwarder instance...");
        console.log("Implementation:", implementationAddress);
        console.log("Factory:", factoryAddress);
        console.log("Mainnet recipient:", mainnetRecipient);

        vm.startBroadcast(deployerPrivateKey);

        ForwarderFactory factory = ForwarderFactory(factoryAddress);

        // Predict the forwarder address using the direct method
        address predictedAddress = factory.predictForwarderAddressDirect(implementationAddress, mainnetRecipient);
        console.log("Predicted forwarder address:", predictedAddress);

        // Deploy the forwarder using the direct method (recommended)
        address forwarderAddress = factory.deployForwarderDirect(implementationAddress, mainnetRecipient);
        console.log("Deployed forwarder address:", forwarderAddress);

        // Verify the addresses match
        require(predictedAddress == forwarderAddress, "Address mismatch");

        vm.stopBroadcast();

        console.log("\n=== Forwarder Instance Deployed ===");
        console.log("Forwarder address:", forwarderAddress);
        console.log("Mainnet recipient:", mainnetRecipient);
        console.log("Implementation:", implementationAddress);
    }

    /// @notice Deploy multiple forwarder instances for different recipients
    /// @param implementationAddress The deployed implementation address
    /// @param factoryAddress The deployed factory address
    /// @param mainnetRecipients Array of mainnet addresses that will receive tokens
    function deployMultipleForwarders(
        address implementationAddress,
        address factoryAddress,
        address[] calldata mainnetRecipients
    ) external {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must deploy on Gnosis Chain");
        require(implementationAddress != address(0), "Invalid implementation");
        require(factoryAddress != address(0), "Invalid factory");
        require(mainnetRecipients.length > 0, "No recipients provided");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("Deploying multiple forwarder instances...");
        console.log("Implementation:", implementationAddress);
        console.log("Factory:", factoryAddress);
        console.log("Number of recipients:", mainnetRecipients.length);

        vm.startBroadcast(deployerPrivateKey);

        ForwarderFactory factory = ForwarderFactory(factoryAddress);

        for (uint256 i = 0; i < mainnetRecipients.length; i++) {
            address recipient = mainnetRecipients[i];
            require(recipient != address(0), "Invalid recipient");

            console.log("Deploying forwarder for recipient:", recipient);

            // Check if already deployed
            if (factory.forwarderExists(implementationAddress, recipient)) {
                console.log("Forwarder already exists for recipient:", recipient);
                continue;
            }

            // Deploy the forwarder
            address forwarderAddress = factory.deployForwarderDirect(implementationAddress, recipient);
            console.log("Deployed forwarder at:", forwarderAddress);
        }

        vm.stopBroadcast();

        console.log("\n=== Multiple Forwarders Deployed ===");
    }

    /// @notice Get deployment addresses from environment or previous deployment
    function getDeploymentAddresses() external view returns (address implementation, address factory) {
        // Try to get from environment variables
        try vm.envAddress("GNOSIS_FORWARDER_IMPL") returns (address impl) {
            implementation = impl;
        } catch {
            console.log("GNOSIS_FORWARDER_IMPL not set");
        }

        try vm.envAddress("GNOSIS_FORWARDER_FACTORY") returns (address fact) {
            factory = fact;
        } catch {
            console.log("GNOSIS_FORWARDER_FACTORY not set");
        }
    }

    /// @notice Verify deployment on Gnosis Chain
    function verifyDeployment(address implementationAddress, address factoryAddress) external view {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must verify on Gnosis Chain");

        console.log("Verifying deployment...");

        // Verify implementation
        GnosisChainForwarder impl = GnosisChainForwarder(payable(implementationAddress));
        require(impl.getChainId() == GNOSIS_CHAIN_ID, "Wrong chain for implementation");
        require(impl.isBridgeConfigured(), "Bridge not configured");
        console.log("[OK] Implementation verified");

        // Verify factory
        ForwarderFactory factory = ForwarderFactory(factoryAddress);
        // Test prediction function works
        address testPrediction = factory.predictForwarderAddressDirect(implementationAddress, address(0x1));
        require(testPrediction != address(0), "Factory prediction failed");
        console.log("[OK] Factory verified");

        console.log("[OK] All verifications passed");
    }

    /// @notice Test deployment by creating a test forwarder instance
    function testDeployment(address implementationAddress, address factoryAddress) external {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must test on Gnosis Chain");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address testRecipient = address(0x1234567890123456789012345678901234567890);

        console.log("Testing deployment with test recipient:", testRecipient);

        vm.startBroadcast(deployerPrivateKey);

        ForwarderFactory factory = ForwarderFactory(factoryAddress);

        // Deploy test forwarder
        address testForwarder = factory.deployForwarderDirect(implementationAddress, testRecipient);

        // Verify the forwarder is initialized correctly
        GnosisChainForwarder forwarder = GnosisChainForwarder(payable(testForwarder));
        require(forwarder.initialized(), "Forwarder not initialized");
        require(forwarder.mainnetRecipient() == testRecipient, "Wrong recipient");
        require(forwarder.getChainId() == GNOSIS_CHAIN_ID, "Wrong chain ID");

        vm.stopBroadcast();

        console.log("[OK] Test deployment successful");
        console.log("Test forwarder address:", testForwarder);
    }

    /// @notice Check forwarder determinism across different deployers
    function testDeterminism(
        address implementationAddress,
        address factoryAddress1,
        address factoryAddress2,
        address testRecipient
    ) external view {
        console.log("Testing address determinism...");

        ForwarderFactory factory1 = ForwarderFactory(factoryAddress1);
        ForwarderFactory factory2 = ForwarderFactory(factoryAddress2);

        address predicted1 = factory1.predictForwarderAddressDirect(implementationAddress, testRecipient);
        address predicted2 = factory2.predictForwarderAddressDirect(implementationAddress, testRecipient);

        console.log("Factory 1 prediction:", predicted1);
        console.log("Factory 2 prediction:", predicted2);

        if (predicted1 == predicted2) {
            console.log("[OK] Deterministic deployment verified");
        } else {
            console.log("[FAIL] Deterministic deployment failed");
        }
    }
}
