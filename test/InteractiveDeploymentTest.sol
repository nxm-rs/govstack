// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../script/Deploy.s.sol";

/**
 * @title InteractiveDeploymentTest
 * @dev Tests for the interactive deployment functionality in Deploy.s.sol
 * Note: These tests focus on the parsing and discovery logic, not the actual interactive prompts
 */
contract InteractiveDeploymentTest is Test {
    Deploy deployer;

    // Test config file content
    string constant TEST_CONFIG_CONTENT = "[token]\n" "name = \"Test Token\"\n" "symbol = \"TEST\"\n"
        "initial_supply = 0\n" "\n" "[governor]\n" "name = \"Test Governor\"\n" "voting_delay_time = \"1 day\"\n"
        "voting_period_time = \"1 week\"\n" "late_quorum_extension_time = \"1 hour\"\n" "quorum_numerator = 500\n" "\n"
        "[treasury]\n" "address = \"0x1234567890123456789012345678901234567890\"\n" "\n" "[distributions.default]\n"
        "description = \"Standard governance token distribution\"\n" "\n" "[[distributions.default.recipients]]\n"
        "name = \"DAO Treasury\"\n" "address = \"0x1111111111111111111111111111111111111111\"\n"
        "amount = \"4000000000000000000000000\"\n" "description = \"Main DAO treasury\"\n" "\n"
        "[distributions.startup]\n" "description = \"Early stage startup token distribution\"\n" "\n"
        "[[distributions.startup.recipients]]\n" "name = \"Founders\"\n"
        "address = \"0x5555555555555555555555555555555555555555\"\n" "amount = \"3000000000000000000000000\"\n"
        "description = \"Founder allocation\"\n" "\n" "[distributions.dao]\n"
        "description = \"Decentralized autonomous organization distribution\"\n" "\n"
        "[[distributions.dao.recipients]]\n" "name = \"DAO Treasury\"\n"
        "address = \"0xDadaDadadadadadaDaDadAdaDADAdadAdADaDADA\"\n" "amount = \"5000000000000000000000000\"\n"
        "description = \"Main DAO treasury\"\n" "\n" "[splitter.default]\n"
        "description = \"Standard dividend splitting configuration\"\n" "\n" "[[splitter.default.payees]]\n"
        "account = \"0x1111111111111111111111111111111111111111\"\n" "shares = 4000\n" "\n" "[splitter.simple]\n"
        "description = \"Simple 50/50 split between two parties\"\n" "\n" "[[splitter.simple.payees]]\n"
        "account = \"0x1111111111111111111111111111111111111111\"\n" "shares = 5000\n" "\n" "[splitter.revenue_share]\n"
        "description = \"Revenue sharing among stakeholders\"\n" "\n" "[[splitter.revenue_share.payees]]\n"
        "account = \"0x1111111111111111111111111111111111111111\"\n" "shares = 5000\n" "\n" "[deployment]\n"
        "scenario = \"default\"\n" "splitter_scenario = \"default\"\n" "verify = true\n" "save_artifacts = true\n";

    function setUp() public {
        deployer = new Deploy();
    }

    function testConfigFileDiscovery() public view {
        // Test that readDir works and finds our test files
        Vm.DirEntry[] memory entries = vm.readDir("config");

        bool foundTestConfig = false;
        bool foundMinimal = false;

        for (uint256 i = 0; i < entries.length; i++) {
            string memory filename = entries[i].path;
            if (deployer._endsWith(filename, "deployment.toml")) {
                foundTestConfig = true;
            }
            if (deployer._endsWith(filename, "test.toml")) {
                foundMinimal = true;
            }
        }

        assertTrue(foundTestConfig, "Should find deployment.toml");
        assertTrue(foundMinimal, "Should find test.toml");
    }

    function testDistributionScenarioParsing() public view {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test parsing distribution scenarios
        string[] memory scenarios = deployer._parseDistributionScenarios(configContent);

        assertEq(scenarios.length, 4, "Should find 4 distribution scenarios");

        // Check that we found the expected scenarios
        bool foundDefault = false;
        bool foundStartup = false;
        bool foundDao = false;
        bool foundTest = false;

        for (uint256 i = 0; i < scenarios.length; i++) {
            if (keccak256(bytes(scenarios[i])) == keccak256("default")) {
                foundDefault = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("startup")) {
                foundStartup = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("dao")) {
                foundDao = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("test")) {
                foundTest = true;
            }
        }

        assertTrue(foundDefault, "Should find 'default' distribution scenario");
        assertTrue(foundStartup, "Should find 'startup' distribution scenario");
        assertTrue(foundDao, "Should find 'dao' distribution scenario");
        assertTrue(foundTest, "Should find 'test' distribution scenario");
    }

    function testSplitterScenarioParsing() public view {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test parsing splitter scenarios
        string[] memory scenarios = deployer._parseSplitterScenarios(configContent);

        assertEq(scenarios.length, 4, "Should find 4 splitter scenarios");

        // Check that we found the expected scenarios
        bool foundDefault = false;
        bool foundSimple = false;
        bool foundRevenueShare = false;
        bool foundTest = false;

        for (uint256 i = 0; i < scenarios.length; i++) {
            if (keccak256(bytes(scenarios[i])) == keccak256("default")) {
                foundDefault = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("simple")) {
                foundSimple = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("revenue_share")) {
                foundRevenueShare = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("test")) {
                foundTest = true;
            }
        }

        assertTrue(foundDefault, "Should find 'default' splitter scenario");
        assertTrue(foundSimple, "Should find 'simple' splitter scenario");
        assertTrue(foundRevenueShare, "Should find 'revenue_share' splitter scenario");
        assertTrue(foundTest, "Should find 'test' splitter scenario");
    }

    function testScenarioDescriptionExtraction() public view {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test extracting distribution scenario descriptions
        string memory defaultDesc = deployer._getScenarioDescription(configContent, "default", "distributions");
        assertEq(
            defaultDesc,
            "Standard governance token distribution",
            "Should extract correct default distribution description"
        );

        string memory startupDesc = deployer._getScenarioDescription(configContent, "startup", "distributions");
        assertEq(
            startupDesc,
            "Early stage startup token distribution",
            "Should extract correct startup distribution description"
        );

        string memory daoDesc = deployer._getScenarioDescription(configContent, "dao", "distributions");
        assertEq(
            daoDesc,
            "Decentralized autonomous organization distribution",
            "Should extract correct dao distribution description"
        );

        // Test extracting splitter scenario descriptions
        string memory splitterDefaultDesc = deployer._getScenarioDescription(configContent, "default", "splitter");
        assertEq(
            splitterDefaultDesc,
            "Standard dividend splitting configuration",
            "Should extract correct default splitter description"
        );

        string memory simpleDesc = deployer._getScenarioDescription(configContent, "simple", "splitter");
        assertEq(
            simpleDesc, "Simple 50/50 split between two parties", "Should extract correct simple splitter description"
        );

        string memory revenueDesc = deployer._getScenarioDescription(configContent, "revenue_share", "splitter");
        assertEq(
            revenueDesc,
            "Revenue sharing among stakeholders",
            "Should extract correct revenue_share splitter description"
        );
    }

    function testEmptyConfigFileParsing() public view {
        // Test parsing with just the TEST_CONFIG_CONTENT that has no splitter scenarios
        string memory emptyConfig = "[token]\nname = \"Empty\"\nsymbol = \"EMP\"\ninitial_supply = 0\n";

        string[] memory distScenarios = deployer._parseDistributionScenarios(emptyConfig);
        string[] memory splitterScenarios = deployer._parseSplitterScenarios(emptyConfig);

        assertEq(distScenarios.length, 0, "Empty config should have no distribution scenarios");
        assertEq(splitterScenarios.length, 0, "Empty config should have no splitter scenarios");
    }

    function testMinimalConfigParsing() public view {
        // Test parsing test.toml which has only test scenarios
        string memory configContent = vm.readFile("config/test.toml");

        string[] memory distScenarios = deployer._parseDistributionScenarios(configContent);

        // test.toml should have only 1 distribution scenario: "test"
        assertEq(distScenarios.length, 1, "Test config should have 1 distribution scenario");
        assertEq(distScenarios[0], "test", "Should find 'test' distribution scenario");

        string memory testDesc = deployer._getScenarioDescription(configContent, "test", "distributions");
        assertEq(testDesc, "Simple test distribution", "Should extract correct test distribution description");
    }

    function testEndsWith() public view {
        // Test the _endsWith helper function
        assertTrue(deployer._endsWith("test.toml", ".toml"), "Should detect .toml ending");
        assertTrue(deployer._endsWith("deployment.toml", ".toml"), "Should detect .toml ending in longer string");
        assertFalse(deployer._endsWith("test.txt", ".toml"), "Should not detect .toml in .txt file");
        assertFalse(deployer._endsWith("toml", ".toml"), "Should not match when string is shorter than suffix");
        assertFalse(deployer._endsWith("test", ".toml"), "Should not match when no suffix present");
    }

    function testExtractString() public view {
        // Test the _extractString helper function
        bytes memory testData = bytes("Hello World!");

        string memory extracted = deployer._extractString(testData, 0, 5);
        assertEq(extracted, "Hello", "Should extract 'Hello' from beginning");

        string memory extracted2 = deployer._extractString(testData, 6, 11);
        assertEq(extracted2, "World", "Should extract 'World' from middle");

        string memory extracted3 = deployer._extractString(testData, 11, 12);
        assertEq(extracted3, "!", "Should extract single character");
    }

    function testBytesMatch() public view {
        // Test the _bytesMatch helper function
        bytes memory content = bytes("This is a test string for pattern matching");
        bytes memory pattern1 = bytes("This");
        bytes memory pattern2 = bytes("test");
        bytes memory pattern3 = bytes("notfound");

        assertTrue(deployer._bytesMatch(content, 0, pattern1), "Should match 'This' at position 0");
        assertTrue(deployer._bytesMatch(content, 10, pattern2), "Should match 'test' at position 10");
        assertFalse(deployer._bytesMatch(content, 0, pattern2), "Should not match 'test' at position 0");
        assertFalse(deployer._bytesMatch(content, 0, pattern3), "Should not match 'notfound' anywhere");

        // Test edge cases
        assertFalse(deployer._bytesMatch(content, content.length, pattern1), "Should not match at end position");
        assertFalse(
            deployer._bytesMatch(content, content.length - 1, pattern1),
            "Should not match when pattern extends beyond content"
        );
    }

    function testParseStringToUint() public {
        // Test the _parseStringToUint helper function
        assertEq(deployer._parseStringToUint("1"), 1, "Should parse '1' to 1");
        assertEq(deployer._parseStringToUint("123"), 123, "Should parse '123' to 123");
        assertEq(deployer._parseStringToUint("0"), 0, "Should parse '0' to 0");

        // Test invalid inputs (should revert)
        assertEq(deployer._parseStringToUint(""), 0, "Should return 0 for empty string");

        vm.expectRevert("Invalid number character");
        deployer._parseStringToUint("abc");

        vm.expectRevert("Invalid number character");
        deployer._parseStringToUint("12abc");
    }

    function testDuplicateScenarioHandling() public view {
        // Create a config with duplicate scenario names (should be deduplicated)
        string memory configWithDuplicates = "[distributions.test]\n" "description = \"First test\"\n" "\n"
            "[distributions.test]\n" "description = \"Second test\"\n" "\n" "[distributions.prod]\n"
            "description = \"Production\"\n";

        string[] memory scenarios = deployer._parseDistributionScenarios(configWithDuplicates);

        // Should only find unique scenarios
        assertEq(scenarios.length, 2, "Should deduplicate scenarios and find 2 unique ones");

        bool foundTest = false;
        bool foundProd = false;

        for (uint256 i = 0; i < scenarios.length; i++) {
            if (keccak256(bytes(scenarios[i])) == keccak256("test")) {
                foundTest = true;
            } else if (keccak256(bytes(scenarios[i])) == keccak256("prod")) {
                foundProd = true;
            }
        }

        assertTrue(foundTest, "Should find 'test' scenario");
        assertTrue(foundProd, "Should find 'prod' scenario");
    }

    function testComplexScenarioNames() public view {
        // Test scenarios with complex names (underscores, numbers, etc.)
        string memory complexConfig = "[distributions.scenario_1]\n"
            "description = \"Scenario with underscore and number\"\n" "\n" "[distributions.test123]\n"
            "description = \"Scenario with numbers\"\n" "\n"
            "[distributions.long_scenario_name_with_many_underscores]\n" "description = \"Very long scenario name\"\n"
            "\n" "[splitter.split_50_50]\n" "description = \"Split with numbers\"\n";

        string[] memory distScenarios = deployer._parseDistributionScenarios(complexConfig);
        string[] memory splitterScenarios = deployer._parseSplitterScenarios(complexConfig);

        assertEq(distScenarios.length, 3, "Should find 3 distribution scenarios with complex names");
        assertEq(splitterScenarios.length, 1, "Should find 1 splitter scenario with complex name");

        // Check specific complex names
        bool foundLongName = false;
        for (uint256 i = 0; i < distScenarios.length; i++) {
            if (keccak256(bytes(distScenarios[i])) == keccak256("long_scenario_name_with_many_underscores")) {
                foundLongName = true;
                break;
            }
        }
        assertTrue(foundLongName, "Should find long scenario name with underscores");

        assertEq(
            splitterScenarios[0], "split_50_50", "Should correctly parse splitter name with numbers and underscores"
        );
    }

    function testMissingDescription() public view {
        // Test scenario without description
        string memory configWithoutDesc = "[distributions.nodesc]\n" "\n" "[[distributions.nodesc.recipients]]\n"
            "name = \"Test\"\n" "address = \"0x1111111111111111111111111111111111111111\"\n" "amount = \"1000\"\n";

        string[] memory scenarios = deployer._parseDistributionScenarios(configWithoutDesc);
        assertEq(scenarios.length, 1, "Should find scenario even without description");
        assertEq(scenarios[0], "nodesc", "Should find 'nodesc' scenario");

        string memory desc = deployer._getScenarioDescription(configWithoutDesc, "nodesc", "distributions");
        assertEq(desc, "", "Should return empty string for missing description");
    }

    function testNonExistentScenarioDescription() public view {
        string memory configContent = vm.readFile("config/deployment.toml");

        string memory desc = deployer._getScenarioDescription(configContent, "nonexistent", "distributions");
        assertEq(desc, "", "Should return empty string for non-existent scenario");

        string memory desc2 = deployer._getScenarioDescription(configContent, "default", "nonexistent_section");
        assertEq(desc2, "", "Should return empty string for non-existent section type");
    }

    function testFullConfigDiscoveryWorkflow() public view {
        // Test the complete workflow: discover files -> read content -> parse scenarios -> extract descriptions

        // 1. Discover config files
        Vm.DirEntry[] memory entries = vm.readDir("config");
        assertTrue(entries.length >= 3, "Should find at least 3 config files");

        // 2. Find deployment.toml
        string memory deploymentPath = "";
        for (uint256 i = 0; i < entries.length; i++) {
            if (deployer._endsWith(entries[i].path, "deployment.toml")) {
                deploymentPath = entries[i].path;
                break;
            }
        }
        assertTrue(bytes(deploymentPath).length > 0, "Should find deployment.toml");

        // 3. Read and parse the config
        string memory configContent = vm.readFile(deploymentPath);
        string[] memory distScenarios = deployer._parseDistributionScenarios(configContent);
        string[] memory splitterScenarios = deployer._parseSplitterScenarios(configContent);

        // 4. Verify expected scenarios are found
        assertTrue(distScenarios.length >= 4, "Should find at least 4 distribution scenarios");
        assertTrue(splitterScenarios.length >= 4, "Should find at least 4 splitter scenarios");

        // 5. Verify scenario descriptions can be extracted
        string memory defaultDesc = deployer._getScenarioDescription(configContent, "default", "distributions");
        assertTrue(bytes(defaultDesc).length > 0, "Should extract default distribution description");

        string memory splitterDefaultDesc = deployer._getScenarioDescription(configContent, "default", "splitter");
        assertTrue(bytes(splitterDefaultDesc).length > 0, "Should extract default splitter description");

        // 6. Verify specific scenarios exist
        bool foundDefault = false;
        bool foundDao = false;
        for (uint256 i = 0; i < distScenarios.length; i++) {
            if (keccak256(bytes(distScenarios[i])) == keccak256("default")) {
                foundDefault = true;
            } else if (keccak256(bytes(distScenarios[i])) == keccak256("dao")) {
                foundDao = true;
            }
        }
        assertTrue(foundDefault, "Should find 'default' distribution scenario");
        assertTrue(foundDao, "Should find 'dao' distribution scenario");
    }

    function testConfigFileFilteringAndParsing() public view {
        // Test that only .toml files are selected and parsed correctly
        Vm.DirEntry[] memory entries = vm.readDir("config");

        uint256 tomlCount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (deployer._endsWith(entries[i].path, ".toml") && !entries[i].isDir) {
                tomlCount++;

                // Each .toml file should be readable and parseable
                string memory configContent = vm.readFile(entries[i].path);
                assertTrue(bytes(configContent).length > 0, "Config file should not be empty");

                // Should be able to parse without reverting
                string[] memory distScenarios = deployer._parseDistributionScenarios(configContent);
                string[] memory splitterScenarios = deployer._parseSplitterScenarios(configContent);

                // At minimum, files should parse without error (may have 0 scenarios)
                assertTrue(distScenarios.length >= 0, "Should parse distribution scenarios");
                assertTrue(splitterScenarios.length >= 0, "Should parse splitter scenarios");
            }
        }

        assertEq(tomlCount, 3, "Should find exactly 3 .toml files");
    }

    function testFallbackConfigValidation() public view {
        // Test that common config files exist and are readable (fallback scenario)
        string[] memory commonConfigs = new string[](3);
        commonConfigs[0] = "config/deployment.toml";
        commonConfigs[1] = "config/test.toml";
        commonConfigs[2] = "config/gas-test.toml";

        for (uint256 i = 0; i < commonConfigs.length; i++) {
            // Each common config should be readable
            string memory configContent = vm.readFile(commonConfigs[i]);
            assertTrue(
                bytes(configContent).length > 0, string.concat("Config file should not be empty: ", commonConfigs[i])
            );

            // Should be parseable
            string[] memory distScenarios = deployer._parseDistributionScenarios(configContent);
            string[] memory splitterScenarios = deployer._parseSplitterScenarios(configContent);

            // Should parse without error
            assertTrue(
                distScenarios.length >= 0, string.concat("Should parse distribution scenarios: ", commonConfigs[i])
            );
            assertTrue(
                splitterScenarios.length >= 0, string.concat("Should parse splitter scenarios: ", commonConfigs[i])
            );
        }
    }
}
