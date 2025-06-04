// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../script/Deploy.s.sol";
import "../src/Deployer.sol";
import "./TestHelper.sol";

/**
 * @title TimeBasedTests
 * @dev Consolidated tests for time-based governor parameters and deployment functionality
 * Merges functionality from TimeBasedDeployment.t.sol and TimeBasedGovernor.t.sol
 */
contract TimeBasedTests is TestHelper {
    Deploy deployer;
    string constant TEST_CONFIG_PATH = "config/test.toml";

    function setUp() public {
        deployer = setupDeployerForLocalhost();
    }

    // ============ TIME CONVERSION UNIT TESTS ============

    /**
     * @dev Test time unit conversion to seconds
     */
    function testConvertUnitToSeconds() public view {
        // Test seconds
        assertEq(deployer._convertUnitToSeconds("second", 30), 30);
        assertEq(deployer._convertUnitToSeconds("seconds", 45), 45);
        assertEq(deployer._convertUnitToSeconds("sec", 60), 60);
        assertEq(deployer._convertUnitToSeconds("secs", 90), 90);
        assertEq(deployer._convertUnitToSeconds("s", 120), 120);

        // Test minutes
        assertEq(deployer._convertUnitToSeconds("minute", 1), 60);
        assertEq(deployer._convertUnitToSeconds("minutes", 5), 300);
        assertEq(deployer._convertUnitToSeconds("min", 10), 600);
        assertEq(deployer._convertUnitToSeconds("mins", 15), 900);
        assertEq(deployer._convertUnitToSeconds("m", 30), 1800);

        // Test hours
        assertEq(deployer._convertUnitToSeconds("hour", 1), 3600);
        assertEq(deployer._convertUnitToSeconds("hours", 2), 7200);
        assertEq(deployer._convertUnitToSeconds("h", 6), 21600);

        // Test days
        assertEq(deployer._convertUnitToSeconds("day", 1), 86400);
        assertEq(deployer._convertUnitToSeconds("days", 3), 259200);
        assertEq(deployer._convertUnitToSeconds("d", 7), 604800);

        // Test weeks
        assertEq(deployer._convertUnitToSeconds("week", 1), 604800);
        assertEq(deployer._convertUnitToSeconds("weeks", 2), 1209600);
        assertEq(deployer._convertUnitToSeconds("w", 4), 2419200);
    }

    /**
     * @dev Test invalid time units
     */
    function testInvalidTimeUnits() public {
        vm.expectRevert("Unsupported time unit: invalid");
        deployer._convertUnitToSeconds("invalid", 1);

        vm.expectRevert("Unsupported time unit: year");
        deployer._convertUnitToSeconds("year", 1);

        vm.expectRevert("Unsupported time unit: unknown");
        deployer._convertUnitToSeconds("unknown", 1);
    }

    /**
     * @dev Test substring extraction
     */
    function testSubstring() public view {
        string memory text = "hello world";

        assertEq(deployer._substring(text, 0, 5), "hello");
        assertEq(deployer._substring(text, 6, 11), "world");
        assertEq(deployer._substring(text, 0, 11), "hello world");
        assertEq(deployer._substring(text, 3, 8), "lo wo");
        assertEq(deployer._substring(text, 0, 0), "");
    }

    /**
     * @dev Test invalid substring ranges
     */
    function testInvalidSubstringRanges() public {
        string memory text = "hello";

        vm.expectRevert("Invalid substring range");
        deployer._substring(text, 5, 4); // start > end

        vm.expectRevert("Invalid substring range");
        deployer._substring(text, 0, 6); // end > length
    }

    /**
     * @dev Test time string parsing to blocks (updated for milliseconds)
     */
    function testParseTimeToBlocks() public view {
        // Test various time formats with 12-second blocks (Ethereum mainnet)
        uint256 blockTimeMs = ETHEREUM_BLOCK_TIME_MS; // 12000ms

        // Test basic formats
        assertEq(deployer._parseTimeToBlocks("1 day", blockTimeMs), 7200); // 86400000 / 12000 = 7200
        assertEq(deployer._parseTimeToBlocks("1 week", blockTimeMs), 50400); // 604800000 / 12000 = 50400
        assertEq(deployer._parseTimeToBlocks("1 hour", blockTimeMs), 300); // 3600000 / 12000 = 300
        assertEq(deployer._parseTimeToBlocks("30 minutes", blockTimeMs), 150); // 1800000 / 12000 = 150
        assertEq(deployer._parseTimeToBlocks("60 seconds", blockTimeMs), 5); // 60000 / 12000 = 5

        // Test ceiling division (should round up)
        assertEq(deployer._parseTimeToBlocks("13 seconds", blockTimeMs), 2); // 13000 / 12000 = 1.08... -> 2
        assertEq(deployer._parseTimeToBlocks("25 seconds", blockTimeMs), 3); // 25000 / 12000 = 2.08... -> 3
    }

    /**
     * @dev Test time parsing with different block times (updated for milliseconds)
     */
    function testParseTimeWithDifferentBlockTimes() public view {
        string memory oneDay = "1 day";

        // Ethereum mainnet (12s blocks)
        assertEq(deployer._parseTimeToBlocks(oneDay, ETHEREUM_BLOCK_TIME_MS), 7200);

        // Fast L2 network (2s blocks)
        assertEq(deployer._parseTimeToBlocks(oneDay, 2000), 43200);

        // Test network (1s blocks for fast testing)
        assertEq(deployer._parseTimeToBlocks("5 minutes", LOCALHOST_BLOCK_TIME_MS), 300);
        assertEq(deployer._parseTimeToBlocks("2 hours", LOCALHOST_BLOCK_TIME_MS), 7200);
    }

    /**
     * @dev Test invalid time formats
     */
    function testInvalidTimeFormats() public {
        uint256 blockTimeMs = ETHEREUM_BLOCK_TIME_MS;

        vm.expectRevert("Empty time string");
        deployer._parseTimeToBlocks("", blockTimeMs);

        vm.expectRevert("Invalid time format");
        deployer._parseTimeToBlocks("1day", blockTimeMs);

        vm.expectRevert("Invalid time format");
        deployer._parseTimeToBlocks("invalid", blockTimeMs);

        vm.expectRevert("Unsupported time unit: year");
        deployer._parseTimeToBlocks("1 year", blockTimeMs);

        vm.expectRevert();
        deployer._parseTimeToBlocks("abc hours", blockTimeMs);
    }

    // ============ TIME-BASED GOVERNOR CONFIGURATION TESTS ============

    /**
     * @dev Test time-based governor configuration conversion
     */
    function testTimeBasedGovernorConfigConversion() public {
        // Test with Ethereum mainnet block times
        setupEthereumNetwork();

        Deploy.TimeBasedGovernorConfig memory config = Deploy.TimeBasedGovernorConfig({
            name: "Test Governor",
            votingDelayTime: "1 day",
            votingPeriodTime: "1 week",
            lateQuorumExtensionTime: "1 hour",
            quorumNumerator: 500
        });

        // Create a mock network config for Ethereum
        Deploy.NetworkConfig memory networkConfig = Deploy.NetworkConfig({
            description: "Ethereum Mainnet",
            chainId: 1,
            blockTimeMilliseconds: ETHEREUM_BLOCK_TIME_MS,
            gasPriceGwei: 20,
            gasLimit: 8000000
        });

        // The deploy script should convert these times to blocks based on network
        AbstractDeployer.GovernorConfig memory convertedConfig =
            deployer._convertTimeBasedGovernorConfig(config, networkConfig);

        // With 12-second blocks:
        // 1 day = 86400 seconds = 7200 blocks
        // 1 week = 604800 seconds = 50400 blocks
        // 1 hour = 3600 seconds = 300 blocks
        assertEq(convertedConfig.votingDelay, 7200);
        assertEq(convertedConfig.votingPeriod, 50400);
        assertEq(convertedConfig.lateQuorumExtension, 300);
        assertEq(convertedConfig.quorumNumerator, 500);
    }

    /**
     * @dev Test conversion across different networks
     */
    function testConversionAcrossNetworks() public {
        Deploy.TimeBasedGovernorConfig memory config = Deploy.TimeBasedGovernorConfig({
            name: "Multi Network Governor",
            votingDelayTime: "2 days",
            votingPeriodTime: "1 week",
            lateQuorumExtensionTime: "6 hours",
            quorumNumerator: 1000
        });

        // Test Ethereum (12s blocks)
        setupEthereumNetwork();
        Deploy.NetworkConfig memory ethNetwork = Deploy.NetworkConfig({
            description: "Ethereum Mainnet",
            chainId: 1,
            blockTimeMilliseconds: ETHEREUM_BLOCK_TIME_MS,
            gasPriceGwei: 20,
            gasLimit: 8000000
        });
        AbstractDeployer.GovernorConfig memory ethConfig = deployer._convertTimeBasedGovernorConfig(config, ethNetwork);
        assertEq(ethConfig.votingDelay, 14400); // 2 days = 172800s = 14400 blocks
        assertEq(ethConfig.votingPeriod, 50400); // 1 week = 604800s = 50400 blocks
        assertEq(ethConfig.lateQuorumExtension, 1800); // 6 hours = 21600s = 1800 blocks

        // Test Fast L2 network (2s blocks)
        setupFastL2Network();
        Deploy.NetworkConfig memory fastL2Network = Deploy.NetworkConfig({
            description: "Fast L2 Network",
            chainId: 11155111,
            blockTimeMilliseconds: 2000,
            gasPriceGwei: 1,
            gasLimit: 15000000
        });
        AbstractDeployer.GovernorConfig memory fastL2Config =
            deployer._convertTimeBasedGovernorConfig(config, fastL2Network);
        assertEq(fastL2Config.lateQuorumExtension, 10800); // 6 hours = 21600s = 10800 blocks
    }

    /**
     * @dev Test time parameters converted event emission
     */
    function testTimeParametersConvertedEvent() public {
        setupEthereumNetwork(); // Ethereum mainnet

        // Expect the event to be emitted with converted values
        expectTimeParametersConverted(
            "1 day",
            7200, // 1 day in 12s blocks
            "1 week",
            50400, // 1 week in 12s blocks
            "1 hour",
            300 // 1 hour in 12s blocks
        );

        Deploy.TimeBasedGovernorConfig memory config = Deploy.TimeBasedGovernorConfig({
            name: "Event Test Governor",
            votingDelayTime: "1 day",
            votingPeriodTime: "1 week",
            lateQuorumExtensionTime: "1 hour",
            quorumNumerator: 500
        });

        Deploy.NetworkConfig memory networkConfig = Deploy.NetworkConfig({
            description: "Ethereum Mainnet",
            chainId: 1,
            blockTimeMilliseconds: ETHEREUM_BLOCK_TIME_MS,
            gasPriceGwei: 20,
            gasLimit: 8000000
        });

        deployer._convertTimeBasedGovernorConfig(config, networkConfig);
    }

    // ============ INTEGRATION TESTS ============

    /**
     * @dev Test edge cases in time conversion
     */
    function testTimeConversionEdgeCases() public view {
        uint256 blockTimeMs = ETHEREUM_BLOCK_TIME_MS;

        // Test very small times
        assertEq(deployer._parseTimeToBlocks("1 second", blockTimeMs), 1); // 1000ms / 12000ms = 0.083... -> 1 (ceiling)
        assertEq(deployer._parseTimeToBlocks("5 seconds", blockTimeMs), 1); // 5000ms / 12000ms = 0.417... -> 1 (ceiling)
        assertEq(deployer._parseTimeToBlocks("12 seconds", blockTimeMs), 1); // 12000ms / 12000ms = 1
        assertEq(deployer._parseTimeToBlocks("13 seconds", blockTimeMs), 2); // 13000ms / 12000ms = 1.083... -> 2 (ceiling)

        // Test very large times
        assertEq(deployer._parseTimeToBlocks("365 days", blockTimeMs), 2628000); // 365 * 86400 * 1000 / 12000 = 2628000

        // Test fractional results that should round up
        assertEq(deployer._parseTimeToBlocks("1 second", 3000), 1); // 1000 / 3000 = 0.33... -> 1
        assertEq(deployer._parseTimeToBlocks("2 seconds", 3000), 1); // 2000 / 3000 = 0.67... -> 1
        assertEq(deployer._parseTimeToBlocks("3 seconds", 3000), 1); // 3000 / 3000 = 1
        assertEq(deployer._parseTimeToBlocks("4 seconds", 3000), 2); // 4000 / 3000 = 1.33... -> 2
    }

    /**
     * @dev Test realistic deployment timing scenarios
     */
    function testRealisticDeploymentTiming() public view {
        // Test realistic DAO governance scenarios
        TimeTestCase[] memory realisticCases = new TimeTestCase[](5);
        realisticCases[0] = TimeTestCase("2 days", 172800, "Standard voting delay");
        realisticCases[1] = TimeTestCase("1 week", 604800, "Standard voting period");
        realisticCases[2] = TimeTestCase("6 hours", 21600, "Late quorum extension");
        realisticCases[3] = TimeTestCase("3 days", 259200, "Extended voting delay");
        realisticCases[4] = TimeTestCase("2 weeks", 1209600, "Extended voting period");

        uint256 blockTimeMs = ETHEREUM_BLOCK_TIME_MS;

        for (uint256 i = 0; i < realisticCases.length; i++) {
            TimeTestCase memory testCase = realisticCases[i];
            uint256 expectedBlocks = (testCase.expectedSeconds * 1000 + blockTimeMs - 1) / blockTimeMs; // ceiling division
            uint256 actualBlocks = deployer._parseTimeToBlocks(testCase.timeString, blockTimeMs);

            assertEq(actualBlocks, expectedBlocks, string(abi.encodePacked("Failed for case: ", testCase.description)));
        }
    }

    /**
     * @dev Test edge cases with various time formats and edge conditions
     */
    function testEdgeCases() public view {
        uint256 blockTimeMs = LOCALHOST_BLOCK_TIME_MS; // 1000ms

        // Test minimum values
        assertEq(deployer._parseTimeToBlocks("1 second", blockTimeMs), 1);

        // Test large values
        assertEq(deployer._parseTimeToBlocks("100 days", blockTimeMs), 8640000);

        // Test various combinations
        assertEq(deployer._parseTimeToBlocks("1 day", blockTimeMs), 86400);
        assertEq(deployer._parseTimeToBlocks("7 days", blockTimeMs), 604800);
        assertEq(deployer._parseTimeToBlocks("24 hours", blockTimeMs), 86400);
        assertEq(deployer._parseTimeToBlocks("1440 minutes", blockTimeMs), 86400);
    }

    /**
     * @dev Test realistic governance scenarios across networks
     */
    function testRealisticGovernanceScenarios() public view {
        // Test a realistic DAO configuration across different networks
        ConversionTestCase[] memory scenarios = new ConversionTestCase[](3);
        scenarios[0] = ConversionTestCase("2 days", ETHEREUM_BLOCK_TIME_MS, 14400, "Ethereum 2-day voting delay");
        scenarios[1] = ConversionTestCase("1 week", 2000, 302400, "Fast L2 1-week voting period");
        scenarios[2] = ConversionTestCase("6 hours", LOCALHOST_BLOCK_TIME_MS, 21600, "Fast network 6-hour extension");

        for (uint256 i = 0; i < scenarios.length; i++) {
            ConversionTestCase memory scenario = scenarios[i];
            uint256 actualBlocks = deployer._parseTimeToBlocks(scenario.timeString, scenario.blockTimeMs);

            assertEq(
                actualBlocks,
                scenario.expectedBlocks,
                string(abi.encodePacked("Failed for scenario: ", scenario.description))
            );
        }
    }

    /**
     * @dev Test consistency across different block times
     */
    function testConsistencyAcrossBlockTimes() public view {
        string memory timeString = "1 day";
        uint256 expectedSeconds = SECONDS_PER_DAY;

        // Test that the time conversion is consistent across different block times
        uint256[] memory blockTimes = new uint256[](5);
        blockTimes[0] = ETHEREUM_BLOCK_TIME_MS; // 12000
        blockTimes[1] = 2000; // Fast L2
        blockTimes[2] = LOCALHOST_BLOCK_TIME_MS; // 1000
        blockTimes[3] = 2000; // Fast L2
        blockTimes[4] = LOCALHOST_BLOCK_TIME_MS; // 1000

        for (uint256 i = 0; i < blockTimes.length; i++) {
            uint256 blockTimeMs = blockTimes[i];
            uint256 blocks = deployer._parseTimeToBlocks(timeString, blockTimeMs);
            uint256 convertedSeconds = (blocks * blockTimeMs) / 1000;

            // The converted time should be >= original time (due to ceiling)
            assertGe(convertedSeconds, expectedSeconds, "Converted time should not be less than original");

            // The difference should be less than one block time
            uint256 blockTimeSeconds = blockTimeMs / 1000;
            assertLt(convertedSeconds - expectedSeconds, blockTimeSeconds, "Difference should be less than one block");
        }
    }
}
