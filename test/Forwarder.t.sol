// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Forwarder.sol";
import "../src/forwarders/gnosis/GnosisForwarderFactory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

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
    using SafeTransferLib for address;

    address public constant MOCK_BRIDGE = 0x1234567890123456789012345678901234567890;

    function _bridgeToken(address token, uint256 amount, address recipient) internal override {
        // Transfer tokens to simulate bridging
        token.safeTransfer(MOCK_BRIDGE, amount);

        // Mock bridge call
        (bool success,) = MOCK_BRIDGE.call(abi.encodeCall(this.bridgeToken, (token, amount, recipient)));
        require(success, BridgeFailed());
    }

    function _bridgeNative(uint256 amount, address recipient) internal override {
        // Send native tokens to simulate bridging
        MOCK_BRIDGE.safeTransferETH(amount);

        // Mock bridge call (no value needed since we already sent it)
        (bool success,) = MOCK_BRIDGE.call(abi.encodeCall(this.bridgeNative, (amount, recipient)));
        require(success, BridgeFailed());
    }

    // Mock functions for the bridge calls
    function bridgeToken(address, uint256, address) external pure returns (bool) {
        // This is just for abi.encodeCall, never actually called
        return true;
    }

    function bridgeNative(uint256, address) external payable returns (bool) {
        // This is just for abi.encodeCall, never actually called
        return true;
    }
}

/// @title ForwarderTest
/// @notice Test suite for Forwarder contracts
contract ForwarderTest is Test {
    GnosisForwarderFactory factory;
    TestERC20 testToken;
    address mainnetRecipient;
    address user;
    address mockBridge;

    // Events from Forwarder
    event TokensForwarded(address indexed token, uint256 amount, address indexed recipient);
    event NativeForwarded(uint256 amount, address indexed recipient);

    function setUp() public {
        // Set chain ID to Gnosis Chain since factory deploys GnosisForwarder
        vm.chainId(100);

        // Create test addresses
        mainnetRecipient = vm.addr(1);
        user = vm.addr(2);
        mockBridge = 0x1234567890123456789012345678901234567890;

        // Deploy factory (which deploys its own implementation)
        factory = new GnosisForwarderFactory();

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
        address payable forwarder1 = factory.deployForwarder(mainnetRecipient, bytes32(0));

        // Verify it exists
        assertTrue(forwarder1.code.length > 0);

        // Try to deploy again - should revert with DeploymentFailed since the address already has code
        vm.expectRevert(ForwarderFactory.DeploymentFailed.selector);
        factory.deployForwarder(mainnetRecipient, bytes32(0));
    }

    function testGetOrDeployForwarder() public {
        // First call should deploy
        address payable forwarder1 = factory.getOrDeployForwarder(mainnetRecipient, bytes32(0));
        assertTrue(forwarder1 != address(0));

        // Second call should return existing
        address payable forwarder2 = factory.getOrDeployForwarder(mainnetRecipient, bytes32(0));
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

        // Mock the bridge call to succeed (no value since ETH is transferred separately)
        vm.mockCall(mockBridge, abi.encodeCall(forwarder.bridgeNative, (1 ether, mainnetRecipient)), abi.encode(true));

        // Expect the bridge call (no value since ETH is transferred separately)
        vm.expectCall(mockBridge, abi.encodeCall(forwarder.bridgeNative, (1 ether, mainnetRecipient)));

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

        // Mock the bridge call to succeed (no value since ETH is transferred separately)
        vm.mockCall(mockBridge, abi.encodeCall(forwarder.bridgeNative, (0.5 ether, mainnetRecipient)), abi.encode(true));

        // Expect the bridge call (no value since ETH is transferred separately)
        vm.expectCall(mockBridge, abi.encodeCall(forwarder.bridgeNative, (0.5 ether, mainnetRecipient)));

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

        bytes32[] memory salts = new bytes32[](2);
        salts[0] = bytes32(0);
        salts[1] = bytes32(0);

        address payable[] memory forwarders = factory.batchDeployForwarders(recipients, salts);

        assertEq(forwarders.length, 2);
        assertTrue(forwarders[0] != address(0));
        assertTrue(forwarders[1] != address(0));
        assertTrue(forwarders[0] != forwarders[1]);
    }

    function testDeterministicAddresses() public {
        // Deploy forwarder for same recipient
        address payable forwarder1 = factory.deployForwarder(mainnetRecipient, bytes32(0));

        // Create new factory (simulating deployment on different chain)
        GnosisForwarderFactory factory2 = new GnosisForwarderFactory();

        // Predict address from both factories
        address predicted1 = factory.predictForwarderAddress(mainnetRecipient, bytes32(0));
        address predicted2 = factory2.predictForwarderAddress(mainnetRecipient, bytes32(0));

        // Should be the same since they use the same implementation
        assertEq(forwarder1, predicted1);

        // Different factories on same chain will have different implementations
        assertTrue(predicted1 != predicted2);

        // Deploy from second factory and verify it matches its prediction
        address payable forwarder2 = factory2.deployForwarder(mainnetRecipient, bytes32(0));
        assertEq(forwarder2, predicted2);
    }

    function testDeployAndForwardTokens() public {
        address testRecipient = vm.addr(123);

        // Setup forwarder configs - empty tokens array since GnosisForwarder has complex validation
        // and we're not on actual Gnosis chain
        ForwarderFactory.ForwarderConfig[] memory configs = new ForwarderFactory.ForwarderConfig[](1);
        configs[0].salt = bytes32(uint256(456));
        configs[0].tokens = new address[](0);

        // Deploy and forward tokens (should work with empty array)
        address payable[] memory deployedForwarders = factory.deployAndForwardTokens(testRecipient, configs);

        // Verify deployment
        assertEq(deployedForwarders.length, 1);
        assertTrue(deployedForwarders[0].code.length > 0);

        // Verify initialization
        GnosisForwarder deployedForwarderContract = GnosisForwarder(deployedForwarders[0]);
        assertTrue(deployedForwarderContract.initialized());
        assertEq(deployedForwarderContract.mainnetRecipient(), testRecipient);
    }

    function testDeployAndForwardTokensWithDifferentSalts() public {
        address testRecipient = vm.addr(789);

        // Setup configs for two different forwarders
        ForwarderFactory.ForwarderConfig[] memory configs = new ForwarderFactory.ForwarderConfig[](2);
        configs[0].salt = bytes32(uint256(111));
        configs[0].tokens = new address[](0);
        configs[1].salt = bytes32(uint256(222));
        configs[1].tokens = new address[](0);

        // Deploy both forwarders
        address payable[] memory forwarders = factory.deployAndForwardTokens(testRecipient, configs);

        // Should have different addresses due to different salts
        assertEq(forwarders.length, 2);
        assertTrue(forwarders[0] != forwarders[1]);

        // Both should be properly initialized with same recipient
        assertEq(GnosisForwarder(payable(forwarders[0])).mainnetRecipient(), testRecipient);
        assertEq(GnosisForwarder(payable(forwarders[1])).mainnetRecipient(), testRecipient);
    }

    function testDeployAndForwardTokensEmptyArray() public {
        address testRecipient = vm.addr(333);

        // Should deploy successfully even with empty configs array
        ForwarderFactory.ForwarderConfig[] memory configs = new ForwarderFactory.ForwarderConfig[](0);

        address payable[] memory forwarders = factory.deployAndForwardTokens(testRecipient, configs);

        assertEq(forwarders.length, 0);
    }

    function testDeployAndForwardTokensWithTestForwarder() public {
        // Create a custom factory with TestForwarder for proper testing
        ForwarderFactory testFactory = new TestForwarderFactory();

        address testRecipient = vm.addr(999);
        bytes32 salt = bytes32(uint256(777));

        // Setup forwarder config with tokens to forward
        ForwarderFactory.ForwarderConfig[] memory configs = new ForwarderFactory.ForwarderConfig[](1);
        configs[0].salt = salt;
        configs[0].tokens = new address[](2);
        configs[0].tokens[0] = address(testToken); // ERC20 token
        configs[0].tokens[1] = address(0); // Native token

        // Predict the forwarder address
        address predictedForwarder = testFactory.predictForwarderAddress(testRecipient, salt);

        // Fund the predicted forwarder with tokens and native currency
        testToken.mint(predictedForwarder, 500e18);
        vm.deal(predictedForwarder, 2 ether);

        // Get the forwarder contract for mocking
        TestForwarder forwarder = TestForwarder(payable(predictedForwarder));

        // Mock the bridge calls to succeed (no value for native call since ETH is transferred separately)
        vm.mockCall(
            mockBridge,
            abi.encodeCall(forwarder.bridgeToken, (address(testToken), 500e18, testRecipient)),
            abi.encode(true)
        );
        vm.mockCall(mockBridge, abi.encodeCall(forwarder.bridgeNative, (2 ether, testRecipient)), abi.encode(true));

        // Expect the bridge calls (no value for native call)
        vm.expectCall(mockBridge, abi.encodeCall(forwarder.bridgeToken, (address(testToken), 500e18, testRecipient)));
        vm.expectCall(mockBridge, abi.encodeCall(forwarder.bridgeNative, (2 ether, testRecipient)));

        // Expect events
        vm.expectEmit(true, true, false, true);
        emit TokensForwarded(address(testToken), 500e18, testRecipient);
        vm.expectEmit(true, false, false, true);
        emit NativeForwarded(2 ether, testRecipient);

        // Deploy and forward tokens
        address payable[] memory deployedForwarders = testFactory.deployAndForwardTokens(testRecipient, configs);

        // Verify deployment
        assertEq(deployedForwarders.length, 1);
        assertEq(deployedForwarders[0], predictedForwarder);
        assertTrue(deployedForwarders[0].code.length > 0);

        // Verify initialization
        TestForwarder deployedForwarderContract = TestForwarder(deployedForwarders[0]);
        assertTrue(deployedForwarderContract.initialized());
        assertEq(deployedForwarderContract.mainnetRecipient(), testRecipient);

        // Verify tokens were forwarded (balances should be zero)
        assertEq(testToken.balanceOf(deployedForwarders[0]), 0);
        assertEq(deployedForwarders[0].balance, 0);
    }

    function testDeployAndForwardTokensMultipleForwarders() public {
        // Create a custom factory with TestForwarder for proper testing
        ForwarderFactory testFactory = new TestForwarderFactory();

        address testRecipient = vm.addr(888);

        // Create another test token
        TestERC20 testToken2 = new TestERC20("Test Token 2", "TEST2");

        // Setup configs for multiple forwarders with different token sets
        ForwarderFactory.ForwarderConfig[] memory configs = new ForwarderFactory.ForwarderConfig[](3);

        // First forwarder: only ERC20 token
        configs[0].salt = bytes32(uint256(100));
        configs[0].tokens = new address[](1);
        configs[0].tokens[0] = address(testToken);

        // Second forwarder: only native token
        configs[1].salt = bytes32(uint256(200));
        configs[1].tokens = new address[](1);
        configs[1].tokens[0] = address(0);

        // Third forwarder: both tokens
        configs[2].salt = bytes32(uint256(300));
        configs[2].tokens = new address[](2);
        configs[2].tokens[0] = address(testToken2);
        configs[2].tokens[1] = address(0);

        // Predict forwarder addresses
        address forwarder1 = testFactory.predictForwarderAddress(testRecipient, configs[0].salt);
        address forwarder2 = testFactory.predictForwarderAddress(testRecipient, configs[1].salt);
        address forwarder3 = testFactory.predictForwarderAddress(testRecipient, configs[2].salt);

        // Fund the forwarders with their respective tokens
        testToken.mint(forwarder1, 100e18);
        vm.deal(forwarder2, 1 ether);
        testToken2.mint(forwarder3, 200e18);
        vm.deal(forwarder3, 2 ether);

        // Mock bridge calls for all tokens
        vm.mockCall(
            mockBridge,
            abi.encodeCall(TestForwarder.bridgeToken, (address(testToken), 100e18, testRecipient)),
            abi.encode(true)
        );
        vm.mockCall(mockBridge, abi.encodeCall(TestForwarder.bridgeNative, (1 ether, testRecipient)), abi.encode(true));
        vm.mockCall(
            mockBridge,
            abi.encodeCall(TestForwarder.bridgeToken, (address(testToken2), 200e18, testRecipient)),
            abi.encode(true)
        );
        vm.mockCall(mockBridge, abi.encodeCall(TestForwarder.bridgeNative, (2 ether, testRecipient)), abi.encode(true));

        // Deploy and forward tokens from all forwarders
        address payable[] memory deployedForwarders = testFactory.deployAndForwardTokens(testRecipient, configs);

        // Verify all forwarders were deployed
        assertEq(deployedForwarders.length, 3);
        assertEq(deployedForwarders[0], forwarder1);
        assertEq(deployedForwarders[1], forwarder2);
        assertEq(deployedForwarders[2], forwarder3);

        // Verify all forwarders are properly initialized
        for (uint256 i = 0; i < deployedForwarders.length; i++) {
            TestForwarder forwarder = TestForwarder(deployedForwarders[i]);
            assertTrue(forwarder.initialized());
            assertEq(forwarder.mainnetRecipient(), testRecipient);
        }

        // Verify tokens were forwarded (balances should be zero)
        assertEq(testToken.balanceOf(forwarder1), 0);
        assertEq(forwarder2.balance, 0);
        assertEq(testToken2.balanceOf(forwarder3), 0);
        assertEq(forwarder3.balance, 0);
    }

    function testSaltFunctionality() public {
        address testRecipient = vm.addr(555);
        bytes32 salt1 = bytes32(uint256(1));
        bytes32 salt2 = bytes32(uint256(2));
        bytes32 salt3 = keccak256("custom salt");

        // Predict addresses with different salts
        address predicted1 = factory.predictForwarderAddress(testRecipient, salt1);
        address predicted2 = factory.predictForwarderAddress(testRecipient, salt2);
        address predicted3 = factory.predictForwarderAddress(testRecipient, salt3);

        // All addresses should be different
        assertTrue(predicted1 != predicted2);
        assertTrue(predicted1 != predicted3);
        assertTrue(predicted2 != predicted3);

        // Deploy with each salt and verify they match predictions
        address deployed1 = factory.deployForwarder(testRecipient, salt1);
        address deployed2 = factory.deployForwarder(testRecipient, salt2);
        address deployed3 = factory.deployForwarder(testRecipient, salt3);

        assertEq(deployed1, predicted1);
        assertEq(deployed2, predicted2);
        assertEq(deployed3, predicted3);

        // All should have same recipient but different addresses
        assertEq(TestForwarder(payable(deployed1)).mainnetRecipient(), testRecipient);
        assertEq(TestForwarder(payable(deployed2)).mainnetRecipient(), testRecipient);
        assertEq(TestForwarder(payable(deployed3)).mainnetRecipient(), testRecipient);
    }

    function testSameSaltReproducesAddress() public {
        address testRecipient = vm.addr(666);
        bytes32 salt = keccak256("reproducible salt");

        // Predict same address multiple times
        address predicted1 = factory.predictForwarderAddress(testRecipient, salt);
        address predicted2 = factory.predictForwarderAddress(testRecipient, salt);
        address predicted3 = factory.predictForwarderAddress(testRecipient, salt);

        // Should always be the same
        assertEq(predicted1, predicted2);
        assertEq(predicted2, predicted3);

        // Deploy and verify it matches
        address deployed = factory.deployForwarder(testRecipient, salt);
        assertEq(deployed, predicted1);
    }

    function testCalculateSaltFunction() public view {
        address recipient1 = vm.addr(777);
        address recipient2 = vm.addr(888);
        bytes32 userSalt = keccak256("test salt");

        // Calculate salts for different recipients with same user salt
        bytes32 calculatedSalt1 = factory.calculateSalt(recipient1, userSalt);
        bytes32 calculatedSalt2 = factory.calculateSalt(recipient2, userSalt);

        // Should be different for different recipients
        assertTrue(calculatedSalt1 != calculatedSalt2);

        // Should be deterministic - same inputs produce same output
        bytes32 calculatedSalt1Again = factory.calculateSalt(recipient1, userSalt);
        assertEq(calculatedSalt1, calculatedSalt1Again);

        // Should match expected keccak256(abi.encodePacked(recipient, salt))
        bytes32 expectedSalt1 = keccak256(abi.encodePacked(recipient1, userSalt));
        assertEq(calculatedSalt1, expectedSalt1);
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

        // Mock the bridge call to revert (no value since ETH is transferred separately)
        vm.mockCallRevert(
            mockBridge,
            abi.encodeCall(forwarder.bridgeNative, (1 ether, mainnetRecipient)),
            abi.encodeWithSelector(Forwarder.BridgeFailed.selector)
        );

        // Expect bridge failure
        vm.expectRevert(Forwarder.BridgeFailed.selector);
        forwarder.forwardNative();
    }
}

/// @title TestForwarderFactory
/// @notice Factory for TestForwarder contracts
contract TestForwarderFactory is ForwarderFactory {
    constructor() ForwarderFactory(address(new TestForwarder())) {}
}

/// @title GnosisForwarderTest
/// @notice Tests specifically for GnosisForwarder functionality
contract GnosisForwarderTest is Test {
    GnosisForwarderFactory factory;
    GnosisForwarder forwarder;
    TestERC20 testToken;
    address mainnetRecipient = vm.addr(1);

    function setUp() public {
        // Set chain ID to Gnosis Chain
        vm.chainId(100);

        // Deploy factory (which deploys its own implementation)
        factory = new GnosisForwarderFactory();

        // Deploy forwarder instance
        address payable forwarderAddr = factory.deployForwarder(mainnetRecipient, bytes32(0));
        forwarder = GnosisForwarder(forwarderAddr);

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

        GnosisForwarder newForwarder = new GnosisForwarder();
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
