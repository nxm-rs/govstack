// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "./TestHelper.sol";

contract DeployerTest is TestHelper {
    function testBasicDeployment() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        vm.recordLogs();

        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, distributions, OWNER
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress, address governorAddress, address splitterAddress, uint256 totalDistributed,) =
            extractDeploymentAddresses(logs);

        assertValidDeployment(tokenAddress, governorAddress, splitterAddress, TOKEN_NAME, GOVERNOR_NAME);

        Token token = Token(tokenAddress);
        assertEq(token.balanceOf(USER1), 1000 * 10 ** 18);
        assertEq(token.balanceOf(USER2), 2000 * 10 ** 18);
        assertEq(totalDistributed, 3000 * 10 ** 18);
        assertEq(splitterAddress, address(0)); // No splitter deployed
    }

    function testDeploymentWithSplitter() public {
        AbstractDeployer.SplitterConfig memory splitterConfig = createBasicSplitterConfig();
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        vm.recordLogs();

        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), splitterConfig, distributions, OWNER
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress, address governorAddress, address splitterAddress,,) = extractDeploymentAddresses(logs);

        assertValidDeployment(tokenAddress, governorAddress, splitterAddress, TOKEN_NAME, GOVERNOR_NAME);

        Splitter splitter = Splitter(splitterAddress);
        assertTrue(_hasPayees(splitterAddress)); // Payees are now configured during deployment

        // Verify that the splitter is properly configured
        Splitter.PayeeData[] memory payees = new Splitter.PayeeData[](2);
        payees[0] = Splitter.PayeeData({payee: PAYEE1, shares: 6000});
        payees[1] = Splitter.PayeeData({payee: PAYEE2, shares: 4000});

        bytes memory packedPayeesData = _createPackedPayeesData(payees);

        // Test that we can get payee info with the correct calldata
        (bool isPayee1, uint16 shares1) = _getPayeeInfo(splitterAddress, PAYEE1, packedPayeesData);
        assertTrue(isPayee1);
        assertEq(shares1, 6000);

        (bool isPayee2, uint16 shares2) = _getPayeeInfo(splitterAddress, PAYEE2, packedPayeesData);
        assertTrue(isPayee2);
        assertEq(shares2, 4000);

        // Verify the splitter is owned by the governor
        assertEq(splitter.owner(), governorAddress);
    }

    function testInvalidTokenConfig() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        testInvalidTokenConfigScenarios(createBasicGovernorConfig(), emptySplitterConfig, distributions, OWNER);
    }

    function testInvalidGovernorConfig() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        testInvalidGovernorConfigScenarios(createBasicTokenConfig(), emptySplitterConfig, distributions, OWNER);
    }

    function testInvalidOwner() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        testInvalidOwnerScenarios(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, distributions
        );
    }

    function testInvalidDistributions() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;

        testInvalidDistributionScenarios(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, OWNER
        );
    }

    function testInvalidSplitterConfig() public {
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        // Invalid total shares (6000 + 3000 = 9000)
        bytes memory invalidPackedData = abi.encodePacked(uint16(6000), PAYEE1, uint16(3000), PAYEE2);

        AbstractDeployer.SplitterConfig memory invalidSplitterConfig =
            AbstractDeployer.SplitterConfig({packedPayeesData: invalidPackedData});

        // Deployer should succeed, but validation will fail in TokenSplitter.updatePayees()
        vm.recordLogs();
        vm.expectRevert(Splitter.InvalidTotalShares.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), invalidSplitterConfig, distributions, OWNER
        );

        // Invalid payee (zero address)
        bytes memory zeroAddressPackedData = abi.encodePacked(uint16(6000), address(0), uint16(4000), PAYEE2);

        invalidSplitterConfig = AbstractDeployer.SplitterConfig({packedPayeesData: zeroAddressPackedData});

        vm.expectRevert(Splitter.InvalidShares.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), invalidSplitterConfig, distributions, OWNER
        );
    }

    function testValidateDistributions() public pure {
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        // Test validation using helper function
        assertValidDistributions(distributions);
    }

    function testValidateSplitterConfig() public pure {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.SplitterConfig memory validSplitterConfig = createBasicSplitterConfig();

        // Test validation using helper functions
        assertValidSplitterConfig(emptySplitterConfig);
        assertValidSplitterConfig(validSplitterConfig);

        // Test invalid calldata length
        bytes memory invalidData = abi.encodePacked(uint16(6000)); // Only 2 bytes, not 22
        AbstractDeployer.SplitterConfig memory invalidConfig =
            AbstractDeployer.SplitterConfig({packedPayeesData: invalidData});

        // Validate that this would fail (check length manually)
        assertFalse(invalidConfig.packedPayeesData.length % 22 == 0);
    }

    function testCalculateTotalDistribution() public pure {
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        // Test using helper function
        uint256 total = calculateTotalDistribution(distributions);
        assertEq(total, 3000 * 10 ** 18);

        AbstractDeployer.TokenDistribution[] memory emptyDistributions = new AbstractDeployer.TokenDistribution[](0);
        uint256 emptyTotal = calculateTotalDistribution(emptyDistributions);
        assertEq(emptyTotal, 0);
    }

    function testEmptyDistributions() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory emptyDistributions = new AbstractDeployer.TokenDistribution[](0);

        vm.recordLogs();

        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, emptyDistributions, OWNER
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress,,, uint256 totalDistributed,) = extractDeploymentAddresses(logs);

        Token token = Token(tokenAddress);
        assertEq(totalDistributed, 0);
        assertEq(token.totalSupply(), 0);
        assertEq(token.owner(), OWNER);
    }
}
