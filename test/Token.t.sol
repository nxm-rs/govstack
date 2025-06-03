// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "./TestHelper.sol";

contract TokenTest is TestHelper {
    Token public token;

    function setUp() public {
        token = new Token(TOKEN_NAME, TOKEN_SYMBOL, INITIAL_SUPPLY, OWNER);
    }

    // Constructor Tests
    function testConstructor() public view {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(OWNER), INITIAL_SUPPLY);
        assertEq(token.owner(), OWNER);
    }

    function testConstructorWithZeroSupply() public {
        Token zeroSupplyToken = new Token("Zero Token", "ZERO", 0, OWNER);
        assertEq(zeroSupplyToken.totalSupply(), 0);
        assertEq(zeroSupplyToken.balanceOf(OWNER), 0);
        assertEq(zeroSupplyToken.owner(), OWNER);
    }

    function testConstructorWithDifferentOwner() public {
        Token differentOwnerToken = new Token(TOKEN_NAME, TOKEN_SYMBOL, INITIAL_SUPPLY, USER1);
        assertEq(differentOwnerToken.owner(), USER1);
        assertEq(differentOwnerToken.balanceOf(USER1), INITIAL_SUPPLY);
    }

    // Minting Tests
    function testOwnerCanMint() public {
        uint256 mintAmount = 500e18;
        uint256 initialBalance = token.balanceOf(USER1);
        uint256 initialTotalSupply = token.totalSupply();

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), USER1, mintAmount);

        vm.prank(OWNER);
        token.mint(USER1, mintAmount);

        assertEq(token.balanceOf(USER1), initialBalance + mintAmount);
        assertEq(token.totalSupply(), initialTotalSupply + mintAmount);
    }

    function testNonOwnerCannotMint() public {
        uint256 mintAmount = 500e18;

        vm.expectRevert();
        vm.prank(USER1);
        token.mint(USER2, mintAmount);
    }

    function testMintToZeroAddressIncreasesTotalSupply() public {
        uint256 mintAmount = 500e18;
        uint256 initialTotalSupply = token.totalSupply();

        vm.prank(OWNER);
        token.mint(address(0), mintAmount);

        // Minting to zero address still increases total supply (tokens are burned)
        assertEq(token.totalSupply(), initialTotalSupply + mintAmount);
        assertEq(token.balanceOf(address(0)), mintAmount);
    }

    // Burning Tests
    function testOwnerCanBurnFromAddress() public {
        uint256 burnAmount = 100e18;
        uint256 initialBalance = token.balanceOf(OWNER);
        uint256 initialTotalSupply = token.totalSupply();

        vm.expectEmit(true, true, false, true);
        emit Transfer(OWNER, address(0), burnAmount);

        vm.prank(OWNER);
        token.burn(OWNER, burnAmount);

        assertEq(token.balanceOf(OWNER), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialTotalSupply - burnAmount);
    }

    function testOwnerCanBurnOwnBalance() public {
        uint256 burnAmount = 100e18;
        uint256 initialBalance = token.balanceOf(OWNER);
        uint256 initialTotalSupply = token.totalSupply();

        vm.expectEmit(true, true, false, true);
        emit Transfer(OWNER, address(0), burnAmount);

        vm.prank(OWNER);
        token.burn(burnAmount);

        assertEq(token.balanceOf(OWNER), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialTotalSupply - burnAmount);
    }

    function testNonOwnerCannotBurnFromAddress() public {
        uint256 burnAmount = 100e18;

        vm.expectRevert();
        vm.prank(USER1);
        token.burn(OWNER, burnAmount);
    }

    function testNonOwnerCannotBurnOwnBalance() public {
        uint256 burnAmount = 100e18;

        vm.expectRevert();
        vm.prank(USER1);
        token.burn(burnAmount);
    }

    function testBurnMoreThanBalance() public {
        uint256 burnAmount = INITIAL_SUPPLY + 1;

        vm.expectRevert();
        vm.prank(OWNER);
        token.burn(OWNER, burnAmount);
    }

    // Ownership Tests
    function testOwnerCanRenounceOwnership() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, address(0));

        vm.prank(OWNER);
        token.renounceOwnership();

        assertEq(token.owner(), address(0));
    }

    function testNonOwnerCannotRenounceOwnership() public {
        vm.expectRevert();
        vm.prank(USER1);
        token.renounceOwnership();
    }

    function testOwnerCanTransferOwnership() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(OWNER, USER1);

        vm.prank(OWNER);
        token.transferOwnership(USER1);

        assertEq(token.owner(), USER1);
    }

    function testNewOwnerCanMint() public {
        // Transfer ownership
        vm.prank(OWNER);
        token.transferOwnership(USER1);

        // New owner can mint
        uint256 mintAmount = 500e18;
        vm.prank(USER1);
        token.mint(USER2, mintAmount);

        assertEq(token.balanceOf(USER2), mintAmount);
    }

    function testFormerOwnerCannotMint() public {
        // Transfer ownership
        vm.prank(OWNER);
        token.transferOwnership(USER1);

        // Former owner cannot mint
        vm.expectRevert();
        vm.prank(OWNER);
        token.mint(USER2, 500e18);
    }

    function testCannotTransferOwnershipToZeroAddress() public {
        vm.expectRevert();
        vm.prank(OWNER);
        token.transferOwnership(address(0));
    }

    function testCannotMintAfterOwnershipRenounced() public {
        // Renounce ownership
        vm.prank(OWNER);
        token.renounceOwnership();

        // Try to mint - should fail because there's no owner
        vm.expectRevert();
        vm.prank(OWNER); // Even the former owner can't mint
        token.mint(USER1, 100e18);

        vm.expectRevert();
        vm.prank(USER1);
        token.mint(USER1, 100e18);
    }

    function testCannotBurnAfterOwnershipRenounced() public {
        // Renounce ownership
        vm.prank(OWNER);
        token.renounceOwnership();

        // Try to burn - should fail because there's no owner
        vm.expectRevert();
        vm.prank(OWNER); // Even the former owner can't burn
        token.burn(OWNER, 100e18);

        vm.expectRevert();
        vm.prank(USER1);
        token.burn(USER1, 100e18);
    }

    // ERC20 Functionality Tests
    function testBasicTransfer() public {
        uint256 transferAmount = 100e18;

        vm.prank(OWNER);
        token.transfer(USER1, transferAmount);

        assertEq(token.balanceOf(OWNER), INITIAL_SUPPLY - transferAmount);
        assertEq(token.balanceOf(USER1), transferAmount);
    }

    function testNameAndSymbolFunctions() public view {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
    }

    function testDecimalsDefault() public view {
        // ERC20 from solady defaults to 18 decimals
        assertEq(token.decimals(), 18);
    }

    // ERC20Votes Integration Tests
    function testVotingPowerAfterMint() public {
        uint256 mintAmount = 500e18;

        vm.prank(OWNER);
        token.mint(USER1, mintAmount);

        // User needs to delegate to themselves to get voting power
        vm.prank(USER1);
        token.delegate(USER1);

        assertEq(token.getVotes(USER1), mintAmount);
    }

    function testVotingPowerAfterBurn() public {
        uint256 burnAmount = 100e18;

        // Owner delegates to themselves first
        vm.prank(OWNER);
        token.delegate(OWNER);

        uint256 initialVotes = token.getVotes(OWNER);

        vm.prank(OWNER);
        token.burn(OWNER, burnAmount);

        assertEq(token.getVotes(OWNER), initialVotes - burnAmount);
    }

    // Fuzz Tests
    function testFuzzMinting(uint256 amount) public {
        vm.assume(amount <= type(uint256).max - token.totalSupply());

        uint256 initialSupply = token.totalSupply();

        vm.prank(OWNER);
        token.mint(USER1, amount);

        assertEq(token.totalSupply(), initialSupply + amount);
        assertEq(token.balanceOf(USER1), amount);
    }

    function testFuzzBurning(uint256 amount) public {
        vm.assume(amount <= token.balanceOf(OWNER));

        uint256 initialSupply = token.totalSupply();
        uint256 initialBalance = token.balanceOf(OWNER);

        vm.prank(OWNER);
        token.burn(OWNER, amount);

        assertEq(token.totalSupply(), initialSupply - amount);
        assertEq(token.balanceOf(OWNER), initialBalance - amount);
    }
}