// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/forwarders/gnosis/GnosisForwarder.sol";
import "../src/forwarders/gnosis/GnosisForwarderFactory.sol";

/// @title DeployGnosisForwarder
/// @notice Deployment script for GnosisForwarder on Gnosis Chain using LibClone
contract DeployGnosisForwarder is Script {
    /// @notice The expected Gnosis Chain ID
    uint256 constant GNOSIS_CHAIN_ID = 100;

    /// @notice Event emitted when deployment is complete
    event DeploymentComplete(address indexed implementation, address indexed factory, uint256 chainId);

    /// @notice Deploy the ForwarderFactory (which deploys its own implementation)
    function run() external {
        // Verify we're deploying on Gnosis Chain
        require(block.chainid == GNOSIS_CHAIN_ID, "Must deploy on Gnosis Chain");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying ForwarderFactory with embedded implementation...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory contract (which will deploy its own implementation)
        GnosisForwarderFactory factory = new GnosisForwarderFactory();
        console.log("ForwarderFactory deployed at:", address(factory));

        // Get the implementation address that was deployed by the factory
        address implementation = factory.getImplementation();
        console.log("GnosisForwarder implementation deployed at:", implementation);

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("Factory:", address(factory));
        console.log("Chain ID:", block.chainid);

        emit DeploymentComplete(address(implementation), address(factory), block.chainid);
    }

    /// @notice Deploy a specific forwarder instance for a mainnet recipient
    /// @param factoryAddress The deployed factory address
    /// @param mainnetRecipient The mainnet address that will receive tokens
    function deployForwarderInstance(address factoryAddress, address mainnetRecipient) external {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must deploy on Gnosis Chain");
        require(factoryAddress != address(0), "Invalid factory");
        require(mainnetRecipient != address(0), "Invalid recipient");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        GnosisForwarderFactory factory = GnosisForwarderFactory(factoryAddress);
        address implementationAddress = factory.getImplementation();

        console.log("Deploying forwarder instance...");
        console.log("Implementation:", implementationAddress);
        console.log("Factory:", factoryAddress);
        console.log("Mainnet recipient:", mainnetRecipient);

        vm.startBroadcast(deployerPrivateKey);

        // Predict the forwarder address using the standard method
        address predictedAddress = factory.predictForwarderAddress(mainnetRecipient, bytes32(0));
        console.log("Predicted forwarder address:", predictedAddress);

        // Deploy the forwarder using the standard method
        address forwarderAddress = factory.deployForwarder(mainnetRecipient, bytes32(0));
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
    /// @param factoryAddress The deployed factory address
    /// @param mainnetRecipients Array of mainnet addresses that will receive tokens
    function deployMultipleForwarders(address factoryAddress, address[] calldata mainnetRecipients) external {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must deploy on Gnosis Chain");
        require(factoryAddress != address(0), "Invalid factory");
        require(mainnetRecipients.length > 0, "No recipients provided");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        GnosisForwarderFactory factory = GnosisForwarderFactory(factoryAddress);
        address implementationAddress = factory.getImplementation();

        console.log("Deploying multiple forwarder instances...");
        console.log("Implementation:", implementationAddress);
        console.log("Factory:", factoryAddress);
        console.log("Number of recipients:", mainnetRecipients.length);

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < mainnetRecipients.length; i++) {
            address recipient = mainnetRecipients[i];
            require(recipient != address(0), "Invalid recipient");

            console.log("Deploying forwarder for recipient:", recipient);

            // Check if already deployed
            address predictedAddress = factory.predictForwarderAddress(recipient, bytes32(0));
            if (predictedAddress.code.length > 0) {
                console.log("Forwarder already exists for recipient:", recipient);
                continue;
            }

            // Deploy the forwarder
            address forwarderAddress = factory.deployForwarder(recipient, bytes32(0));
            console.log("Deployed forwarder at:", forwarderAddress);
        }

        vm.stopBroadcast();

        console.log("\n=== Multiple Forwarders Deployed ===");
    }

    /// @notice Get deployment addresses from environment or previous deployment
    function getDeploymentAddresses() external view returns (address implementation, address factory) {
        // Try to get from environment variables
        try vm.envAddress("GNOSIS_FORWARDER_FACTORY") returns (address fact) {
            factory = fact;
            if (factory != address(0)) {
                implementation = GnosisForwarderFactory(factory).getImplementation();
            }
        } catch {
            console.log("GNOSIS_FORWARDER_FACTORY not set");
        }
    }

    /// @notice Verify deployment on Gnosis Chain
    function verifyDeployment(address factoryAddress) external view {
        require(block.chainid == GNOSIS_CHAIN_ID, "Must verify on Gnosis Chain");

        console.log("Verifying deployment...");

        // Verify factory
        GnosisForwarderFactory factory = GnosisForwarderFactory(factoryAddress);
        address implementationAddress = factory.getImplementation();
        require(implementationAddress != address(0), "No implementation found");

        // Verify implementation
        GnosisForwarder impl = GnosisForwarder(payable(implementationAddress));
        require(block.chainid == GNOSIS_CHAIN_ID, "Wrong chain for implementation");
        require(
            address(impl.OMNIBRIDGE()) != address(0) && address(impl.XDAI_BRIDGE()) != address(0),
            "Bridge not configured"
        );
        console.log("[OK] Implementation verified");

        // Test prediction function works
        address testPrediction = factory.predictForwarderAddress(address(0x1), bytes32(0));
        require(testPrediction != address(0), "Factory prediction failed");
        console.log("[OK] Factory verified");

        console.log("[OK] All verifications passed");
    }
}
