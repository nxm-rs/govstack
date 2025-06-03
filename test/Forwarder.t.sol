// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Forwarder.sol";
import "../src/forwarders/gnosis/GnosisChainForwarderFactory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

/// @title TestERC20
/// @notice Simple ERC20 token for testing
contract TestERC20 is ERC20 {
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title TestForwarder
/// @notice Concrete implementation of Forwarder for testing
contract TestForwarder is Forwarder {
    address public constant MOCK_BRIDGE = 0x1234567890123456789012345678901234567890;

    function _bridgeToken(address token, uint256 amount, address recipient) internal override {
        // Mock bridge call
        (bool success,) = MOCK_BRIDGE.call(abi.encodeCall(this.bridgeToken, (token, amount, recipient)));
        require(success, BridgeFailed());
    }

    function _bridgeNative(uint256 amount, address recipient) internal override {
        // Mock bridge call
        (bool success,) = MOCK_BRIDGE.call{value: amount}(abi.encodeCall(this.bridgeNative, (amount, recipient)));
        require(success, BridgeFailed());
    }

    // Mock functions for the bridge calls
    function bridgeToken(address token, uint256 amount, address recipient) external pure returns (bool) {
        // This is just for abi.encodeCall, never actually called
        return true;
    }

    function bridgeNative(uint256 amount, address recipient) external payable returns (bool) {
        // This is just for abi.encodeCall, never actually called
        return true;
    }
}

/// @title ForwarderTest
/// @notice Test suite for Forwarder contracts
contract ForwarderTest is Test {
    GnosisChainForwarderFactory factory;
    TestERC20 testToken;
    address mainnetRecipient;
    address user;
    address mockBridge;

    // Events from Forwarder
    event TokensForwarded(address indexed token, uint256 amount, address indexed recipient);
    event NativeForwarded(uint256 amount, address indexed recipient);

    function setUp() public {
        // Set chain ID to Gnosis Chain since factory deploys GnosisChainForwarder
        vm.chainId(100);

        // Create test addresses
        mainnetRecipient = vm.addr(1);
        user = vm.addr(2);
        mockBridge = 0x1234567890123456789012345678901234567890;

        // Deploy factory (which deploys its own implementation)
        factory = new GnosisChainForwarderFactory();

        // Deploy test token
        testToken = new TestERC20("Test Token", "TEST");
    }

    function testForwarderInitialization() public {
        TestForwarder forwarder = new TestForwarder();

        // Test proper initialization
        forwarder.initialize(mainnetRecipient);
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);

        // Test double initialization fails
        vm.expectRevert(Forwarder.AlreadyInitialized.selector);
        forwarder.initialize(mainnetRecipient);
    }

    function testInvalidInitialization() public {
        TestForwarder forwarder = new TestForwarder();

        // Test initialization with zero address fails
        vm.expectRevert("Invalid recipient");
        forwarder.initialize(address(0));
    }

    function testFactoryPreventsDuplicateDeployment() public {
        // Deploy first forwarder
        address payable forwarder1 = factory.deployForwarder(mainnetRecipient);

        // Verify it exists
        assertTrue(forwarder1.code.length > 0);

        // Try to deploy again - should revert with DeploymentFailed since the address already has code
        vm.expectRevert(ForwarderFactory.DeploymentFailed.selector);
        factory.deployForwarder(mainnetRecipient);
    }

    function testGetOrDeployForwarder() public {
        // First call should deploy
        address payable forwarder1 = factory.getOrDeployForwarder(mainnetRecipient);
        assertTrue(forwarder1 != address(0));

        // Second call should return existing
        address payable forwarder2 = factory.getOrDeployForwarder(mainnetRecipient);
        assertEq(forwarder1, forwarder2);
    }

    function testTokenForwarding() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Use deal to set token balance directly
        deal(address(testToken), address(forwarder), 1000e18);

        // Mock the bridge call to succeed
        vm.mockCall(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(testToken), 1000e18, mainnetRecipient)),
            abi.encode(true)
        );

        // Expect the bridge call
        vm.expectCall(
            mockBridge, abi.encodeCall(forwarder.bridgeToken, (address(testToken), 1000e18, mainnetRecipient))
        );

        // Forward tokens
        vm.expectEmit(true, true, false, true);
        emit TokensForwarded(address(testToken), 1000e18, mainnetRecipient);

        forwarder.forwardToken(address(testToken));
    }

    function testTokenForwardingSpecificAmount() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Use deal to set token balance directly
        deal(address(testToken), address(forwarder), 1000e18);

        // Mock the bridge call to succeed
        vm.mockCall(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(testToken), 500e18, mainnetRecipient)),
            abi.encode(true)
        );

        // Expect the bridge call
        vm.expectCall(mockBridge, abi.encodeCall(forwarder.bridgeToken, (address(testToken), 500e18, mainnetRecipient)));

        // Forward specific amount
        vm.expectEmit(true, true, false, true);
        emit TokensForwarded(address(testToken), 500e18, mainnetRecipient);

        forwarder.forwardToken(address(testToken), 500e18);
    }

    function testTokenForwardingInsufficientBalance() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Try to forward more than available (balance is 0)
        vm.expectRevert("Insufficient balance");
        forwarder.forwardToken(address(testToken), 1000e18);
    }

    function testTokenForwardingZeroAmount() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Try to forward zero amount
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardToken(address(testToken), 0);

        // Try to forward when balance is zero
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardToken(address(testToken));
    }

    function testNativeForwarding() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Use vm.deal to set native balance directly
        vm.deal(address(forwarder), 1 ether);

        // Mock the bridge call to succeed
        vm.mockCall(
            mockBridge, 1 ether, abi.encodeCall(forwarder.bridgeNative, (1 ether, mainnetRecipient)), abi.encode(true)
        );

        // Expect the bridge call
        vm.expectCall(mockBridge, 1 ether, abi.encodeCall(forwarder.bridgeNative, (1 ether, mainnetRecipient)));

        // Forward native tokens
        vm.expectEmit(true, false, false, true);
        emit NativeForwarded(1 ether, mainnetRecipient);

        forwarder.forwardNative();
    }

    function testNativeForwardingSpecificAmount() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Use vm.deal to set native balance directly
        vm.deal(address(forwarder), 1 ether);

        // Mock the bridge call to succeed
        vm.mockCall(
            mockBridge,
            0.5 ether,
            abi.encodeCall(forwarder.bridgeNative, (0.5 ether, mainnetRecipient)),
            abi.encode(true)
        );

        // Expect the bridge call
        vm.expectCall(mockBridge, 0.5 ether, abi.encodeCall(forwarder.bridgeNative, (0.5 ether, mainnetRecipient)));

        // Forward specific amount
        vm.expectEmit(true, false, false, true);
        emit NativeForwarded(0.5 ether, mainnetRecipient);

        forwarder.forwardNative(0.5 ether);
    }

    function testNativeForwardingZeroAmount() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Try to forward zero amount
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardNative(0);

        // Try to forward when balance is zero
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardNative();
    }

    function testBatchForwardTokens() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Create multiple test tokens
        TestERC20 token2 = new TestERC20("Test Token 2", "TEST2");
        TestERC20 token3 = new TestERC20("Test Token 3", "TEST3");

        // Mint tokens to forwarder
        testToken.mint(address(forwarder), 1000e18);
        token2.mint(address(forwarder), 500e6);
        token3.mint(address(forwarder), 250e8);

        // Mock the bridge calls to succeed for all tokens
        vm.mockCall(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(testToken), 1000e18, mainnetRecipient)),
            abi.encode(true)
        );
        vm.mockCall(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(token2), 500e6, mainnetRecipient)),
            abi.encode(true)
        );
        vm.mockCall(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(token3), 250e8, mainnetRecipient)),
            abi.encode(true)
        );

        // Create token array
        address[] memory tokens = new address[](3);
        tokens[0] = address(testToken);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        // Forward all tokens
        forwarder.batchForwardTokens(tokens);
    }

    function testGetBalance() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Test ERC20 balance
        deal(address(testToken), address(forwarder), 1000e18);
        assertEq(forwarder.getBalance(address(testToken)), 1000e18);

        // Test native balance
        vm.deal(address(forwarder), 1 ether);
        assertEq(forwarder.getBalance(address(0)), 1 ether);
    }

    function testUninitializedForwarderFails() public {
        TestForwarder uninitializedForwarder = new TestForwarder();

        // All operations should fail on uninitialized forwarder
        vm.expectRevert("Not initialized");
        uninitializedForwarder.forwardToken(address(testToken));

        vm.expectRevert("Not initialized");
        uninitializedForwarder.forwardNative();

        address[] memory tokens = new address[](1);
        tokens[0] = address(testToken);

        vm.expectRevert("Not initialized");
        uninitializedForwarder.batchForwardTokens(tokens);
    }

    function testReceiveFunction() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Test that forwarder can receive native tokens
        uint256 initialBalance = address(forwarder).balance;

        (bool success,) = address(forwarder).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(forwarder).balance, initialBalance + 1 ether);
    }

    function testBatchDeployForwarders() public {
        address[] memory recipients = new address[](2);
        recipients[0] = mainnetRecipient;
        recipients[1] = vm.addr(99);

        address payable[] memory forwarders = factory.batchDeployForwarders(recipients);

        assertEq(forwarders.length, 2);
        assertTrue(forwarders[0] != address(0));
        assertTrue(forwarders[1] != address(0));
        assertTrue(forwarders[0] != forwarders[1]);
    }

    function testDeterministicAddresses() public {
        // Deploy forwarder for same recipient
        address payable forwarder1 = factory.deployForwarder(mainnetRecipient);

        // Create new factory (simulating deployment on different chain)
        GnosisChainForwarderFactory factory2 = new GnosisChainForwarderFactory();

        // Predict address from both factories
        address predicted1 = factory.predictForwarderAddress(mainnetRecipient);
        address predicted2 = factory2.predictForwarderAddress(mainnetRecipient);

        // The prediction should match the deployed address from the same factory
        assertEq(forwarder1, predicted1);

        // Note: Addresses will be different between factories because CREATE2 includes deployer address
        // This is expected behavior - each factory creates different addresses
        assertTrue(predicted1 != predicted2);

        // Deploy from second factory and verify it matches its prediction
        address payable forwarder2 = factory2.deployForwarder(mainnetRecipient);
        assertEq(forwarder2, predicted2);
    }

    function testBridgeFailure() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Set up token balance
        deal(address(testToken), address(forwarder), 1000e18);

        // Mock the bridge call to revert
        vm.mockCallRevert(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(testToken), 1000e18, mainnetRecipient)),
            abi.encodeWithSelector(Forwarder.BridgeFailed.selector)
        );

        // Expect bridge failure
        vm.expectRevert(Forwarder.BridgeFailed.selector);
        forwarder.forwardToken(address(testToken));
    }

    function testNativeBridgeFailure() public {
        TestForwarder forwarder = new TestForwarder();
        forwarder.initialize(mainnetRecipient);

        // Set up native balance
        vm.deal(address(forwarder), 1 ether);

        // Mock the bridge call to revert
        vm.mockCallRevert(
            mockBridge,
            1 ether,
            abi.encodeCall(forwarder.bridgeNative, (1 ether, mainnetRecipient)),
            abi.encodeWithSelector(Forwarder.BridgeFailed.selector)
        );

        // Expect bridge failure
        vm.expectRevert(Forwarder.BridgeFailed.selector);
        forwarder.forwardNative();
    }
}

/// @title GnosisChainForwarderTest
/// @notice Test suite specifically for GnosisChainForwarder
contract GnosisChainForwarderTest is Test {
    GnosisChainForwarderFactory factory;
    GnosisChainForwarder forwarder;
    TestERC20 testToken;
    address mainnetRecipient = vm.addr(1);

    function setUp() public {
        // Set chain ID to Gnosis Chain
        vm.chainId(100);

        // Deploy factory (which deploys its own implementation)
        factory = new GnosisChainForwarderFactory();

        // Deploy forwarder instance
        address payable forwarderAddr = factory.deployForwarder(mainnetRecipient);
        forwarder = GnosisChainForwarder(forwarderAddr);

        // Deploy test token
        testToken = new TestERC20("Test Token", "TEST");
    }

    function testGnosisChainId() public view {
        assertEq(block.chainid, 100);
    }

    function testBridgeConfiguration() public view {
        assertTrue(address(forwarder.OMNIBRIDGE()) != address(0) && address(forwarder.XDAI_BRIDGE()) != address(0));
    }

    function testInvalidChainDeployment() public {
        // Change to wrong chain
        vm.chainId(1);

        GnosisChainForwarder newForwarder = new GnosisChainForwarder();
        vm.expectRevert(Forwarder.InvalidChain.selector);
        newForwarder.initialize(mainnetRecipient);
    }

    function testEmergencyRecover() public {
        address recoveryAddress = vm.addr(2);

        // Give forwarder some tokens
        testToken.mint(address(forwarder), 1000e18);

        // Only mainnet recipient can recover
        vm.prank(mainnetRecipient);
        forwarder.emergencyRecover(address(testToken), recoveryAddress);

        assertEq(testToken.balanceOf(recoveryAddress), 1000e18);
    }

    function testEmergencyRecoverNative() public {
        address recoveryAddress = vm.addr(2);

        // Give forwarder some native tokens
        vm.deal(address(forwarder), 1 ether);

        uint256 initialBalance = recoveryAddress.balance;

        // Only mainnet recipient can recover
        vm.prank(mainnetRecipient);
        forwarder.emergencyRecover(address(0), recoveryAddress);

        assertEq(recoveryAddress.balance, initialBalance + 1 ether);
    }

    function testEmergencyRecoverInvalidAddress() public {
        vm.prank(mainnetRecipient);
        vm.expectRevert("Invalid recovery address");
        forwarder.emergencyRecover(address(0), address(0));
    }

    function testInitialization() public view {
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);
    }

    function testForwarderCanReceiveTokens() public {
        // Mint tokens to forwarder
        testToken.mint(address(forwarder), 500e18);

        assertEq(testToken.balanceOf(address(forwarder)), 500e18);
    }

    function testForwarderCanReceiveNative() public {
        uint256 initialBalance = address(forwarder).balance;

        (bool success,) = address(forwarder).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(forwarder).balance, initialBalance + 1 ether);
    }
}
