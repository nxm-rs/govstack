// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "./TestHelper.sol";
import "../src/Deployer.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title OtocoManagerTest
 * @dev Comprehensive tests for the OtocoManager extension functionality.
 *
 * These tests verify:
 * - Manager is correctly set to Governor address upon deployment
 * - getManager() returns the correct manager address
 * - setManager() requires governance and works correctly
 * - isManagerProposal() stub functionality
 * - Manager address can be changed through governance
 * - Proper event emission for manager changes
 */
contract OtocoManagerTest is TestHelper {
    Token public token;
    Governor public governor;

    // Test addresses
    address public constant PROPOSER = address(0x10);
    address public constant VOTER1 = address(0x11);
    address public constant VOTER2 = address(0x12);
    address public constant NEW_MANAGER = address(0x20);

    function setUp() public {
        // Create token distribution for governance testing
        AbstractDeployer.TokenDistribution[] memory distributions = new AbstractDeployer.TokenDistribution[](3);
        distributions[0] = AbstractDeployer.TokenDistribution({
            recipient: PROPOSER,
            amount: 1000e18 // 10% - enough to create proposals
        });
        distributions[1] = AbstractDeployer.TokenDistribution({
            recipient: VOTER1,
            amount: 5000e18 // 50% - enough to reach quorum alone
        });
        distributions[2] = AbstractDeployer.TokenDistribution({
            recipient: VOTER2,
            amount: 4000e18 // 40% - additional voting power
        });

        // Deploy governance system
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;

        vm.recordLogs();
        new TestableDeployer(createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, distributions);

        // Extract deployed addresses
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress, address governorAddress,,,) = extractDeploymentAddresses(logs);

        token = Token(tokenAddress);
        governor = Governor(payable(governorAddress));

        // Delegate voting power
        vm.prank(PROPOSER);
        token.delegate(PROPOSER);

        vm.prank(VOTER1);
        token.delegate(VOTER1);

        vm.prank(VOTER2);
        token.delegate(VOTER2);

        // Move forward one block to activate delegation
        vm.roll(block.number + 1);
    }

    /// @notice Test that the Governor sets itself as Manager upon deployment
    function testInitialManagerSetup() public view {
        // Verify that the Governor address is set as the Manager
        assertEq(governor.getManager(), address(governor));
    }

    /// @notice Test getManager() function returns correct address
    function testGetManager() public view {
        address manager = governor.getManager();
        assertEq(manager, address(governor));
    }

    /// @notice Test that setManager() requires governance (onlyGovernance modifier)
    function testSetManagerRequiresGovernance() public {
        // Attempt to call setManager directly should fail
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(this)));
        governor.setManager(NEW_MANAGER);

        // Test with different addresses
        vm.prank(PROPOSER);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, PROPOSER));
        governor.setManager(NEW_MANAGER);

        vm.prank(VOTER1);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, VOTER1));
        governor.setManager(NEW_MANAGER);
    }

    /// @notice Test setManager() through governance proposal
    function testSetManagerThroughGovernance() public {
        // Create proposal to change manager
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(governor.setManager.selector, NEW_MANAGER);

        // Create proposal
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Change Manager to NEW_MANAGER");

        // Wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote in favor (VOTER1 has 50% which is enough for quorum and majority)
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // 1 = For

        // Wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Verify proposal succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Expect ManagerSet event
        vm.expectEmit(true, true, false, true);
        emit ManagerSet(address(governor), NEW_MANAGER);

        // Execute proposal
        governor.execute(targets, values, calldatas, keccak256(bytes("Change Manager to NEW_MANAGER")));

        // Verify manager was changed
        assertEq(governor.getManager(), NEW_MANAGER);
    }

    /// @notice Test ManagerSet event emission
    function testManagerSetEventEmission() public {
        // Create proposal to change manager
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(governor.setManager.selector, NEW_MANAGER);

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Change Manager Event Test");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Expect specific event emission
        vm.expectEmit(true, true, false, true);
        emit ManagerSet(address(governor), NEW_MANAGER);

        governor.execute(targets, values, calldatas, keccak256(bytes("Change Manager Event Test")));
    }

    /// @notice Test isManagerProposal() stub function
    function testIsManagerProposal() public view {
        // Test with various proposal IDs - should always return false as it's a stub
        assertEq(governor.isManagerProposal(0), false);
        assertEq(governor.isManagerProposal(1), false);
        assertEq(governor.isManagerProposal(999), false);
        assertEq(governor.isManagerProposal(type(uint256).max), false);
    }

    /// @notice Test multiple manager changes
    function testMultipleManagerChanges() public {
        address MANAGER2 = address(0x21);
        address MANAGER3 = address(0x22);

        // First change: Governor -> NEW_MANAGER
        _changeManagerThroughGovernance(NEW_MANAGER, "Change to NEW_MANAGER");
        assertEq(governor.getManager(), NEW_MANAGER);

        // Add delay between proposals to prevent state conflicts
        vm.roll(block.number + 10);

        // Second change: NEW_MANAGER -> MANAGER2
        _changeManagerThroughGovernance(MANAGER2, "Change to MANAGER2");
        assertEq(governor.getManager(), MANAGER2);

        // Add delay between proposals to prevent state conflicts
        vm.roll(block.number + 10);

        // Third change: MANAGER2 -> MANAGER3
        _changeManagerThroughGovernance(MANAGER3, "Change to MANAGER3");
        assertEq(governor.getManager(), MANAGER3);

        // Add delay between proposals to prevent state conflicts
        vm.roll(block.number + 10);

        // Change back to Governor
        _changeManagerThroughGovernance(address(governor), "Change back to Governor");
        assertEq(governor.getManager(), address(governor));
    }

    /// @notice Test setting manager to zero address
    function testSetManagerToZeroAddress() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(governor.setManager.selector, address(0));

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Set Manager to Zero Address");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // This should work - the extension doesn't prevent setting to zero address
        governor.execute(targets, values, calldatas, keccak256(bytes("Set Manager to Zero Address")));

        assertEq(governor.getManager(), address(0));
    }

    /// @notice Test manager functionality persists across multiple proposals
    function testManagerPersistenceAcrossProposals() public {
        // Change manager first
        _changeManagerThroughGovernance(NEW_MANAGER, "Initial Manager Change");
        assertEq(governor.getManager(), NEW_MANAGER);

        // Create and execute another unrelated proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, VOTER2, 1000e18);

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Mint tokens");

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        governor.execute(targets, values, calldatas, keccak256(bytes("Mint tokens")));

        // Manager should still be NEW_MANAGER
        assertEq(governor.getManager(), NEW_MANAGER);
    }

    /// @notice Helper function to change manager through governance
    function _changeManagerThroughGovernance(address newManager, string memory description) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(governor.setManager.selector, newManager);

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote with sufficient power to pass
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        // Wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Verify proposal succeeded before execution
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Execute proposal
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    /// @notice Event to match the one in OtocoManager
    event ManagerSet(address indexed oldManager, address indexed newManager);
}
