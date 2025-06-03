// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "../src/Deployer.sol";
import "../src/Token.sol";
import "../src/Governor.sol";
import "../src/TokenSplitter.sol";

/**
 * @title Deploy
 * @dev Advanced deployment script with TOML configuration support for Token, Governor, and TokenSplitter.
 * Supports multiple distribution scenarios, splitter configurations, network-specific settings,
 * and CREATE2 deployment with unique salts per chain.
 */
contract Deploy is Script {
    struct OwnerConfig {
        address ownerAddress;
    }

    struct NetworkConfig {
        string description;
        uint256 chainId;
        uint256 blockTimeMilliseconds;
        uint256 gasPriceGwei;
        uint256 gasLimit;
    }

    struct DeploymentConfig {
        string scenario;
        string splitterScenario;
        bool verify;
        bool saveArtifacts;
        string customSalt;
    }

    struct RecipientInfo {
        string name;
        address recipientAddress;
        uint256 amount;
        string description;
    }

    struct PayeeInfo {
        address account;
        uint256 shares;
    }

    struct SplitterInfo {
        string description;
        PayeeInfo[] payees;
    }

    struct TimeBasedGovernorConfig {
        string name;
        string votingDelayTime;
        string votingPeriodTime;
        string lateQuorumExtensionTime;
        uint256 quorumNumerator;
    }

    // Events for deployment tracking
    event ConfigurationLoaded(string configPath, string scenario, string splitterScenario);
    event TimeParametersConverted(
        string votingDelayTime,
        uint256 votingDelayBlocks,
        string votingPeriodTime,
        uint256 votingPeriodBlocks,
        string lateQuorumExtensionTime,
        uint256 lateQuorumExtensionBlocks
    );
    event DistributionScenarioSelected(string scenario, uint256 recipientCount);
    event SplitterScenarioSelected(string scenario, uint256 payeeCount, uint256 tokenCount);
    event ContractsPredicted(address token, address governor, address splitter);
    event DeploymentCompleted(
        address indexed token,
        address indexed governor,
        address indexed splitter,
        uint256 totalDistributed,
        bytes32 salt
    );

    /**
     * @dev Main entry point for deployment script
     */
    function run() external virtual {
        runWithConfig("config/deployment.toml");
    }

    /**
     * @dev Run deployment with specific config file
     * @param configPath Path to the TOML configuration file
     */
    function runWithConfig(string memory configPath) public {
        runWithScenario(configPath, "", "");
    }

    /**
     * @dev Run deployment with specific distribution and splitter scenarios
     * @param configPath Path to the TOML configuration file
     * @param distributionScenario Distribution scenario to use (empty for config default)
     * @param splitterScenario Splitter scenario to use (empty for config default)
     */
    function runWithScenario(
        string memory configPath,
        string memory distributionScenario,
        string memory splitterScenario
    ) public {
        // Load configuration from TOML
        (
            AbstractDeployer.TokenConfig memory tokenConfig,
            AbstractDeployer.GovernorConfig memory governorConfig,
            OwnerConfig memory ownerConfig,
            NetworkConfig memory networkConfig,
            DeploymentConfig memory deploymentConfig,
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        ) = _loadConfiguration(configPath, distributionScenario, splitterScenario);

        emit ConfigurationLoaded(configPath, deploymentConfig.scenario, deploymentConfig.splitterScenario);

        // Validate network
        _validateNetwork(networkConfig);

        // Display configuration
        _displayConfiguration(tokenConfig, governorConfig, ownerConfig, recipients, splitterInfo);

        // Deploy contracts
        _deployWithConfiguration(tokenConfig, governorConfig, ownerConfig, recipients, splitterInfo);
    }

    /**
     * @dev Load configuration from TOML file
     */
    function _loadConfiguration(
        string memory configPath,
        string memory distributionScenario,
        string memory splitterScenario
    )
        public
        returns (
            AbstractDeployer.TokenConfig memory tokenConfig,
            AbstractDeployer.GovernorConfig memory governorConfig,
            OwnerConfig memory ownerConfig,
            NetworkConfig memory networkConfig,
            DeploymentConfig memory deploymentConfig,
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        )
    {
        string memory toml = vm.readFile(configPath);

        // Load basic configurations
        tokenConfig.name = vm.parseTomlString(toml, ".token.name");
        tokenConfig.symbol = vm.parseTomlString(toml, ".token.symbol");
        tokenConfig.initialSupply = vm.parseTomlUint(toml, ".token.initial_supply");

        // Load time-based governor config
        TimeBasedGovernorConfig memory timeBasedConfig;
        timeBasedConfig.name = vm.parseTomlString(toml, ".governor.name");
        timeBasedConfig.votingDelayTime = vm.parseTomlString(toml, ".governor.voting_delay_time");
        timeBasedConfig.votingPeriodTime = vm.parseTomlString(toml, ".governor.voting_period_time");
        timeBasedConfig.lateQuorumExtensionTime = vm.parseTomlString(toml, ".governor.late_quorum_extension_time");
        timeBasedConfig.quorumNumerator = vm.parseTomlUint(toml, ".governor.quorum_numerator");

        ownerConfig.ownerAddress = vm.parseTomlAddress(toml, ".treasury.address");

        deploymentConfig.scenario = bytes(distributionScenario).length > 0
            ? distributionScenario
            : vm.parseTomlString(toml, ".deployment.scenario");
        deploymentConfig.splitterScenario = bytes(splitterScenario).length > 0
            ? splitterScenario
            : vm.parseTomlString(toml, ".deployment.splitter_scenario");
        deploymentConfig.verify = vm.parseTomlBool(toml, ".deployment.verify");
        deploymentConfig.saveArtifacts = vm.parseTomlBool(toml, ".deployment.save_artifacts");
        deploymentConfig.customSalt = vm.parseTomlString(toml, ".deployment.custom_salt");

        // Load network configuration
        networkConfig = _loadNetworkConfig(toml);

        // Convert time-based parameters to blocks
        governorConfig = _convertTimeBasedGovernorConfig(timeBasedConfig, networkConfig);

        // Load distribution scenario
        recipients = _loadDistributionScenario(toml, deploymentConfig.scenario);

        // Load splitter scenario
        splitterInfo = _loadSplitterScenario(toml, deploymentConfig.splitterScenario);
    }

    /**
     * @dev Load network configuration from TOML
     */
    function _loadNetworkConfig(string memory toml) public view returns (NetworkConfig memory networkConfig) {
        uint256 currentChainId = block.chainid;
        string memory networkKey;

        if (currentChainId == 1) {
            networkKey = "mainnet";
        } else if (currentChainId == 11155111) {
            networkKey = "sepolia";
        } else {
            networkKey = "mainnet"; // Default fallback
        }

        string memory networkPath = string.concat(".networks.", networkKey);

        networkConfig.description = vm.parseTomlString(toml, string.concat(networkPath, ".description"));
        networkConfig.chainId = vm.parseTomlUint(toml, string.concat(networkPath, ".chain_id"));
        networkConfig.blockTimeMilliseconds =
            vm.parseTomlUint(toml, string.concat(networkPath, ".block_time_milliseconds"));
        networkConfig.gasPriceGwei = vm.parseTomlUint(toml, string.concat(networkPath, ".gas_price_gwei"));
        networkConfig.gasLimit = vm.parseTomlUint(toml, string.concat(networkPath, ".gas_limit"));
    }

    /**
     * @dev Convert time-based governor config to block-based config
     */
    function _convertTimeBasedGovernorConfig(
        TimeBasedGovernorConfig memory timeBasedConfig,
        NetworkConfig memory networkConfig
    ) public returns (AbstractDeployer.GovernorConfig memory governorConfig) {
        governorConfig.name = timeBasedConfig.name;
        governorConfig.quorumNumerator = timeBasedConfig.quorumNumerator;

        // Convert time strings to blocks
        uint256 votingDelayBlocks =
            _parseTimeToBlocks(timeBasedConfig.votingDelayTime, networkConfig.blockTimeMilliseconds);
        uint256 votingPeriodBlocks =
            _parseTimeToBlocks(timeBasedConfig.votingPeriodTime, networkConfig.blockTimeMilliseconds);
        uint256 lateQuorumExtensionBlocks =
            _parseTimeToBlocks(timeBasedConfig.lateQuorumExtensionTime, networkConfig.blockTimeMilliseconds);

        governorConfig.votingDelay = votingDelayBlocks;
        governorConfig.votingPeriod = votingPeriodBlocks;
        governorConfig.lateQuorumExtension = uint48(lateQuorumExtensionBlocks);

        emit TimeParametersConverted(
            timeBasedConfig.votingDelayTime,
            votingDelayBlocks,
            timeBasedConfig.votingPeriodTime,
            votingPeriodBlocks,
            timeBasedConfig.lateQuorumExtensionTime,
            lateQuorumExtensionBlocks
        );
    }

    /**
     * @dev Parse time string to blocks
     * Supports formats like "1 day", "2 hours", "30 minutes", "45 seconds"
     */
    function _parseTimeToBlocks(string memory timeStr, uint256 blockTimeMilliseconds) public pure returns (uint256) {
        bytes memory timeBytes = bytes(timeStr);
        require(timeBytes.length > 0, "Empty time string");

        // Find the space separator
        uint256 spaceIndex = 0;
        for (uint256 i = 0; i < timeBytes.length; i++) {
            if (timeBytes[i] == 0x20) {
                // space character
                spaceIndex = i;
                break;
            }
        }
        require(spaceIndex > 0 && spaceIndex < timeBytes.length - 1, "Invalid time format");

        // Extract number part
        string memory numberStr = _substring(timeStr, 0, spaceIndex);
        uint256 number = _parseStringToUint(numberStr);

        // Extract unit part
        string memory unit = _substring(timeStr, spaceIndex + 1, timeBytes.length);
        uint256 totalSeconds = _convertUnitToSeconds(unit, number);

        // Convert seconds to milliseconds, then to blocks (ceiling division)
        uint256 totalMilliseconds = totalSeconds * 1000;
        return (totalMilliseconds + blockTimeMilliseconds - 1) / blockTimeMilliseconds;
    }

    /**
     * @dev Convert unit string to seconds
     */
    function _convertUnitToSeconds(string memory unit, uint256 value) public pure returns (uint256) {
        bytes32 unitHash = keccak256(bytes(unit));

        // Seconds
        if (
            unitHash == keccak256("second") || unitHash == keccak256("seconds") || unitHash == keccak256("sec")
                || unitHash == keccak256("secs") || unitHash == keccak256("s")
        ) {
            return value;
        }
        // Minutes
        if (
            unitHash == keccak256("minute") || unitHash == keccak256("minutes") || unitHash == keccak256("min")
                || unitHash == keccak256("mins") || unitHash == keccak256("m")
        ) {
            return value * 60;
        }
        // Hours
        if (
            unitHash == keccak256("hour") || unitHash == keccak256("hours") || unitHash == keccak256("hr")
                || unitHash == keccak256("hrs") || unitHash == keccak256("h")
        ) {
            return value * 3600;
        }
        // Days
        if (unitHash == keccak256("day") || unitHash == keccak256("days") || unitHash == keccak256("d")) {
            return value * 86400;
        }
        // Weeks
        if (unitHash == keccak256("week") || unitHash == keccak256("weeks") || unitHash == keccak256("w")) {
            return value * 604800;
        }

        revert(string.concat("Unsupported time unit: ", unit));
    }

    /**
     * @dev Extract substring from string
     */
    function _substring(string memory str, uint256 start, uint256 end) public pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(start <= end && end <= strBytes.length, "Invalid substring range");

        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }
        return string(result);
    }

    /**
     * @dev Parse string to uint256
     */
    function _parseStringToUint(string memory str) public pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        uint256 result = 0;

        for (uint256 i = 0; i < strBytes.length; i++) {
            uint8 digit = uint8(strBytes[i]);
            require(digit >= 48 && digit <= 57, "Invalid number character");
            result = result * 10 + (digit - 48);
        }

        return result;
    }

    /**
     * @dev Load distribution scenario from TOML
     */
    function _loadDistributionScenario(string memory toml, string memory scenario)
        internal
        returns (RecipientInfo[] memory recipients)
    {
        string memory scenarioPath = string.concat(".distributions.", scenario);

        // Parse recipients array
        string[] memory recipientNames =
            vm.parseTomlStringArray(toml, string.concat(scenarioPath, ".recipients[*].name"));
        address[] memory recipientAddresses =
            vm.parseTomlAddressArray(toml, string.concat(scenarioPath, ".recipients[*].address"));
        uint256[] memory recipientAmounts =
            vm.parseTomlUintArray(toml, string.concat(scenarioPath, ".recipients[*].amount"));
        string[] memory recipientDescriptions =
            vm.parseTomlStringArray(toml, string.concat(scenarioPath, ".recipients[*].description"));

        recipients = new RecipientInfo[](recipientNames.length);
        for (uint256 i = 0; i < recipientNames.length; i++) {
            recipients[i] = RecipientInfo({
                name: recipientNames[i],
                recipientAddress: recipientAddresses[i],
                amount: recipientAmounts[i],
                description: recipientDescriptions[i]
            });
        }

        emit DistributionScenarioSelected(scenario, recipients.length);
    }

    /**
     * @dev Load splitter scenario from TOML
     */
    function _loadSplitterScenario(string memory toml, string memory scenario)
        internal
        returns (SplitterInfo memory splitterInfo)
    {
        if (keccak256(bytes(scenario)) == keccak256(bytes("none"))) {
            // No splitter requested
            return splitterInfo;
        }

        string memory scenarioPath = string.concat(".splitter.", scenario);

        // Load description
        splitterInfo.description = vm.parseTomlString(toml, string.concat(scenarioPath, ".description"));

        // Load payees
        address[] memory payeeAccounts =
            vm.parseTomlAddressArray(toml, string.concat(scenarioPath, ".payees[*].account"));
        uint256[] memory payeeShares = vm.parseTomlUintArray(toml, string.concat(scenarioPath, ".payees[*].shares"));

        splitterInfo.payees = new PayeeInfo[](payeeAccounts.length);
        for (uint256 i = 0; i < payeeAccounts.length; i++) {
            splitterInfo.payees[i] = PayeeInfo({account: payeeAccounts[i], shares: payeeShares[i]});
        }

        emit SplitterScenarioSelected(scenario, splitterInfo.payees.length, 0);
    }

    /**
     * @dev Validate network configuration
     */
    function _validateNetwork(NetworkConfig memory networkConfig) internal view {
        require(networkConfig.chainId == block.chainid, "Network chain ID mismatch");
    }

    /**
     * @dev Display configuration summary
     */
    function _displayConfiguration(
        AbstractDeployer.TokenConfig memory tokenConfig,
        AbstractDeployer.GovernorConfig memory governorConfig,
        OwnerConfig memory ownerConfig,
        RecipientInfo[] memory recipients,
        SplitterInfo memory splitterInfo
    ) internal view {
        console.log("=== Deployment Configuration ===");
        console.log("Token Name:", tokenConfig.name);
        console.log("Token Symbol:", tokenConfig.symbol);
        console.log("Token Initial Supply:", tokenConfig.initialSupply);
        console.log("Governor Name:", governorConfig.name);
        console.log("Voting Delay:", governorConfig.votingDelay);
        console.log("Voting Period:", governorConfig.votingPeriod);
        console.log("Quorum Numerator:", governorConfig.quorumNumerator);
        console.log("Late Quorum Extension:", governorConfig.lateQuorumExtension);
        console.log("Final Owner:", ownerConfig.ownerAddress);
        console.log("Recipients Count:", recipients.length);
        console.log("Splitter Payees Count:", splitterInfo.payees.length);
        console.log("Splitter Payees:", splitterInfo.payees.length);
        console.log("Chain ID:", block.chainid);
        console.log("================================");
    }

    /**
     * @dev Deploy contracts with configuration
     */
    function _deployWithConfiguration(
        AbstractDeployer.TokenConfig memory tokenConfig,
        AbstractDeployer.GovernorConfig memory governorConfig,
        OwnerConfig memory ownerConfig,
        RecipientInfo[] memory recipients,
        SplitterInfo memory splitterInfo
    ) internal {
        // Convert recipients to AbstractDeployer.TokenDistribution format
        AbstractDeployer.TokenDistribution[] memory distributions =
            new AbstractDeployer.TokenDistribution[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            distributions[i] = AbstractDeployer.TokenDistribution({
                recipient: recipients[i].recipientAddress,
                amount: recipients[i].amount
            });
        }

        // Convert splitter info to AbstractDeployer.SplitterConfig format
        AbstractDeployer.SplitterConfig memory splitterConfig;
        if (splitterInfo.payees.length > 0) {
            // Create packed payees data
            bytes memory packedData;
            for (uint256 i = 0; i < splitterInfo.payees.length; i++) {
                packedData =
                    abi.encodePacked(packedData, uint16(splitterInfo.payees[i].shares), splitterInfo.payees[i].account);
            }
            splitterConfig.packedPayeesData = packedData;
        }

        // Start broadcasting
        vm.startBroadcast();

        // Deploy using the Deployer contract
        new Deployer(tokenConfig, governorConfig, splitterConfig, distributions, ownerConfig.ownerAddress);

        vm.stopBroadcast();

        // Extract deployment addresses from events
        (address tokenAddress, address governorAddress, address splitterAddress, uint256 totalDistributed, bytes32 salt)
        = _getDeploymentDetailsFromEvents();

        emit ContractsPredicted(tokenAddress, governorAddress, splitterAddress);

        // Verify deployment
        _verifyDeployment(tokenAddress, governorAddress, splitterAddress);

        // Save deployment artifacts
        _saveDeploymentArtifacts(tokenAddress, governorAddress, splitterAddress, salt);

        emit DeploymentCompleted(tokenAddress, governorAddress, splitterAddress, totalDistributed, salt);

        console.log("=== Deployment Successful ===");
        console.log("Token Address:", tokenAddress);
        console.log("Governor Address:", governorAddress);
        if (splitterAddress != address(0)) {
            console.log("Splitter Address:", splitterAddress);
        }
        console.log("Total Distributed:", totalDistributed);
        console.log("Deployment Salt:", vm.toString(salt));
        console.log("=============================");
    }

    /**
     * @dev Extract deployment details from events
     */
    function _getDeploymentDetailsFromEvents()
        internal
        returns (
            address tokenAddress,
            address governorAddress,
            address splitterAddress,
            uint256 totalDistributed,
            bytes32 salt
        )
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DeploymentCompleted(address,address,address,address,uint256,bytes32)"))
            {
                tokenAddress = address(uint160(uint256(logs[i].topics[1])));
                governorAddress = address(uint160(uint256(logs[i].topics[2])));
                splitterAddress = address(uint160(uint256(logs[i].topics[3])));
                (, uint256 distributed, bytes32 deploymentSalt) = abi.decode(logs[i].data, (address, uint256, bytes32));
                totalDistributed = distributed;
                salt = deploymentSalt;
                break;
            }
        }
    }

    /**
     * @dev Verify deployed contracts
     */
    function _verifyDeployment(address tokenAddress, address governorAddress, address splitterAddress) internal view {
        // Verify token exists and has basic properties
        Token token = Token(tokenAddress);
        require(bytes(token.name()).length > 0, "Token name should not be empty");
        require(bytes(token.symbol()).length > 0, "Token symbol should not be empty");

        // Verify governor exists and has basic properties
        TokenGovernor governor = TokenGovernor(payable(governorAddress));
        require(bytes(governor.name()).length > 0, "Governor name should not be empty");
        require(governor.votingDelay() > 0, "Governor voting delay should be greater than 0");
        require(governor.votingPeriod() > 0, "Governor voting period should be greater than 0");

        // Verify splitter if deployed
        if (splitterAddress != address(0)) {
            TokenSplitter splitter = TokenSplitter(splitterAddress);
            require(splitter.hasPayees(), "Splitter should have payees");
        }

        console.log("Contract verification successful");
    }

    /**
     * @dev Save deployment artifacts
     */
    function _saveDeploymentArtifacts(
        address tokenAddress,
        address governorAddress,
        address splitterAddress,
        bytes32 salt
    ) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory timestamp = vm.toString(block.timestamp);

        string memory artifacts = string.concat(
            "{\n",
            '  "chainId": ',
            chainId,
            ",\n",
            '  "timestamp": ',
            timestamp,
            ",\n",
            '  "salt": "',
            vm.toString(salt),
            '",\n',
            '  "token": "',
            vm.toString(tokenAddress),
            '",\n',
            '  "governor": "',
            vm.toString(governorAddress),
            '"'
        );

        if (splitterAddress != address(0)) {
            artifacts = string.concat(artifacts, ',\n  "splitter": "', vm.toString(splitterAddress), '"');
        }

        artifacts = string.concat(artifacts, "\n}");

        string memory filename = string.concat("deployments/deployment-", chainId, "-", timestamp, ".json");
        vm.writeFile(filename, artifacts);

        console.log("Deployment artifacts saved to:", filename);
    }

    /**
     * @dev Get recipient count for a scenario
     */
    function getRecipientCount(string memory configPath, string memory scenario) external view returns (uint256) {
        string memory toml = vm.readFile(configPath);
        string[] memory names =
            vm.parseTomlStringArray(toml, string.concat(".distributions.", scenario, ".recipients[*].name"));
        return names.length;
    }

    /**
     * @dev Get recipient information
     */
    function getRecipient(string memory configPath, string memory scenario, uint256 index)
        external
        view
        returns (string memory name, address recipient, uint256 amount, string memory description)
    {
        string memory toml = vm.readFile(configPath);
        string memory scenarioPath = string.concat(".distributions.", scenario);

        string[] memory names = vm.parseTomlStringArray(toml, string.concat(scenarioPath, ".recipients[*].name"));
        address[] memory recipients =
            vm.parseTomlAddressArray(toml, string.concat(scenarioPath, ".recipients[*].address"));
        uint256[] memory amounts = vm.parseTomlUintArray(toml, string.concat(scenarioPath, ".recipients[*].amount"));
        string[] memory descriptions =
            vm.parseTomlStringArray(toml, string.concat(scenarioPath, ".recipients[*].description"));

        require(index < names.length, "Index out of bounds");

        return (names[index], recipients[index], amounts[index], descriptions[index]);
    }

    /**
     * @dev Preview deployment without executing
     */
    function previewDeployment(string memory configPath)
        external
        returns (
            string memory tokenName,
            string memory tokenSymbol,
            string memory governorName,
            uint256 recipientCount,
            uint256 totalDistribution,
            uint256 payeeCount
        )
    {
        (
            AbstractDeployer.TokenConfig memory tokenConfig,
            AbstractDeployer.GovernorConfig memory governorConfig,
            ,
            ,
            ,
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        ) = _loadConfiguration(configPath, "", "");

        tokenName = tokenConfig.name;
        tokenSymbol = tokenConfig.symbol;
        governorName = governorConfig.name;
        recipientCount = recipients.length;
        payeeCount = splitterInfo.payees.length;

        for (uint256 i = 0; i < recipients.length; i++) {
            totalDistribution += recipients[i].amount;
        }
    }
}
