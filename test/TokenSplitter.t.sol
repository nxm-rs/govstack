// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "./TestHelper.sol";

contract TokenSplitterTest is TestHelper {
    TokenSplitter public splitter;
    TestERC20 public token1;
    TestERC20 public token2;

    // Test payees data
    bytes public packedPayeesData;
    bytes32 public expectedHash;

    address public owner = address(0x123); // Dedicated owner address

    function setUp() public {
        token1 = deployMockToken();
        token2 = deployMockToken();

        // Create splitter with dedicated owner
        splitter = new TokenSplitter(owner);

        // Create packed payees data (60/40 split)
        TokenSplitter.PayeeData[] memory payees = new TokenSplitter.PayeeData[](2);
        payees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 6000}); // 60%
        payees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 4000}); // 40%

        packedPayeesData = _createPackedPayeesData(payees);
        expectedHash = _calculatePayeesHash(payees);

        // Set the payees (only owner can do this)
        vm.prank(owner);
        splitter.updatePayees(packedPayeesData);

        // Give tokens to the owner for testing
        token1.mint(owner, 10000 * 10 ** 18);
        token2.mint(owner, 10000 * 10 ** 18);
    }

    function testInitialSetup() public view {
        assertTrue(_hasPayees(address(splitter)));
        assertEq(splitter.payeesHash(), expectedHash);

        // Test getPayeeInfo
        (bool isPayee1, uint16 shares1) = _getPayeeInfo(address(splitter), PAYEE1, packedPayeesData);
        assertTrue(isPayee1);
        assertEq(shares1, 6000);

        (bool isPayee2, uint16 shares2) = _getPayeeInfo(address(splitter), PAYEE2, packedPayeesData);
        assertTrue(isPayee2);
        assertEq(shares2, 4000);

        (bool isPayee3, uint16 shares3) = _getPayeeInfo(address(splitter), PAYEE3, packedPayeesData);
        assertFalse(isPayee3);
        assertEq(shares3, 0);
    }

    function testUpdatePayeesValidation() public {
        // Test empty calldata
        vm.expectRevert(TokenSplitter.EmptyCalldata.selector);
        vm.prank(owner);
        splitter.updatePayees("");

        // Test invalid calldata length (not multiple of 22)
        bytes memory invalidData = new bytes(23);
        vm.expectRevert(TokenSplitter.InvalidCalldataLength.selector);
        vm.prank(owner);
        splitter.updatePayees(invalidData);

        // Test zero address
        TokenSplitter.PayeeData[] memory invalidPayees = new TokenSplitter.PayeeData[](2);
        invalidPayees[0] = TokenSplitter.PayeeData({payee: address(0), shares: 5000});
        invalidPayees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 5000});

        bytes memory invalidPackedData = _createPackedPayeesData(invalidPayees);
        vm.expectRevert(TokenSplitter.InvalidShares.selector);
        vm.prank(owner);
        splitter.updatePayees(invalidPackedData);

        // Test zero shares
        TokenSplitter.PayeeData[] memory zeroSharesPayees = new TokenSplitter.PayeeData[](2);
        zeroSharesPayees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 0});
        zeroSharesPayees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 10000});

        bytes memory zeroSharesData = _createPackedPayeesData(zeroSharesPayees);
        vm.expectRevert(TokenSplitter.InvalidShares.selector);
        vm.prank(owner);
        splitter.updatePayees(zeroSharesData);

        // Test shares not totaling 10000
        TokenSplitter.PayeeData[] memory wrongTotalPayees = new TokenSplitter.PayeeData[](2);
        wrongTotalPayees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 3000});
        wrongTotalPayees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 4000}); // 7000 total

        bytes memory wrongTotalData = _createPackedPayeesData(wrongTotalPayees);
        vm.expectRevert(TokenSplitter.InvalidTotalShares.selector);
        vm.prank(owner);
        splitter.updatePayees(wrongTotalData);
    }

    function testOnlyOwnerCanUpdatePayees() public {
        vm.prank(PAYEE1); // Not the owner
        vm.expectRevert(); // Should revert with Ownable error
        splitter.updatePayees(packedPayeesData);
    }

    function testPermissionlessSplit() public {
        uint256 amount = 1000 * 10 ** 18;

        // Owner approves splitter to transfer tokens
        vm.prank(owner);
        token1.approve(address(splitter), amount);

        // Anyone can call splitToken (using PAYEE1 as caller)
        vm.prank(PAYEE1);
        splitter.splitToken(address(token1), amount, packedPayeesData);

        // Verify balances - tokens should come from owner, not caller
        assertEq(token1.balanceOf(PAYEE1), 600 * 10 ** 18);
        assertEq(token1.balanceOf(PAYEE2), 400 * 10 ** 18);
        assertEq(token1.balanceOf(owner), 9000 * 10 ** 18); // Owner's balance reduced
    }

    function testSplitToken() public {
        uint256 amount = 1000 * 10 ** 18;

        // Owner approves splitter to transfer tokens
        vm.prank(owner);
        token1.approve(address(splitter), amount);

        expectEmitTokensReleased(address(token1), PAYEE1, 600 * 10 ** 18); // 60%
        expectEmitTokensReleased(address(token1), PAYEE2, 400 * 10 ** 18); // 40%
        expectEmitTokensSplit(address(token1), amount);

        splitter.splitToken(address(token1), amount, packedPayeesData);

        // Verify balances - tokens transferred from owner to payees
        assertEq(token1.balanceOf(PAYEE1), 600 * 10 ** 18);
        assertEq(token1.balanceOf(PAYEE2), 400 * 10 ** 18);
        assertEq(token1.balanceOf(owner), 9000 * 10 ** 18); // Owner's balance reduced
    }

    function testSplitTokenValidation() public {
        // Test zero amount
        vm.expectRevert(TokenSplitter.ZeroAmount.selector);
        splitter.splitToken(address(token1), 0, packedPayeesData);

        // Test empty calldata
        vm.expectRevert(TokenSplitter.EmptyCalldata.selector);
        splitter.splitToken(address(token1), 1000, "");

        // Test wrong hash
        TokenSplitter.PayeeData[] memory wrongPayees = new TokenSplitter.PayeeData[](2);
        wrongPayees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 5000});
        wrongPayees[1] = TokenSplitter.PayeeData({payee: PAYEE3, shares: 5000});

        bytes memory wrongData = _createPackedPayeesData(wrongPayees);
        vm.expectRevert(TokenSplitter.InvalidPayeesHash.selector);
        splitter.splitToken(address(token1), 1000, wrongData);
    }

    function testRoundingInSplit() public {
        uint256 amount = 1001; // Not divisible evenly

        // Owner approves splitter to transfer tokens
        vm.prank(owner);
        token1.approve(address(splitter), amount);

        splitter.splitToken(address(token1), amount, packedPayeesData);

        uint256 payee1Amount = token1.balanceOf(PAYEE1);
        uint256 payee2Amount = token1.balanceOf(PAYEE2);

        assertEq(payee1Amount, 600); // 60% of 1001 = 600.6, rounded down
        assertEq(payee2Amount, 401); // Remainder goes to last payee
        assertEq(payee1Amount + payee2Amount, amount); // No tokens lost
    }

    function testCalculateSplit() public view {
        uint256 amount = 1000 * 10 ** 18;
        uint256[] memory expectedAmounts = _calculateSplit(address(splitter), amount, packedPayeesData);

        assertEq(expectedAmounts.length, 2);
        assertEq(expectedAmounts[0], 600 * 10 ** 18); // 60%
        assertEq(expectedAmounts[1], 400 * 10 ** 18); // 40%

        // Test with amount that has rounding
        uint256[] memory roundingAmounts = _calculateSplit(address(splitter), 1001, packedPayeesData);
        assertEq(roundingAmounts[0], 600);
        assertEq(roundingAmounts[1], 401); // Last payee gets remainder
        assertEq(roundingAmounts[0] + roundingAmounts[1], 1001);
    }

    function testMultipleTokenSplits() public {
        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;

        // Owner approves and split token1
        vm.prank(owner);
        token1.approve(address(splitter), amount1);
        splitter.splitToken(address(token1), amount1, packedPayeesData);

        // Owner approves and split token2
        vm.prank(owner);
        token2.approve(address(splitter), amount2);
        splitter.splitToken(address(token2), amount2, packedPayeesData);

        // Verify token1 balances
        assertEq(token1.balanceOf(PAYEE1), 600 * 10 ** 18); // 60%
        assertEq(token1.balanceOf(PAYEE2), 400 * 10 ** 18); // 40%

        // Verify token2 balances
        assertEq(token2.balanceOf(PAYEE1), 1200 * 10 ** 18); // 60%
        assertEq(token2.balanceOf(PAYEE2), 800 * 10 ** 18); // 40%
    }

    function testThreeWaySplit() public {
        // Create a 3-way split: 50%, 30%, 20%
        TokenSplitter.PayeeData[] memory payees = new TokenSplitter.PayeeData[](3);
        payees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 5000}); // 50%
        payees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 3000}); // 30%
        payees[2] = TokenSplitter.PayeeData({payee: PAYEE3, shares: 2000}); // 20%

        address threeWayOwner = address(0x456);
        TokenSplitter threeWaySplitter = new TokenSplitter(threeWayOwner);
        bytes memory threeWayData = _createPackedPayeesData(payees);

        vm.prank(threeWayOwner);
        threeWaySplitter.updatePayees(threeWayData);

        uint256 amount = 10000 * 10 ** 18;
        token1.mint(threeWayOwner, amount);

        vm.prank(threeWayOwner);
        token1.approve(address(threeWaySplitter), amount);

        threeWaySplitter.splitToken(address(token1), amount, threeWayData);

        assertEq(token1.balanceOf(PAYEE1), 5000 * 10 ** 18); // 50%
        assertEq(token1.balanceOf(PAYEE2), 3000 * 10 ** 18); // 30%
        assertEq(token1.balanceOf(PAYEE3), 2000 * 10 ** 18); // 20%
    }

    function testUpdatePayees() public {
        // Create new payees configuration (30/70 split)
        TokenSplitter.PayeeData[] memory newPayees = new TokenSplitter.PayeeData[](2);
        newPayees[0] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 3000}); // 30%
        newPayees[1] = TokenSplitter.PayeeData({payee: PAYEE3, shares: 7000}); // 70%

        bytes memory newPackedData = _createPackedPayeesData(newPayees);
        bytes32 newHash = _calculatePayeesHash(newPayees);

        // Update payees (only owner can do this)
        expectEmitPayeeAdded(PAYEE2, 3000);
        expectEmitPayeeAdded(PAYEE3, 7000);
        expectEmitPayeesUpdated(newHash);

        vm.prank(owner);
        splitter.updatePayees(newPackedData);

        // Verify new configuration
        assertEq(splitter.payeesHash(), newHash);

        (bool isOldPayee,) = _getPayeeInfo(address(splitter), PAYEE1, newPackedData);
        assertFalse(isOldPayee);

        (bool isNewPayee1, uint16 shares1) = _getPayeeInfo(address(splitter), PAYEE2, newPackedData);
        assertTrue(isNewPayee1);
        assertEq(shares1, 3000);

        (bool isNewPayee2, uint16 shares2) = _getPayeeInfo(address(splitter), PAYEE3, newPackedData);
        assertTrue(isNewPayee2);
        assertEq(shares2, 7000);

        // Test split with new configuration
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(owner);
        token1.approve(address(splitter), amount);
        splitter.splitToken(address(token1), amount, newPackedData);

        assertEq(token1.balanceOf(PAYEE2), 300 * 10 ** 18); // 30%
        assertEq(token1.balanceOf(PAYEE3), 700 * 10 ** 18); // 70%
    }

    function testCalculatePayeesHashView() public view {
        TokenSplitter.PayeeData[] memory payees = new TokenSplitter.PayeeData[](2);
        payees[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 6000});
        payees[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 4000});

        bytes32 calculatedHash = _calculatePayeesHash(payees);
        assertEq(calculatedHash, expectedHash);
    }

    function testAddressSorting() public pure {
        // Test that different input orders produce the same hash
        TokenSplitter.PayeeData[] memory payees1 = new TokenSplitter.PayeeData[](2);
        payees1[0] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 6000});
        payees1[1] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 4000});

        TokenSplitter.PayeeData[] memory payees2 = new TokenSplitter.PayeeData[](2);
        payees2[0] = TokenSplitter.PayeeData({payee: PAYEE2, shares: 4000}); // Swapped order
        payees2[1] = TokenSplitter.PayeeData({payee: PAYEE1, shares: 6000});

        bytes32 hash1 = _calculatePayeesHash(payees1);
        bytes32 hash2 = _calculatePayeesHash(payees2);

        assertEq(hash1, hash2, "Hashes should be equal regardless of input order");

        bytes memory packedData1 = _createPackedPayeesData(payees1);
        bytes memory packedData2 = _createPackedPayeesData(payees2);

        assertEq(
            keccak256(packedData1), keccak256(packedData2), "Packed data should be identical regardless of input order"
        );
    }

    function testInsufficientAllowanceFromOwner() public {
        uint256 amount = 1000 * 10 ** 18;

        // Owner only approves half the amount needed
        vm.prank(owner);
        token1.approve(address(splitter), amount / 2);

        // Should revert when trying to split the full amount
        vm.expectRevert();
        splitter.splitToken(address(token1), amount, packedPayeesData);
    }

    function testOwnerHasInsufficientBalance() public {
        uint256 amount = 20000 * 10 ** 18; // More than owner has

        // Owner approves the full amount but doesn't have enough tokens
        vm.prank(owner);
        token1.approve(address(splitter), amount);

        // Should revert due to insufficient balance
        vm.expectRevert();
        splitter.splitToken(address(token1), amount, packedPayeesData);
    }

    function testMultipleCallersCanSplit() public {
        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 500 * 10 ** 18;

        // Owner approves total amount
        vm.prank(owner);
        token1.approve(address(splitter), amount1 + amount2);

        // First caller (PAYEE1) splits some tokens
        vm.prank(PAYEE1);
        splitter.splitToken(address(token1), amount1, packedPayeesData);

        // Different caller (PAYEE2) splits remaining tokens
        vm.prank(PAYEE2);
        splitter.splitToken(address(token1), amount2, packedPayeesData);

        // Verify total distributions
        assertEq(token1.balanceOf(PAYEE1), 600 * 10 ** 18 + 300 * 10 ** 18); // 60% of both splits
        assertEq(token1.balanceOf(PAYEE2), 400 * 10 ** 18 + 200 * 10 ** 18); // 40% of both splits
        assertEq(token1.balanceOf(owner), 10000 * 10 ** 18 - amount1 - amount2); // Owner's remaining balance
    }

    function testOwnerCannotSplitWithoutApproval() public {
        uint256 amount = 1000 * 10 ** 18;

        // Owner tries to split without approving the contract first
        vm.prank(owner);
        vm.expectRevert();
        splitter.splitToken(address(token1), amount, packedPayeesData);
    }

    function expectEmitPayeesUpdated(bytes32 newHash) internal {
        vm.expectEmit(true, false, false, false);
        emit TokenSplitter.PayeesUpdated(newHash);
    }
}
