// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "../src/Deployer.sol";

/**
 * @title Deploy
 * @dev Advanced deployment script with TOML configuration support for Token, Governor, and TokenSplitter.
 * Supports multiple distribution scenarios, splitter configurations, network-specific settings,
 * and CREATE2 deployment with unique salts per chain.
 */
contract Deploy is Script {
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
        bool saveArtifacts;
        string customSalt;
    }

    struct RecipientInfo {
        address addr; // "address" in JSON
        string amount; // "amount" in JSON (as string to handle large numbers)
        string description; // "description" in JSON
        string name; // "name" in JSON
    }

    struct PayeeInfo {
        address account; // "account" in JSON
        uint256 shares; // "shares" in JSON
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
        uint256 proposalThreshold;
    }

    // Token decimals constant (standard ERC20 uses 18 decimals)
    uint256 private constant TOKEN_DECIMALS = 18;

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

    /**
     * @dev Main entry point for deployment script
     */
    function run() external virtual {
        runWithConfig("config/deployment.toml");
    }

    /**
     * @dev Interactive deployment with prompts for RPC URL and private key
     */
    function runInteractive() external {
        runInteractiveWithConfig("config/deployment.toml");
    }

    /**
     * @dev Interactive deployment with specific config file
     * @param configPath Path to the TOML configuration file
     */
    function runInteractiveWithConfig(string memory configPath) public {
        runInteractiveWithScenario(configPath, "", "");
    }

    /**
     * @dev Fully interactive deployment with config file selection and scenario prompts
     */
    function runInteractiveWithScenario() public {
        // Prompt for all deployment configuration interactively
        (string memory configPath, string memory distributionScenario, string memory splitterScenario) =
            _promptForFullConfiguration();

        runInteractiveWithScenario(configPath, distributionScenario, splitterScenario);
    }

    /**
     * @dev Interactive deployment with specific distribution and splitter scenarios
     * @param configPath Path to the TOML configuration file
     * @param distributionScenario Distribution scenario to use (empty for config default)
     * @param splitterScenario Splitter scenario to use (empty for config default)
     */
    function runInteractiveWithScenario(
        string memory configPath,
        string memory distributionScenario,
        string memory splitterScenario
    ) public {
        // Prompt for deployment configuration
        uint256 privateKey = _promptForPrivateKey();

        // Load configuration from TOML
        (
            AbstractDeployer.TokenConfig memory tokenConfig,
            AbstractDeployer.GovernorConfig memory governorConfig,
            NetworkConfig memory networkConfig,
            DeploymentConfig memory deploymentConfig,
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        ) = _loadConfiguration(configPath, distributionScenario, splitterScenario);

        emit ConfigurationLoaded(configPath, deploymentConfig.scenario, deploymentConfig.splitterScenario);

        // Validate network
        _validateNetwork(networkConfig);

        // Display configuration
        _displayConfiguration(tokenConfig, governorConfig, networkConfig, recipients, splitterInfo);

        // Deploy contracts with interactive configuration
        _deployWithInteractiveConfiguration(tokenConfig, governorConfig, recipients, splitterInfo, privateKey);
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
            NetworkConfig memory networkConfig,
            DeploymentConfig memory deploymentConfig,
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        ) = _loadConfiguration(configPath, distributionScenario, splitterScenario);

        emit ConfigurationLoaded(configPath, deploymentConfig.scenario, deploymentConfig.splitterScenario);

        // Validate network
        _validateNetwork(networkConfig);

        // Display configuration
        _displayConfiguration(tokenConfig, governorConfig, networkConfig, recipients, splitterInfo);

        // Deploy contracts
        _deployWithConfiguration(tokenConfig, governorConfig, recipients, splitterInfo);
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
            NetworkConfig memory networkConfig,
            DeploymentConfig memory deploymentConfig,
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        )
    {
        string memory toml = vm.readFile(configPath);

        deploymentConfig.scenario = bytes(distributionScenario).length > 0
            ? distributionScenario
            : vm.parseTomlString(toml, ".deployment.scenario");
        deploymentConfig.splitterScenario = bytes(splitterScenario).length > 0
            ? splitterScenario
            : vm.parseTomlString(toml, ".deployment.splitter_scenario");
        deploymentConfig.saveArtifacts = vm.parseTomlBool(toml, ".deployment.save_artifacts");
        deploymentConfig.customSalt = vm.parseTomlString(toml, ".deployment.custom_salt");

        // Load base configurations
        tokenConfig.name = vm.parseTomlString(toml, ".token.name");
        tokenConfig.symbol = vm.parseTomlString(toml, ".token.symbol");

        // Load time-based governor config
        TimeBasedGovernorConfig memory timeBasedConfig;
        timeBasedConfig.name = vm.parseTomlString(toml, ".governor.name");
        timeBasedConfig.votingDelayTime = vm.parseTomlString(toml, ".governor.voting_delay_time");
        timeBasedConfig.votingPeriodTime = vm.parseTomlString(toml, ".governor.voting_period_time");
        timeBasedConfig.lateQuorumExtensionTime = vm.parseTomlString(toml, ".governor.late_quorum_extension_time");
        timeBasedConfig.quorumNumerator = vm.parseTomlUint(toml, ".governor.quorum_numerator");
        timeBasedConfig.proposalThreshold = vm.parseTomlUint(toml, ".governor.proposal_threshold");

        // Apply scenario-specific overrides
        string memory scenarioTokenPath = string.concat(".distributions.", deploymentConfig.scenario, ".token");
        string memory scenarioGovernorPath = string.concat(".distributions.", deploymentConfig.scenario, ".governor");

        // Check if scenario has token overrides
        try vm.parseTomlString(toml, string.concat(scenarioTokenPath, ".name")) returns (
            string memory scenarioTokenName
        ) {
            if (bytes(scenarioTokenName).length > 0) {
                tokenConfig.name = scenarioTokenName;
            }
        } catch {}

        try vm.parseTomlString(toml, string.concat(scenarioTokenPath, ".symbol")) returns (
            string memory scenarioTokenSymbol
        ) {
            if (bytes(scenarioTokenSymbol).length > 0) {
                tokenConfig.symbol = scenarioTokenSymbol;
            }
        } catch {}

        // Check if scenario has governor overrides
        try vm.parseTomlString(toml, string.concat(scenarioGovernorPath, ".name")) returns (
            string memory scenarioGovernorName
        ) {
            if (bytes(scenarioGovernorName).length > 0) {
                timeBasedConfig.name = scenarioGovernorName;
            }
        } catch {}

        try vm.parseTomlString(toml, string.concat(scenarioGovernorPath, ".voting_delay_time")) returns (
            string memory scenarioVotingDelayTime
        ) {
            if (bytes(scenarioVotingDelayTime).length > 0) {
                timeBasedConfig.votingDelayTime = scenarioVotingDelayTime;
            }
        } catch {}

        try vm.parseTomlString(toml, string.concat(scenarioGovernorPath, ".voting_period_time")) returns (
            string memory scenarioVotingPeriodTime
        ) {
            if (bytes(scenarioVotingPeriodTime).length > 0) {
                timeBasedConfig.votingPeriodTime = scenarioVotingPeriodTime;
            }
        } catch {}

        try vm.parseTomlString(toml, string.concat(scenarioGovernorPath, ".late_quorum_extension_time")) returns (
            string memory scenarioLateQuorumExtensionTime
        ) {
            if (bytes(scenarioLateQuorumExtensionTime).length > 0) {
                timeBasedConfig.lateQuorumExtensionTime = scenarioLateQuorumExtensionTime;
            }
        } catch {}

        try vm.parseTomlUint(toml, string.concat(scenarioGovernorPath, ".quorum_numerator")) returns (
            uint256 scenarioQuorumNumerator
        ) {
            timeBasedConfig.quorumNumerator = scenarioQuorumNumerator;
        } catch {}

        try vm.parseTomlUint(toml, string.concat(scenarioGovernorPath, ".proposal_threshold")) returns (
            uint256 scenarioProposalThreshold
        ) {
            timeBasedConfig.proposalThreshold = scenarioProposalThreshold;
        } catch {}

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
        } else if (currentChainId == 84532) {
            networkKey = "base_sepolia";
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
        governorConfig.proposalThreshold = timeBasedConfig.proposalThreshold;

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
        uint256 number = vm.parseUint(numberStr);
        require(number > 0 || keccak256(bytes(numberStr)) == keccak256(bytes("0")), "Invalid number character");

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
     * @dev Load distribution scenario from TOML
     */
    function _loadDistributionScenario(string memory toml, string memory scenario)
        internal
        returns (RecipientInfo[] memory recipients)
    {
        string memory scenarioPath = string.concat(".distributions.", scenario, ".recipients");

        // Parse the recipients array directly
        bytes memory recipientsRaw = vm.parseToml(toml, scenarioPath);
        recipients = abi.decode(recipientsRaw, (RecipientInfo[]));

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

        // Load payees using struct parsing for arrays of tables
        string memory payeesPath = string.concat(scenarioPath, ".payees");

        bytes memory payeesRaw = vm.parseToml(toml, payeesPath);
        splitterInfo.payees = abi.decode(payeesRaw, (PayeeInfo[]));

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
        NetworkConfig memory networkConfig,
        RecipientInfo[] memory recipients,
        SplitterInfo memory splitterInfo
    ) internal {
        string memory configDisplay = _buildBasicConfigDisplay(tokenConfig, governorConfig, networkConfig);
        configDisplay = string.concat(configDisplay, _buildRecipientsDisplay(recipients));
        configDisplay = string.concat(configDisplay, _buildSplitterDisplay(splitterInfo));
        configDisplay =
            string.concat(configDisplay, "\n================================\n\nContinue with deployment? (y/N)");

        string memory confirmation = vm.prompt(configDisplay);
        require(
            keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("y"))
                || keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("Y")),
            "Deployment cancelled by user"
        );
    }

    function _buildBasicConfigDisplay(
        AbstractDeployer.TokenConfig memory tokenConfig,
        AbstractDeployer.GovernorConfig memory governorConfig,
        NetworkConfig memory networkConfig
    ) internal view returns (string memory) {
        uint256 blockTimeSeconds = networkConfig.blockTimeMilliseconds / 1000;

        string memory result = string.concat(
            "=== Deployment Configuration ===\n",
            "Network: ",
            networkConfig.description,
            " (Chain ID: ",
            vm.toString(block.chainid),
            ")\n",
            "Block Time: ",
            vm.toString(networkConfig.blockTimeMilliseconds),
            " ms\n"
        );

        result = string.concat(
            result,
            "\n=== Token Configuration ===\n",
            "Token Name: ",
            tokenConfig.name,
            "\n",
            "Token Symbol: ",
            tokenConfig.symbol,
            "\n"
        );

        result =
            string.concat(result, "\n=== Governor Configuration ===\n", "Governor Name: ", governorConfig.name, "\n");

        uint256 votingDelayMinutes = (governorConfig.votingDelay * blockTimeSeconds) / 60;
        uint256 votingPeriodHours = (governorConfig.votingPeriod * blockTimeSeconds) / 3600;
        uint256 extensionMinutes = (governorConfig.lateQuorumExtension * blockTimeSeconds) / 60;

        result = string.concat(
            result,
            "Voting Delay: ",
            vm.toString(governorConfig.votingDelay),
            " blocks (~",
            vm.toString(votingDelayMinutes),
            " min)\n"
        );

        result = string.concat(
            result,
            "Voting Period: ",
            vm.toString(governorConfig.votingPeriod),
            " blocks (~",
            vm.toString(votingPeriodHours),
            " hours)\n"
        );

        result = string.concat(
            result, "Quorum: ", vm.toString(governorConfig.quorumNumerator), "% of total supply required\n"
        );

        result = string.concat(
            result,
            "Late Quorum Ext: ",
            vm.toString(governorConfig.lateQuorumExtension),
            " blocks (~",
            vm.toString(extensionMinutes),
            " min)\n"
        );

        return string.concat(
            result, "\n=== Ownership Configuration ===\n", "Token Owner: Governor (deployed automatically)\n"
        );
    }

    function _buildRecipientsDisplay(RecipientInfo[] memory recipients) internal pure returns (string memory) {
        string memory display = string.concat("\n=== Recipients (", vm.toString(recipients.length), " total) ===\n");

        for (uint256 i = 0; i < recipients.length; i++) {
            display = string.concat(
                display,
                vm.toString(i + 1),
                ". ",
                recipients[i].name,
                "\n",
                "   Address: ",
                vm.toString(recipients[i].addr),
                "\n",
                "   Amount: ",
                recipients[i].amount,
                " tokens\n",
                "   Description: ",
                recipients[i].description,
                "\n"
            );
            if (i < recipients.length - 1) {
                display = string.concat(display, "\n");
            }
        }

        return display;
    }

    function _buildSplitterDisplay(SplitterInfo memory splitterInfo) internal pure returns (string memory) {
        string memory display =
            string.concat("\n\n=== Splitter Configuration ===\n", "Description: ", splitterInfo.description, "\n");

        display = string.concat(display, "Payees (", vm.toString(splitterInfo.payees.length), " total):\n");

        uint256 totalShares = 0;
        for (uint256 i = 0; i < splitterInfo.payees.length; i++) {
            totalShares += splitterInfo.payees[i].shares;
        }

        for (uint256 i = 0; i < splitterInfo.payees.length; i++) {
            uint256 percentage = (splitterInfo.payees[i].shares * 100) / totalShares;

            string memory payeeInfo =
                string.concat(vm.toString(i + 1), ". Address: ", vm.toString(splitterInfo.payees[i].account), "\n");

            payeeInfo = string.concat(
                payeeInfo,
                "   Shares: ",
                vm.toString(splitterInfo.payees[i].shares),
                " (",
                vm.toString(percentage),
                "%)\n"
            );

            display = string.concat(display, payeeInfo);
            if (i < splitterInfo.payees.length - 1) {
                display = string.concat(display, "\n");
            }
        }

        return display;
    }

    /**
     * @dev Deploy contracts with configuration
     */
    /**
     * @dev Prompt user for full deployment configuration including file and scenario selection
     * @return configPath The selected configuration file path
     * @return distributionScenario The selected distribution scenario
     * @return splitterScenario The selected splitter scenario
     */
    function _promptForFullConfiguration()
        internal
        returns (string memory configPath, string memory distributionScenario, string memory splitterScenario)
    {
        // Dynamically discover and list config files
        configPath = _promptForConfigFile();

        // Prompt for distribution scenario based on config content
        distributionScenario = _promptForDistributionScenario(configPath);

        // Prompt for splitter scenario based on config content
        splitterScenario = _promptForSplitterScenario(configPath);

        return (configPath, distributionScenario, splitterScenario);
    }

    /**
     * @dev Dynamically discover and prompt for config file selection
     * @return configPath The selected configuration file path
     */
    function _promptForConfigFile() internal returns (string memory configPath) {
        // Check if config files exist first
        if (!vm.exists("config/deployment.toml")) {
            configPath = vm.prompt(
                "=== Configuration File Selection ===\n\nWARNING: config/deployment.toml not found!\nMake sure you're running this script from the project root directory.\n\nEnter config file path manually:"
            );
            return configPath;
        }

        try vm.readDir("config") returns (Vm.DirEntry[] memory entries) {
            // Filter for .toml files
            string[] memory tomlFiles = new string[](entries.length);
            uint256 tomlCount = 0;

            for (uint256 i = 0; i < entries.length; i++) {
                if (_endsWithInternal(entries[i].path, ".toml") && !entries[i].isDir) {
                    tomlFiles[tomlCount] = entries[i].path;
                    tomlCount++;
                }
            }

            if (tomlCount == 0) {
                configPath = vm.prompt(
                    "=== Configuration File Selection ===\n\nNo .toml files found in config/ directory.\n\nEnter config file path manually:"
                );
                return configPath;
            }

            // Build file list as a single string since console.log doesn't work in interactive mode
            string memory fileList = "=== Configuration File Selection ===\n\nAvailable configuration files:\n";
            for (uint256 i = 0; i < tomlCount; i++) {
                fileList = string.concat(fileList, vm.toString(i + 1), ". ", tomlFiles[i], "\n");
            }
            fileList = string.concat(fileList, "\nSelect config file (number) or enter custom path");

            string memory choice = vm.prompt(fileList);

            // Parse choice
            uint256 choiceNum = vm.parseUint(choice);
            if (choiceNum > 0 && choiceNum <= tomlCount) {
                configPath = tomlFiles[choiceNum - 1];
            } else {
                configPath = choice; // Allow custom path
            }

            // Validate the file exists - no need for additional prompts, just proceed
            try vm.readFile(configPath) {
                // File exists, continue silently
            } catch {
                // File might not exist, but proceed anyway
            }
        } catch {
            configPath = vm.prompt(
                "=== Configuration File Selection ===\n\nCould not list config files automatically.\nCommon config files: config/deployment.toml, config/test.toml\n\nEnter config file path:"
            );
        }

        return configPath;
    }

    /**
     * @dev Discover and prompt for distribution scenario selection
     * @param configPath The configuration file to analyze
     * @return distributionScenario The selected distribution scenario
     */
    function _promptForDistributionScenario(string memory configPath)
        internal
        returns (string memory distributionScenario)
    {
        try vm.readFile(configPath) returns (string memory configContent) {
            // Parse distribution scenarios from config
            string[] memory scenarios = _parseDistributionScenariosInternal(configContent);

            if (scenarios.length == 0) {
                distributionScenario = vm.prompt(
                    "No distribution scenarios found in config file.\nEnter distribution scenario name (or press Enter for default)"
                );
                return distributionScenario;
            }

            // Build scenarios list as a single string since console.log doesn't work in interactive mode
            string memory scenariosList = string.concat(
                "=== Distribution Scenario Selection ===\n\nAvailable distribution scenarios in ", configPath, ":\n"
            );
            for (uint256 i = 0; i < scenarios.length; i++) {
                scenariosList = string.concat(scenariosList, vm.toString(i + 1), ". ", scenarios[i]);

                // Try to read scenario description
                string memory description =
                    _getScenarioDescriptionInternal(configContent, scenarios[i], "distributions");
                if (bytes(description).length > 0) {
                    scenariosList = string.concat(scenariosList, "\n   Description: ", description);
                }
                scenariosList = string.concat(scenariosList, "\n");
            }
            scenariosList = string.concat(
                scenariosList,
                vm.toString(scenarios.length + 1),
                ". (Press Enter for config default)\n\nSelect distribution scenario"
            );

            string memory choice = vm.prompt(scenariosList);

            // Parse choice
            if (bytes(choice).length == 0) {
                distributionScenario = "";
            } else {
                uint256 choiceNum = vm.parseUint(choice);
                if (choiceNum > 0 && choiceNum <= scenarios.length) {
                    distributionScenario = scenarios[choiceNum - 1];
                } else {
                    distributionScenario = choice; // Allow custom input
                }
            }
        } catch {
            distributionScenario = vm.prompt(
                "=== Distribution Scenario Selection ===\n\nCould not read config file for scenario discovery.\nEnter distribution scenario name (or press Enter for default):"
            );
        }

        return distributionScenario;
    }

    /**
     * @dev Discover and prompt for splitter scenario selection
     * @param configPath The configuration file to analyze
     * @return splitterScenario The selected splitter scenario
     */
    function _promptForSplitterScenario(string memory configPath) internal returns (string memory splitterScenario) {
        try vm.readFile(configPath) returns (string memory configContent) {
            // Parse splitter scenarios from config
            string[] memory scenarios = _parseSplitterScenariosInternal(configContent);

            // Build scenarios list as a single string since console.log doesn't work in interactive mode
            string memory scenariosList = string.concat(
                "=== Splitter Scenario Selection ===\n\nAvailable splitter scenarios in ", configPath, ":\n"
            );
            for (uint256 i = 0; i < scenarios.length; i++) {
                scenariosList = string.concat(scenariosList, vm.toString(i + 1), ". ", scenarios[i]);

                // Try to read scenario description
                string memory description = _getScenarioDescriptionInternal(configContent, scenarios[i], "splitter");
                if (bytes(description).length > 0) {
                    scenariosList = string.concat(scenariosList, "\n   Description: ", description);
                }
                scenariosList = string.concat(scenariosList, "\n");
            }
            scenariosList =
                string.concat(scenariosList, vm.toString(scenarios.length + 1), ". none - Skip splitter deployment\n");
            scenariosList = string.concat(
                scenariosList,
                vm.toString(scenarios.length + 2),
                ". (Press Enter for config default)\n\nSelect splitter scenario"
            );

            string memory choice = vm.prompt(scenariosList);

            // Parse choice
            if (bytes(choice).length == 0) {
                splitterScenario = "";
            } else {
                uint256 choiceNum = vm.parseUint(choice);
                if (choiceNum > 0 && choiceNum <= scenarios.length) {
                    splitterScenario = scenarios[choiceNum - 1];
                } else if (choiceNum == scenarios.length + 1) {
                    splitterScenario = "none";
                } else {
                    splitterScenario = choice; // Allow custom input
                }
            }
        } catch {
            splitterScenario = vm.prompt(
                "=== Splitter Scenario Selection ===\n\nCould not read config file for scenario discovery.\nEnter splitter scenario name (none to skip, or Enter for default):"
            );
        }

        return splitterScenario;
    }

    /**
     * @dev Parse distribution scenarios from config file content
     * @param configContent The TOML config file content
     * @return scenarios Array of distribution scenario names
     */
    function _parseDistributionScenariosInternal(string memory configContent)
        internal
        pure
        returns (string[] memory scenarios)
    {
        return _parseSectionScenarios(configContent, "distributions");
    }

    /**
     * @dev Parse splitter scenarios from config file content
     * @param configContent The TOML config file content
     * @return scenarios Array of splitter scenario names
     */
    function _parseSplitterScenariosInternal(string memory configContent)
        internal
        pure
        returns (string[] memory scenarios)
    {
        return _parseSectionScenarios(configContent, "splitter");
    }

    /**
     * @dev Generic parser for TOML sections
     * @param configContent The TOML config file content
     * @param sectionType The section type ("distributions" or "splitter")
     * @return scenarios Array of scenario names
     */
    function _parseSectionScenarios(string memory configContent, string memory sectionType)
        internal
        pure
        returns (string[] memory scenarios)
    {
        string[] memory tempScenarios = new string[](20); // Max 20 scenarios
        uint256 count = 0;

        bytes memory content = bytes(configContent);
        string memory pattern = string.concat("[", sectionType, ".");
        bytes memory patternBytes = bytes(pattern);

        for (uint256 i = 0; i <= content.length - patternBytes.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < patternBytes.length; j++) {
                if (content[i + j] != patternBytes[j]) {
                    matches = false;
                    break;
                }
            }

            if (matches && count < 20) {
                // Extract scenario name
                uint256 start = i + patternBytes.length;
                uint256 end = start;

                // Find the closing ]
                while (end < content.length && content[end] != 0x5D) {
                    // 0x5D is ']'
                    end++;
                }

                if (end > start && end < content.length) {
                    string memory fullScenarioName = _extractStringInternal(content, start, end);

                    // Only include direct scenarios, not nested ones (no dots in scenario name)
                    bool hasDot = false;
                    bytes memory scenarioBytes = bytes(fullScenarioName);
                    for (uint256 k = 0; k < scenarioBytes.length; k++) {
                        if (scenarioBytes[k] == 0x2E) {
                            // 0x2E is '.'
                            hasDot = true;
                            break;
                        }
                    }

                    if (!hasDot) {
                        // Check if this scenario name already exists
                        bool exists = false;
                        for (uint256 k = 0; k < count; k++) {
                            if (keccak256(bytes(tempScenarios[k])) == keccak256(bytes(fullScenarioName))) {
                                exists = true;
                                break;
                            }
                        }

                        if (!exists) {
                            tempScenarios[count] = fullScenarioName;
                            count++;
                        }
                    }
                }
            }
        }

        // Copy to properly sized array
        scenarios = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            scenarios[i] = tempScenarios[i];
        }

        return scenarios;
    }

    /**
     * @dev Extract string from bytes array between start and end indices
     * @param content The bytes array
     * @param start Start index (inclusive)
     * @param end End index (exclusive)
     * @return extracted The extracted string
     */
    function _extractStringInternal(bytes memory content, uint256 start, uint256 end)
        internal
        pure
        returns (string memory extracted)
    {
        bytes memory extractedBytes = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            extractedBytes[i] = content[start + i];
        }
        return string(extractedBytes);
    }

    /**
     * @dev Check if a string ends with a suffix
     * @param str The string to check
     * @param suffix The suffix to look for
     * @return result True if str ends with suffix
     */
    function _endsWithInternal(string memory str, string memory suffix) internal pure returns (bool result) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(suffix);

        if (strBytes.length < suffixBytes.length) {
            return false;
        }

        uint256 offset = strBytes.length - suffixBytes.length;
        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (strBytes[offset + i] != suffixBytes[i]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Get scenario description from config content
     * @param configContent The TOML config file content
     * @param scenarioName The scenario name to look for
     * @param sectionType Either "distributions" or "splitter"
     * @return description The scenario description if found
     */
    function _getScenarioDescriptionInternal(
        string memory configContent,
        string memory scenarioName,
        string memory sectionType
    ) internal pure returns (string memory description) {
        bytes memory content = bytes(configContent);
        string memory sectionHeader = string.concat("[", sectionType, ".", scenarioName, "]");
        bytes memory headerBytes = bytes(sectionHeader);

        // Find the section header
        for (uint256 i = 0; i <= content.length - headerBytes.length; i++) {
            if (_bytesMatchInternal(content, i, headerBytes)) {
                // Look for description = "..." in the section
                string memory descPattern = 'description = "';
                bytes memory descPatternBytes = bytes(descPattern);

                for (uint256 k = i + headerBytes.length; k <= content.length - descPatternBytes.length; k++) {
                    // Stop if we hit another section starting with [
                    if (content[k] == 0x5B) {
                        // '[' character
                        break;
                    }

                    if (_bytesMatchInternal(content, k, descPatternBytes)) {
                        // Extract description until closing quote
                        uint256 start = k + descPatternBytes.length;
                        uint256 end = start;

                        while (end < content.length && content[end] != 0x22) {
                            // 0x22 is '"'
                            end++;
                        }

                        if (end > start) {
                            return _extractStringInternal(content, start, end);
                        }
                        break;
                    }
                }
                break;
            }
        }

        return "";
    }

    /**
     * @dev Check if bytes match at a specific position
     * @param content The content to search in
     * @param startPos The position to start matching
     * @param pattern The pattern to match
     * @return matches True if pattern matches at startPos
     */
    function _bytesMatchInternal(bytes memory content, uint256 startPos, bytes memory pattern)
        internal
        pure
        returns (bool matches)
    {
        if (startPos + pattern.length > content.length) {
            return false;
        }

        for (uint256 i = 0; i < pattern.length; i++) {
            if (content[startPos + i] != pattern[i]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Prompt user for private key
     * @return privateKey The private key to use for deployment
     */
    function _promptForPrivateKey() internal returns (uint256 privateKey) {
        string memory privateKeyStr = vm.promptSecret(
            string.concat(
                "=== Private Key Configuration ===\n\n",
                "Enter the private key for deployment:\n",
                "WARNING: Use only a dedicated deployment wallet with minimal funds!\n",
                "NEVER use your main wallet's private key for deployments!\n\n",
                "Private Key (0x...):"
            )
        );

        // Convert hex string to uint256
        privateKey = vm.parseUint(privateKeyStr);

        // Derive wallet address from private key to show user
        address walletAddress = vm.addr(privateKey);

        vm.prompt(
            string.concat(
                "Private key configured securely.\n",
                "Wallet Address: ",
                vm.toString(walletAddress),
                "\n",
                "==================================\n\n",
                "Press Enter to continue..."
            )
        );

        return privateKey;
    }

    // Public wrappers for testing internal functions
    function _parseDistributionScenarios(string memory configContent) public pure returns (string[] memory) {
        return _parseSectionScenarios(configContent, "distributions");
    }

    function _parseSplitterScenarios(string memory configContent) public pure returns (string[] memory) {
        return _parseSectionScenarios(configContent, "splitter");
    }

    function _getScenarioDescription(string memory configContent, string memory scenarioName, string memory sectionType)
        public
        pure
        returns (string memory)
    {
        return _getScenarioDescriptionInternal(configContent, scenarioName, sectionType);
    }

    function _endsWith(string memory str, string memory suffix) public pure returns (bool) {
        return _endsWithInternal(str, suffix);
    }

    function _extractString(bytes memory content, uint256 start, uint256 end) public pure returns (string memory) {
        return _extractStringInternal(content, start, end);
    }

    function _bytesMatch(bytes memory content, uint256 startPos, bytes memory pattern) public pure returns (bool) {
        return _bytesMatchInternal(content, startPos, pattern);
    }

    /**
     * @dev Deploy contracts with non-interactive configuration
     */
    function _deployWithConfiguration(
        AbstractDeployer.TokenConfig memory tokenConfig,
        AbstractDeployer.GovernorConfig memory governorConfig,
        RecipientInfo[] memory recipients,
        SplitterInfo memory splitterInfo
    ) internal {
        // Convert recipients to AbstractDeployer.TokenDistribution format
        AbstractDeployer.TokenDistribution[] memory distributions =
            new AbstractDeployer.TokenDistribution[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            distributions[i] = AbstractDeployer.TokenDistribution({
                recipient: recipients[i].addr,
                amount: _convertTokensToWei(vm.parseUint(recipients[i].amount))
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

        // Get the deployer address from the current broadcaster
        address deployerAddress = msg.sender;

        string memory deploymentConfirm = string.concat(
            "=== Ready to Deploy ===\n",
            "Deploying from wallet: ",
            vm.toString(deployerAddress),
            "\n\n",
            "Continue with deployment? (y/N)"
        );
        string memory confirmation = vm.prompt(deploymentConfirm);
        require(
            keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("y"))
                || keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("Y")),
            "Deployment cancelled by user"
        );

        // Record logs to capture deployment events
        vm.recordLogs();

        // Start broadcasting
        vm.startBroadcast();

        // Deploy using the Deployer contract
        new Deployer(tokenConfig, governorConfig, splitterConfig, distributions);

        vm.stopBroadcast();
    }

    /**
     * @dev Deploy contracts with interactive configuration
     */
    function _deployWithInteractiveConfiguration(
        AbstractDeployer.TokenConfig memory tokenConfig,
        AbstractDeployer.GovernorConfig memory governorConfig,
        RecipientInfo[] memory recipients,
        SplitterInfo memory splitterInfo,
        uint256 privateKey
    ) internal {
        // Convert recipients to AbstractDeployer.TokenDistribution format
        AbstractDeployer.TokenDistribution[] memory distributions =
            new AbstractDeployer.TokenDistribution[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            distributions[i] = AbstractDeployer.TokenDistribution({
                recipient: recipients[i].addr,
                amount: _convertTokensToWei(vm.parseUint(recipients[i].amount))
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

        // Derive wallet address from private key to show in deployment summary
        address walletAddress = vm.addr(privateKey);

        string memory deploymentStart = string.concat(
            "=== Ready to Deploy ===\n",
            "Deploying from wallet: ",
            vm.toString(walletAddress),
            "\n\n",
            "Continue with deployment? (y/N)"
        );

        string memory confirmation = vm.prompt(deploymentStart);
        require(
            keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("y"))
                || keccak256(abi.encodePacked(confirmation)) == keccak256(abi.encodePacked("Y")),
            "Deployment cancelled by user"
        );

        // Start broadcasting with the provided private key
        vm.startBroadcast(privateKey);

        // Deploy using the Deployer contract
        new Deployer(tokenConfig, governorConfig, splitterConfig, distributions);

        vm.stopBroadcast();
    }

    /**
     * @dev Get recipient count for a scenario
     */
    function getRecipientCount(string memory configPath, string memory scenario) external view returns (uint256) {
        string memory toml = vm.readFile(configPath);
        RecipientInfo[] memory recipients = _loadDistributionScenarioView(toml, scenario);
        return recipients.length;
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
        RecipientInfo[] memory recipients = _loadDistributionScenarioView(toml, scenario);

        require(index < recipients.length, "Index out of bounds");

        return (
            recipients[index].name,
            recipients[index].addr,
            _convertTokensToWei(vm.parseUint(recipients[index].amount)),
            recipients[index].description
        );
    }

    /**
     * @dev View-only version of _loadDistributionScenario that doesn't emit events
     */
    function _loadDistributionScenarioView(string memory toml, string memory scenario)
        internal
        pure
        returns (RecipientInfo[] memory recipients)
    {
        string memory scenarioPath = string.concat(".distributions.", scenario, ".recipients");

        // Parse the recipients array directly
        bytes memory recipientsRaw = vm.parseToml(toml, scenarioPath);
        recipients = abi.decode(recipientsRaw, (RecipientInfo[]));
    }

    /**
     * @dev Preview deployment without executing
     */
    /**
     * @dev Convert token amounts (in token units) to wei (multiply by 10^18)
     * @param tokenAmount Amount in token units (e.g., 1000 for 1000 tokens)
     * @return Amount in wei (e.g., 1000000000000000000000 for 1000 tokens)
     */
    function _convertTokensToWei(uint256 tokenAmount) internal pure returns (uint256) {
        return tokenAmount * (10 ** TOKEN_DECIMALS);
    }

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
            RecipientInfo[] memory recipients,
            SplitterInfo memory splitterInfo
        ) = _loadConfiguration(configPath, "", "");

        tokenName = tokenConfig.name;
        tokenSymbol = tokenConfig.symbol;
        governorName = governorConfig.name;
        recipientCount = recipients.length;
        payeeCount = splitterInfo.payees.length;

        for (uint256 i = 0; i < recipients.length; i++) {
            totalDistribution += _convertTokensToWei(vm.parseUint(recipients[i].amount));
        }
    }
}
