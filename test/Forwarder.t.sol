// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Forwarder.sol";
import "../src/ForwarderFactory.sol";
import "../src/forwarders/GnosisChainForwarder.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

/// @title MockERC20
/// @notice Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title MockForwarder
/// @notice Simple mock forwarder implementation for testing
contract MockForwarder is Forwarder {
    mapping(address => uint256) public bridgedTokens;
    mapping(address => uint256) public bridgedNative;

    function _bridgeToken(address token, uint256 amount, address recipient) internal override {
        // Record the bridge operation
        bridgedTokens[recipient] += amount;
        // Simulate token consumption by burning them
        ERC20(token).transfer(address(0), amount);
    }

    function _bridgeNative(uint256 amount, address recipient) internal override {
        // Record the bridge operation
        bridgedNative[recipient] += amount;
        // Simulate native token consumption by sending to burn address
        payable(address(0x000000000000000000000000000000000000dEaD)).transfer(amount);
    }

    function getBridgedTokens(address recipient) external view returns (uint256) {
        return bridgedTokens[recipient];
    }

    function getBridgedNative(address recipient) external view returns (uint256) {
        return bridgedNative[recipient];
    }
}

/// @title ForwarderTest
/// @notice Test suite for Forwarder contracts
contract ForwarderTest is Test {
    ForwarderFactory factory;
    MockForwarder implementation;
    MockERC20 testToken;
    
    address mainnetRecipient = address(0x1234567890123456789012345678901234567890);
    address user = address(0x1111111111111111111111111111111111111111);
    
    event ForwarderDeployed(
        address indexed implementation,
        address indexed mainnetRecipient,
        address indexed forwarder,
        bytes32 salt
    );
    
    event TokensForwarded(address indexed token, uint256 amount, address indexed recipient);
    event NativeForwarded(uint256 amount, address indexed recipient);

    function setUp() public {
        // Deploy factory
        factory = new ForwarderFactory();
        
        // Deploy mock forwarder implementation
        implementation = new MockForwarder();
        
        // Deploy test token
        testToken = new MockERC20("Test Token", "TEST", 18);
    }

    function testForwarderInitialization() public {
        MockForwarder forwarder = new MockForwarder();
        
        // Test initialization
        forwarder.initialize(mainnetRecipient);
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);
        assertTrue(forwarder.initialized());
        
        // Test double initialization fails
        vm.expectRevert(Forwarder.AlreadyInitialized.selector);
        forwarder.initialize(mainnetRecipient);
    }

    function testInvalidInitialization() public {
        MockForwarder forwarder = new MockForwarder();
        
        // Test initialization with zero address fails
        vm.expectRevert("Invalid recipient");
        forwarder.initialize(address(0));
    }

    function testFactoryDeploymentDirect() public {
        // Predict forwarder address
        address predictedAddress = factory.predictForwarderAddressDirect(address(implementation), mainnetRecipient);
        
        // Deploy forwarder
        vm.expectEmit(true, true, true, true);
        emit ForwarderDeployed(address(implementation), mainnetRecipient, predictedAddress, keccak256(abi.encodePacked(mainnetRecipient)));
        
        address payable forwarderAddress = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        
        // Verify addresses match
        assertEq(predictedAddress, forwarderAddress);
        
        // Verify forwarder is registered
        assertEq(factory.getForwarder(address(implementation), mainnetRecipient), forwarderAddress);
        assertTrue(factory.forwarderExists(address(implementation), mainnetRecipient));
        
        // Verify forwarder is initialized
        MockForwarder forwarder = MockForwarder(forwarderAddress);
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);
    }

    function testFactoryDeploymentWithArgs() public {
        // Predict forwarder address
        address predictedAddress = factory.predictForwarderAddress(address(implementation), mainnetRecipient);
        
        // Deploy forwarder
        address payable forwarderAddress = factory.deployForwarder(address(implementation), mainnetRecipient);
        
        // Verify addresses match
        assertEq(predictedAddress, forwarderAddress);
        
        // Verify forwarder is registered
        assertEq(factory.getForwarder(address(implementation), mainnetRecipient), forwarderAddress);
        assertTrue(factory.forwarderExists(address(implementation), mainnetRecipient));
        
        // Verify forwarder is initialized
        MockForwarder forwarder = MockForwarder(forwarderAddress);
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);
    }

    function testFactoryPreventsDuplicateDeployment() public {
        // Deploy first forwarder
        factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        
        // Try to deploy again - should fail
        vm.expectRevert(ForwarderFactory.ForwarderAlreadyExists.selector);
        factory.deployForwarderDirect(address(implementation), mainnetRecipient);
    }

    function testGetOrDeployForwarder() public {
        // First call should deploy
        address payable forwarder1 = factory.getOrDeployForwarder(address(implementation), mainnetRecipient);
        assertTrue(forwarder1 != address(0));
        
        // Second call should return existing
        address payable forwarder2 = factory.getOrDeployForwarder(address(implementation), mainnetRecipient);
        assertEq(forwarder1, forwarder2);
    }

    function testTokenForwarding() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Use deal to set token balance directly
        deal(address(testToken), forwarderAddr, 1000e18);
        
        // Forward tokens
        vm.expectEmit(true, true, false, true);
        emit TokensForwarded(address(testToken), 1000e18, mainnetRecipient);
        
        forwarder.forwardToken(address(testToken));
        
        // Verify tokens were bridged
        assertEq(forwarder.getBridgedTokens(mainnetRecipient), 1000e18);
    }

    function testTokenForwardingSpecificAmount() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Use deal to set token balance directly
        deal(address(testToken), forwarderAddr, 1000e18);
        
        // Forward specific amount
        vm.expectEmit(true, true, false, true);
        emit TokensForwarded(address(testToken), 500e18, mainnetRecipient);
        
        forwarder.forwardToken(address(testToken), 500e18);
        
        // Verify correct amount was bridged
        assertEq(forwarder.getBridgedTokens(mainnetRecipient), 500e18);
        // Verify remaining balance (tokens were transferred to address(0))
        assertEq(testToken.balanceOf(forwarderAddr), 500e18);
    }

    function testTokenForwardingInsufficientBalance() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Try to forward more than available (balance is 0)
        vm.expectRevert("Insufficient balance");
        forwarder.forwardToken(address(testToken), 1000e18);
    }

    function testTokenForwardingZeroAmount() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Try to forward zero amount
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardToken(address(testToken), 0);
        
        // Try to forward when balance is zero
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardToken(address(testToken));
    }

    function testNativeForwarding() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Use vm.deal to set native balance directly
        vm.deal(forwarderAddr, 1 ether);
        
        // Forward native tokens
        vm.expectEmit(true, false, false, true);
        emit NativeForwarded(1 ether, mainnetRecipient);
        
        forwarder.forwardNative();
        
        // Verify native tokens were bridged
        assertEq(forwarder.getBridgedNative(mainnetRecipient), 1 ether);
    }

    function testNativeForwardingSpecificAmount() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Use vm.deal to set native balance directly
        vm.deal(forwarderAddr, 1 ether);
        
        // Forward specific amount
        vm.expectEmit(true, false, false, true);
        emit NativeForwarded(0.5 ether, mainnetRecipient);
        
        forwarder.forwardNative(0.5 ether);
        
        // Verify correct amount was bridged
        assertEq(forwarder.getBridgedNative(mainnetRecipient), 0.5 ether);
        // Verify remaining balance
        assertEq(forwarderAddr.balance, 0.5 ether);
    }

    function testNativeForwardingZeroAmount() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Try to forward zero amount
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardNative(0);
        
        // Try to forward when balance is zero
        vm.expectRevert(Forwarder.ZeroAmount.selector);
        forwarder.forwardNative();
    }

    function testBatchForwardTokens() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Create multiple test tokens
        MockERC20 token2 = new MockERC20("Test Token 2", "TEST2", 6);
        MockERC20 token3 = new MockERC20("Test Token 3", "TEST3", 8);
        
        // Use deal to set token balances directly
        deal(address(testToken), forwarderAddr, 1000e18);
        deal(address(token2), forwarderAddr, 500e6);
        deal(address(token3), forwarderAddr, 250e8);
        
        // Prepare token array
        address[] memory tokens = new address[](3);
        tokens[0] = address(testToken);
        tokens[1] = address(token2);
        tokens[2] = address(token3);
        
        // Batch forward tokens
        forwarder.batchForwardTokens(tokens);
        
        // Verify all tokens were bridged (total amount regardless of decimals)
        assertEq(forwarder.getBridgedTokens(mainnetRecipient), 1000e18 + 500e6 + 250e8);
    }

    function testGetBalance() public {
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        MockForwarder forwarder = MockForwarder(forwarderAddr);
        
        // Test ERC20 balance
        deal(address(testToken), forwarderAddr, 1000e18);
        assertEq(forwarder.getBalance(address(testToken)), 1000e18);
        
        // Test native balance
        vm.deal(forwarderAddr, 1 ether);
        assertEq(forwarder.getBalance(address(0)), 1 ether);
    }

    function testUninitializedForwarderFails() public {
        MockForwarder uninitializedForwarder = new MockForwarder();
        
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
        // Deploy forwarder
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        
        // Test that forwarder can receive native tokens
        uint256 initialBalance = forwarderAddr.balance;
        
        (bool success, ) = forwarderAddr.call{value: 1 ether}("");
        assertTrue(success);
        
        assertEq(forwarderAddr.balance, initialBalance + 1 ether);
    }

    function testBatchDeployForwarders() public {
        address[] memory implementations = new address[](2);
        address[] memory recipients = new address[](2);
        
        implementations[0] = address(implementation);
        implementations[1] = address(implementation);
        recipients[0] = mainnetRecipient;
        recipients[1] = address(0x9999999999999999999999999999999999999999);
        
        address payable[] memory forwarders = factory.batchDeployForwarders(implementations, recipients);
        
        assertEq(forwarders.length, 2);
        assertTrue(forwarders[0] != address(0));
        assertTrue(forwarders[1] != address(0));
        assertTrue(forwarders[0] != forwarders[1]);
    }

    function testDeterministicAddresses() public {
        // Deploy forwarder for same recipient using direct method
        address payable forwarder1 = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        
        // Create new factory (simulating deployment on different chain)
        ForwarderFactory factory2 = new ForwarderFactory();
        
        // Predict address from both factories
        address predicted1 = factory.predictForwarderAddressDirect(address(implementation), mainnetRecipient);
        address predicted2 = factory2.predictForwarderAddressDirect(address(implementation), mainnetRecipient);
        
        // The prediction should match the deployed address from the same factory
        assertEq(forwarder1, predicted1);
        
        // Note: Addresses will be different between factories because CREATE2 includes deployer address
        // This is expected behavior - each factory creates different addresses
        assertTrue(predicted1 != predicted2);
        
        // Deploy from second factory and verify it matches its prediction
        address payable forwarder2 = factory2.deployForwarderDirect(address(implementation), mainnetRecipient);
        assertEq(forwarder2, predicted2);
    }
}

/// @title GnosisChainForwarderTest
/// @notice Test suite specifically for GnosisChainForwarder
contract GnosisChainForwarderTest is Test {
    GnosisChainForwarder forwarder;
    ForwarderFactory factory;
    address mainnetRecipient = address(0x1234567890123456789012345678901234567890);
    
    function setUp() public {
        // Set chain ID to Gnosis Chain
        vm.chainId(100);
        
        // Deploy factory and implementation
        factory = new ForwarderFactory();
        GnosisChainForwarder implementation = new GnosisChainForwarder();
        
        // Deploy forwarder instance
        address payable forwarderAddr = factory.deployForwarderDirect(address(implementation), mainnetRecipient);
        forwarder = GnosisChainForwarder(forwarderAddr);
    }

    function testGnosisChainId() public view {
        assertEq(forwarder.getChainId(), 100);
        assertEq(forwarder.GNOSIS_CHAIN_ID(), 100);
    }

    function testBridgeConfiguration() public view {
        assertTrue(forwarder.isBridgeConfigured());
        assertTrue(forwarder.OMNIBRIDGE() != address(0));
        assertTrue(forwarder.XDAI_BRIDGE() != address(0));
        assertTrue(forwarder.AMB_BRIDGE() != address(0));
    }

    function testInvalidChainDeployment() public {
        // Set chain ID to something other than Gnosis Chain
        vm.chainId(1);
        
        // Deploy implementation
        GnosisChainForwarder implementation = new GnosisChainForwarder();
        
        // Should revert when trying to initialize on wrong chain
        vm.expectRevert(GnosisChainForwarder.InvalidChain.selector);
        implementation.initialize(mainnetRecipient);
    }

    function testEmergencyRecover() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 18);
        
        // Use deal to give tokens to forwarder
        deal(address(testToken), address(forwarder), 1000e18);
        
        // Only mainnet recipient should be able to recover
        vm.prank(address(0x9999));
        vm.expectRevert("Only recipient can recover");
        forwarder.emergencyRecover(address(testToken), address(0x9999));
        
        // Mainnet recipient can recover
        vm.prank(mainnetRecipient);
        forwarder.emergencyRecover(address(testToken), mainnetRecipient);
        
        // Verify tokens were recovered
        assertEq(testToken.balanceOf(mainnetRecipient), 1000e18);
        assertEq(testToken.balanceOf(address(forwarder)), 0);
    }

    function testEmergencyRecoverNative() public {
        // Use vm.deal to give native tokens to forwarder
        vm.deal(address(forwarder), 1 ether);
        
        uint256 initialBalance = mainnetRecipient.balance;
        
        // Recover native tokens
        vm.prank(mainnetRecipient);
        forwarder.emergencyRecover(address(0), mainnetRecipient);
        
        // Verify native tokens were recovered
        assertEq(mainnetRecipient.balance, initialBalance + 1 ether);
        assertEq(address(forwarder).balance, 0);
    }

    function testEmergencyRecoverInvalidAddress() public {
        vm.prank(mainnetRecipient);
        vm.expectRevert("Invalid recovery address");
        forwarder.emergencyRecover(address(0), address(0));
    }

    function testInitialization() public view {
        assertTrue(forwarder.initialized());
        assertEq(forwarder.mainnetRecipient(), mainnetRecipient);
        assertEq(forwarder.getChainId(), 100);
    }

    function testForwarderCanReceiveTokens() public {
        MockERC20 testToken = new MockERC20("Test Token", "TEST", 18);
        
        // Use deal to mint and transfer tokens to forwarder
        deal(address(testToken), address(forwarder), 1000e18);
        
        // Verify forwarder received tokens
        assertEq(testToken.balanceOf(address(forwarder)), 1000e18);
        assertEq(forwarder.getBalance(address(testToken)), 1000e18);
    }

    function testForwarderCanReceiveNative() public {
        // Use vm.deal to send native tokens to forwarder
        vm.deal(address(forwarder), 1 ether);
        
        // Verify forwarder received native tokens
        assertEq(address(forwarder).balance, 1 ether);
        assertEq(forwarder.getBalance(address(0)), 1 ether);
    }
}