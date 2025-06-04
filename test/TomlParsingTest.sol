// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract TomlParsingTest is Test, Deploy {
    function setUp() public {
        // No need to create deployer instance since we inherit from Deploy
    }

    function testDistributionScenarioLoading() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test loading the default distribution scenario
        Deploy.RecipientInfo[] memory recipients = _loadDistributionScenario(configContent, "default");

        // Verify we got the expected number of recipients
        assertEq(recipients.length, 4, "Default scenario should have 4 recipients");

        // Verify the first recipient details
        assertEq(recipients[0].name, "DAO Treasury", "First recipient name should be DAO Treasury");
        assertEq(recipients[0].addr, 0x1111111111111111111111111111111111111111, "First recipient address should match");
        assertEq(
            vm.parseUint(recipients[0].amount), 4000000000000000000000000, "First recipient amount should be 4M tokens"
        );
        assertEq(
            recipients[0].description, "Main DAO treasury for governance", "First recipient description should match"
        );

        // Verify the second recipient details
        assertEq(recipients[1].name, "Core Contributors", "Second recipient name should be Core Contributors");
        assertEq(
            recipients[1].addr, 0x2222222222222222222222222222222222222222, "Second recipient address should match"
        );
        assertEq(
            vm.parseUint(recipients[1].amount),
            2500000000000000000000000,
            "Second recipient amount should be 2.5M tokens"
        );
        assertEq(
            recipients[1].description, "Core team and early contributors", "Second recipient description should match"
        );
    }

    function testSplitterScenarioLoading() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test loading the default splitter scenario
        Deploy.SplitterInfo memory splitterInfo = _loadSplitterScenario(configContent, "default");

        // Verify we got the expected description
        assertEq(
            splitterInfo.description, "Standard dividend splitting configuration", "Splitter description should match"
        );

        // Verify we got the expected number of payees
        assertEq(splitterInfo.payees.length, 4, "Default splitter should have 4 payees");

        // Verify the first payee details
        assertEq(
            splitterInfo.payees[0].account,
            0x1111111111111111111111111111111111111111,
            "First payee address should match"
        );
        assertEq(splitterInfo.payees[0].shares, 4000, "First payee shares should be 4000 (40%)");

        // Verify the second payee details
        assertEq(
            splitterInfo.payees[1].account,
            0x2222222222222222222222222222222222222222,
            "Second payee address should match"
        );
        assertEq(splitterInfo.payees[1].shares, 3000, "Second payee shares should be 3000 (30%)");
    }

    function testTestScenarioLoading() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test loading the test distribution scenario
        Deploy.RecipientInfo[] memory recipients = _loadDistributionScenario(configContent, "test");

        // Verify we got the expected number of recipients
        assertEq(recipients.length, 3, "Test scenario should have 3 recipients");

        // Verify the first recipient details
        assertEq(recipients[0].name, "Test Account 1", "First test recipient name should match");
        assertEq(
            recipients[0].addr, 0x1111111111111111111111111111111111111111, "First test recipient address should match"
        );
        assertEq(
            vm.parseUint(recipients[0].amount),
            1000000000000000000000,
            "First test recipient amount should be 1000 tokens"
        );
        assertEq(recipients[0].description, "Test recipient 1", "First test recipient description should match");

        // Verify the last recipient details
        assertEq(recipients[2].name, "Test Account 3", "Third test recipient name should match");
        assertEq(
            recipients[2].addr, 0x3333333333333333333333333333333333333333, "Third test recipient address should match"
        );
        assertEq(
            vm.parseUint(recipients[2].amount),
            3000000000000000000000,
            "Third test recipient amount should be 3000 tokens"
        );
        assertEq(recipients[2].description, "Test recipient 3", "Third test recipient description should match");
    }

    function testSimpleSplitterScenarioLoading() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test loading the simple splitter scenario
        Deploy.SplitterInfo memory splitterInfo = _loadSplitterScenario(configContent, "simple");

        // Verify we got the expected description
        assertEq(
            splitterInfo.description,
            "Simple 50/50 split between two parties",
            "Simple splitter description should match"
        );

        // Verify we got the expected number of payees
        assertEq(splitterInfo.payees.length, 2, "Simple splitter should have 2 payees");

        // Verify the payee details
        assertEq(
            splitterInfo.payees[0].account,
            0x1111111111111111111111111111111111111111,
            "First simple payee address should match"
        );
        assertEq(splitterInfo.payees[0].shares, 5000, "First simple payee shares should be 5000 (50%)");

        assertEq(
            splitterInfo.payees[1].account,
            0x2222222222222222222222222222222222222222,
            "Second simple payee address should match"
        );
        assertEq(splitterInfo.payees[1].shares, 5000, "Second simple payee shares should be 5000 (50%)");
    }

    function testNoneSplitterScenario() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test loading the "none" splitter scenario
        Deploy.SplitterInfo memory splitterInfo = _loadSplitterScenario(configContent, "none");

        // Verify we got empty splitter info
        assertEq(splitterInfo.description, "", "None splitter description should be empty");
        assertEq(splitterInfo.payees.length, 0, "None splitter should have 0 payees");
    }

    function testAllDistributionScenarios() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test all distribution scenarios
        string[] memory scenarios = new string[](4);
        scenarios[0] = "default";
        scenarios[1] = "startup";
        scenarios[2] = "dao";
        scenarios[3] = "test";

        uint256[] memory expectedCounts = new uint256[](4);
        expectedCounts[0] = 4; // default
        expectedCounts[1] = 4; // startup
        expectedCounts[2] = 4; // dao
        expectedCounts[3] = 3; // test

        for (uint256 i = 0; i < scenarios.length; i++) {
            Deploy.RecipientInfo[] memory recipients = _loadDistributionScenario(configContent, scenarios[i]);
            assertEq(
                recipients.length,
                expectedCounts[i],
                string.concat("Scenario ", scenarios[i], " should have correct number of recipients")
            );

            // Verify that all recipients have valid data
            for (uint256 j = 0; j < recipients.length; j++) {
                assertTrue(bytes(recipients[j].name).length > 0, "Recipient name should not be empty");
                assertTrue(recipients[j].addr != address(0), "Recipient address should not be zero");
                assertTrue(vm.parseUint(recipients[j].amount) > 0, "Recipient amount should be greater than zero");
                assertTrue(bytes(recipients[j].description).length > 0, "Recipient description should not be empty");
            }
        }
    }

    function testAllSplitterScenarios() public {
        // Read the deployment config content
        string memory configContent = vm.readFile("config/deployment.toml");

        // Test all splitter scenarios
        string[] memory scenarios = new string[](4);
        scenarios[0] = "default";
        scenarios[1] = "simple";
        scenarios[2] = "revenue_share";
        scenarios[3] = "test";

        uint256[] memory expectedCounts = new uint256[](4);
        expectedCounts[0] = 4; // default
        expectedCounts[1] = 2; // simple
        expectedCounts[2] = 4; // revenue_share
        expectedCounts[3] = 2; // test

        for (uint256 i = 0; i < scenarios.length; i++) {
            Deploy.SplitterInfo memory splitterInfo = _loadSplitterScenario(configContent, scenarios[i]);
            assertEq(
                splitterInfo.payees.length,
                expectedCounts[i],
                string.concat("Splitter scenario ", scenarios[i], " should have correct number of payees")
            );
            assertTrue(bytes(splitterInfo.description).length > 0, "Splitter description should not be empty");

            // Verify that all payees have valid data
            uint256 totalShares = 0;
            for (uint256 j = 0; j < splitterInfo.payees.length; j++) {
                assertTrue(splitterInfo.payees[j].account != address(0), "Payee address should not be zero");
                assertTrue(splitterInfo.payees[j].shares > 0, "Payee shares should be greater than zero");
                totalShares += splitterInfo.payees[j].shares;
            }

            // Verify total shares add up to 10000 (100%)
            assertEq(totalShares, 10000, string.concat("Total shares for ", scenarios[i], " should equal 10000 (100%)"));
        }
    }
}
