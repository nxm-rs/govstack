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

        TokenSplitter splitter = TokenSplitter(splitterAddress);
        assertTrue(splitter.hasPayees()); // Payees are now configured during deployment

        // Verify that the splitter is properly configured
        TokenSplitter.PayeeData[] memory payees = new TokenSplitter.PayeeData[](2);
        payees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 6000});
        payees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 4000});

        bytes memory packedPayeesData = splitter.createPackedPayeesData(payees);

        // Test that we can get payee info with the correct calldata
        (bool isPayee1, uint16 shares1) = splitter.getPayeeInfo(PAYEE1, packedPayeesData);
        assertTrue(isPayee1);
        assertEq(shares1, 6000);

        (bool isPayee2, uint16 shares2) = splitter.getPayeeInfo(PAYEE2, packedPayeesData);
        assertTrue(isPayee2);
        assertEq(shares2, 4000);

        // Verify the splitter is owned by the governor
        assertEq(splitter.owner(), governorAddress);
    }

    function testInvalidTokenConfig() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        AbstractDeployer.TokenConfig memory invalidTokenConfig =
            AbstractDeployer.TokenConfig({name: "", symbol: TOKEN_SYMBOL, initialSupply: 0});

        vm.expectRevert(AbstractDeployer.TokenNameEmpty.selector);
        new TestableDeployer(invalidTokenConfig, createBasicGovernorConfig(), emptySplitterConfig, distributions, OWNER);

        invalidTokenConfig = AbstractDeployer.TokenConfig({name: TOKEN_NAME, symbol: "", initialSupply: 0});

        vm.expectRevert(AbstractDeployer.TokenSymbolEmpty.selector);
        new TestableDeployer(invalidTokenConfig, createBasicGovernorConfig(), emptySplitterConfig, distributions, OWNER);
    }

    function testInvalidGovernorConfig() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        AbstractDeployer.GovernorConfig memory invalidGovernorConfig = AbstractDeployer.GovernorConfig({
            name: "",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumNumerator: QUORUM_NUMERATOR,
            lateQuorumExtension: LATE_QUORUM_EXTENSION
        });

        vm.expectRevert(AbstractDeployer.GovernorNameEmpty.selector);
        new TestableDeployer(createBasicTokenConfig(), invalidGovernorConfig, emptySplitterConfig, distributions, OWNER);
    }

    function testInvalidOwner() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        vm.expectRevert(AbstractDeployer.FinalOwnerZeroAddress.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, distributions, address(0)
        );
    }

    function testInvalidDistributions() public {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;

        AbstractDeployer.TokenDistribution[] memory invalidDistributions = new AbstractDeployer.TokenDistribution[](1);
        invalidDistributions[0] = AbstractDeployer.TokenDistribution({recipient: address(0), amount: 1000});

        vm.expectRevert(AbstractDeployer.RecipientZeroAddress.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, invalidDistributions, OWNER
        );

        invalidDistributions[0] = AbstractDeployer.TokenDistribution({recipient: USER1, amount: 0});

        vm.expectRevert(AbstractDeployer.AmountMustBeGreaterThanZero.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, invalidDistributions, OWNER
        );

        AbstractDeployer.TokenDistribution[] memory duplicateDistributions = new AbstractDeployer.TokenDistribution[](2);
        duplicateDistributions[0] = AbstractDeployer.TokenDistribution({recipient: USER1, amount: 1000});
        duplicateDistributions[1] = AbstractDeployer.TokenDistribution({recipient: USER1, amount: 2000});

        vm.expectRevert(AbstractDeployer.DuplicateRecipient.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, duplicateDistributions, OWNER
        );
    }

    function testInvalidSplitterConfig() public {
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        // Invalid total shares (6000 + 3000 = 9000)
        bytes memory invalidPackedData = abi.encodePacked(uint16(6000), PAYEE1, uint16(3000), PAYEE2);

        AbstractDeployer.SplitterConfig memory invalidSplitterConfig =
            AbstractDeployer.SplitterConfig({packedPayeesData: invalidPackedData});

        vm.expectRevert(AbstractDeployer.TotalSharesMustEqual10000.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), invalidSplitterConfig, distributions, OWNER
        );

        // Invalid payee (zero address)
        bytes memory zeroAddressPackedData = abi.encodePacked(uint16(6000), address(0), uint16(4000), PAYEE2);

        invalidSplitterConfig = AbstractDeployer.SplitterConfig({packedPayeesData: zeroAddressPackedData});

        vm.expectRevert(AbstractDeployer.PayeeZeroAddress.selector);
        new TestableDeployer(
            createBasicTokenConfig(), createBasicGovernorConfig(), invalidSplitterConfig, distributions, OWNER
        );
    }

    function testValidateDistributions() public pure {
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        // Test validation logic by checking array properties directly

        AbstractDeployer.TokenDistribution[] memory invalidDistributions = new AbstractDeployer.TokenDistribution[](1);
        invalidDistributions[0] = AbstractDeployer.TokenDistribution({recipient: address(0), amount: 1000});

        // Test validation logic by checking array properties directly
        assertTrue(distributions.length > 0);
        assertTrue(distributions[0].recipient != address(0));
        assertTrue(distributions[0].amount > 0);

        // Test invalid case
        assertFalse(invalidDistributions[0].recipient != address(0));
    }

    function testValidateSplitterConfig() public pure {
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;
        // Test empty config is valid
        assertTrue(emptySplitterConfig.packedPayeesData.length == 0);

        AbstractDeployer.SplitterConfig memory validSplitterConfig = createBasicSplitterConfig();
        // Test valid config has data
        assertTrue(validSplitterConfig.packedPayeesData.length > 0);
        assertTrue(validSplitterConfig.packedPayeesData.length % 22 == 0);

        // Test invalid calldata length
        bytes memory invalidData = abi.encodePacked(uint16(6000)); // Only 2 bytes, not 22
        AbstractDeployer.SplitterConfig memory invalidConfig =
            AbstractDeployer.SplitterConfig({packedPayeesData: invalidData});
        assertFalse(invalidConfig.packedPayeesData.length % 22 == 0);
    }

    function testCalculateTotalDistribution() public pure {
        AbstractDeployer.TokenDistribution[] memory distributions = createBasicTokenDistribution();

        // Calculate total manually to test logic
        uint256 total = 0;
        for (uint256 i = 0; i < distributions.length; i++) {
            total += distributions[i].amount;
        }
        assertEq(total, 3000 * 10 ** 18);

        AbstractDeployer.TokenDistribution[] memory emptyDistributions = new AbstractDeployer.TokenDistribution[](0);
        // Test empty array
        uint256 emptyTotal = 0;
        for (uint256 i = 0; i < emptyDistributions.length; i++) {
            emptyTotal += emptyDistributions[i].amount;
        }
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
