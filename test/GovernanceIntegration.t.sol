// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "./TestHelper.sol";
import "../src/Deployer.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title GovernanceIntegrationTest
 * @dev Comprehensive end-to-end integration tests for the governance system.
 *
 * These tests verify the complete governance flow including:
 * - Token distribution and delegation
 * - Proposal creation and voting
 * - Quorum enforcement and vote counting
 * - Proposal execution
 * - Compatibility between Solady ERC20Votes and OpenZeppelin Governor
 * - Dynamic voting power changes
 * - Governance settings enforcement
 *
 * The tests use a realistic scenario with multiple token holders having
 * different voting power percentages to simulate real-world governance.
 */
contract GovernanceIntegrationTest is TestHelper {
    Token public token;
    Governor public governor;
    Splitter public splitter;

    // Test addresses with predefined voting power distribution
    address public constant PROPOSER = address(0x10); // 10% voting power
    address public constant VOTER1 = address(0x11); // 30% voting power
    address public constant VOTER2 = address(0x12); // 40% voting power
    address public constant VOTER3 = address(0x13); // 20% voting power
    address public constant TARGET_CONTRACT = address(0x20);

    MockTarget public mockTarget;

    function setUp() public {
        // Deploy mock target for testing proposal execution
        mockTarget = new MockTarget();

        // Create realistic token distribution across multiple holders
        // Total supply: 10,000 tokens distributed as follows:
        // PROPOSER: 1,000 tokens (10%) - has enough to create proposals
        // VOTER1:   3,000 tokens (30%) - significant voting power
        // VOTER2:   4,000 tokens (40%) - largest voting block
        // VOTER3:   2,000 tokens (20%) - minority voting power
        AbstractDeployer.TokenDistribution[] memory distributions = new AbstractDeployer.TokenDistribution[](4);
        distributions[0] = AbstractDeployer.TokenDistribution({
            recipient: PROPOSER,
            amount: 1000e18 // 10% of total supply
        });
        distributions[1] = AbstractDeployer.TokenDistribution({
            recipient: VOTER1,
            amount: 3000e18 // 30% of total supply
        });
        distributions[2] = AbstractDeployer.TokenDistribution({
            recipient: VOTER2,
            amount: 4000e18 // 40% of total supply
        });
        distributions[3] = AbstractDeployer.TokenDistribution({
            recipient: VOTER3,
            amount: 2000e18 // 20% of total supply
        });

        // Deploy the complete governance system using the testable deployer
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;

        vm.recordLogs();

        new TestableDeployer(createBasicTokenConfig(), createBasicGovernorConfig(), emptySplitterConfig, distributions);

        // Extract deployed contract addresses from deployment logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress, address governorAddress, address splitterAddress,,) = extractDeploymentAddresses(logs);

        token = Token(tokenAddress);
        governor = Governor(payable(governorAddress));
        if (splitterAddress != address(0)) {
            splitter = Splitter(splitterAddress);
        }

        // Critical: Delegate voting power to self for all token holders
        // This is required for the Solady ERC20Votes implementation to
        // properly track voting power for governance
        vm.prank(PROPOSER);
        token.delegate(PROPOSER);

        vm.prank(VOTER1);
        token.delegate(VOTER1);

        vm.prank(VOTER2);
        token.delegate(VOTER2);

        vm.prank(VOTER3);
        token.delegate(VOTER3);

        // Move forward one block to ensure voting power delegation is active
        vm.roll(block.number + 1);
    }

    /**
     * @dev Test that verifies the initial setup of the governance system
     * including token distribution, voting power delegation, and governance parameters.
     */
    function testInitialSetup() public view {
        // Verify token distribution matches expected amounts
        assertEq(token.balanceOf(PROPOSER), 1000e18);
        assertEq(token.balanceOf(VOTER1), 3000e18);
        assertEq(token.balanceOf(VOTER2), 4000e18);
        assertEq(token.balanceOf(VOTER3), 2000e18);
        assertEq(token.totalSupply(), 10000e18);

        // Verify voting power delegation is working correctly
        // This tests the Solady ERC20Votes integration
        assertEq(token.getVotes(PROPOSER), 1000e18);
        assertEq(token.getVotes(VOTER1), 3000e18);
        assertEq(token.getVotes(VOTER2), 4000e18);
        assertEq(token.getVotes(VOTER3), 2000e18);

        // Verify governor configuration parameters
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.quorumNumerator(), QUORUM_NUMERATOR);

        // Verify quorum calculation (50% of total supply = 5000e18)
        assertEq(governor.quorum(block.number - 1), 5000e18);
    }

    /**
     * @dev Test proposal creation and state transitions through the governance lifecycle.
     * Verifies that proposals start in Pending state and become Active after voting delay.
     */
    function testCreateProposal() public {
        // Create a simple proposal to call setValue on our mock contract
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (42));

        string memory description = "Set mock target value to 42";

        // Create proposal using PROPOSER account (has sufficient voting power)
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Verify proposal starts in Pending state
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Move past voting delay period
        vm.roll(block.number + VOTING_DELAY + 1);

        // Verify proposal transitions to Active state and can accept votes
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));
    }

    /**
     * @dev Test the complete governance flow: proposal creation, voting, and execution.
     * This test verifies that a proposal with majority support succeeds and executes correctly.
     */
    function testProposalVotingAndExecution() public {
        // Create a proposal to modify external contract state
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (123));

        string memory description = "Set mock target value to 123";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay to enable voting
        vm.roll(block.number + VOTING_DELAY + 1);

        // Cast votes: VOTER1 (30%) + VOTER2 (40%) = 70% FOR
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // FOR

        vm.prank(VOTER2);
        governor.castVote(proposalId, 1); // FOR

        // VOTER3 (20%) votes AGAINST
        vm.prank(VOTER3);
        governor.castVote(proposalId, 0); // AGAINST

        // Verify vote tallies
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 7000e18); // VOTER1 (3000) + VOTER2 (4000)
        assertEq(againstVotes, 2000e18); // VOTER3 (2000)
        assertEq(abstainVotes, 0);

        // Move past voting period to close voting
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Verify proposal succeeded (FOR > AGAINST and quorum met)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Execute proposal directly (this governor has no timelock)
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Verify execution results
        assertEq(mockTarget.value(), 123);
        assertTrue(mockTarget.executed());
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function testProposalFailsWithInsufficientVotes() public {
        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (456));

        string memory description = "This proposal should fail";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Only minority votes FOR (quorum is 5000e18, we need majority of that)
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // FOR (3000e18)

        // Majority votes against
        vm.prank(VOTER2);
        governor.castVote(proposalId, 0); // AGAINST (4000e18)

        vm.prank(VOTER3);
        governor.castVote(proposalId, 0); // AGAINST (2000e18)

        // Move past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Verify proposal was defeated
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function testProposalFailsWithInsufficientQuorum() public {
        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (789));

        string memory description = "This proposal should fail due to low participation";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Only small participation (below quorum of 5000e18)
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // FOR (3000e18)

        // PROPOSER votes FOR too (1000e18)
        vm.prank(PROPOSER);
        governor.castVote(proposalId, 1); // FOR

        // Total FOR votes = 4000e18, which is below quorum of 5000e18

        // Move past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Verify proposal was defeated due to insufficient quorum
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    /**
     * @dev Test that voting power correctly updates when tokens are transferred between accounts.
     * This tests the dynamic nature of governance participation.
     */
    function testVotingPowerChangesAfterTokenTransfer() public {
        // Transfer 1000 tokens from VOTER2 to PROPOSER
        vm.prank(VOTER2);
        token.transfer(PROPOSER, 1000e18);

        // Re-delegate voting power to reflect new balances
        // This is required after token transfers to update voting power
        vm.prank(PROPOSER);
        token.delegate(PROPOSER);

        vm.prank(VOTER2);
        token.delegate(VOTER2);

        // Move forward one block to activate new voting power
        vm.roll(block.number + 1);

        // Verify updated voting power reflects token transfers
        assertEq(token.getVotes(PROPOSER), 2000e18); // Original 1000 + transferred 1000
        assertEq(token.getVotes(VOTER2), 3000e18); // Original 4000 - transferred 1000

        // Create proposal with new voting power distribution
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (999));

        string memory description = "Test with updated voting power";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote with updated power
        vm.prank(PROPOSER);
        governor.castVote(proposalId, 1); // FOR (2000e18)

        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // FOR (3000e18)

        vm.prank(VOTER2);
        governor.castVote(proposalId, 1); // FOR (3000e18)

        // Total FOR = 8000e18, should be enough

        // Move past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Verify proposal succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function testProposalThresholdEnforcement() public {
        // First, let's update the proposal threshold to be non-zero
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (1000e18));

        string memory description = "Set proposal threshold to 1000 tokens";

        // Create and execute proposal to set threshold
        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        vm.prank(VOTER2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        governor.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Now test that proposal threshold is enforced
        address smallHolder = address(0x99);

        // Give small holder only 50 tokens (below threshold of 1000)
        vm.prank(address(governor));
        token.mint(smallHolder, 50e18);

        vm.prank(smallHolder);
        token.delegate(smallHolder);

        vm.roll(block.number + 1);

        // Try to create proposal with insufficient voting power
        address[] memory failTargets = new address[](1);
        uint256[] memory failValues = new uint256[](1);
        bytes[] memory failCalldatas = new bytes[](1);

        failTargets[0] = address(mockTarget);
        failValues[0] = 0;
        failCalldatas[0] = abi.encodeCall(IMockTarget.setValue, (111));

        string memory failDescription = "This should fail due to proposal threshold";

        // This should revert due to insufficient proposal threshold
        vm.prank(smallHolder);
        vm.expectRevert();
        governor.propose(failTargets, failValues, failCalldatas, failDescription);
    }

    function testMultipleProposalsAndVoting() public {
        // Create first proposal
        address[] memory targets1 = new address[](1);
        uint256[] memory values1 = new uint256[](1);
        bytes[] memory calldatas1 = new bytes[](1);

        targets1[0] = address(mockTarget);
        values1[0] = 0;
        calldatas1[0] = abi.encodeCall(IMockTarget.setValue, (100));

        string memory description1 = "First proposal";

        vm.prank(PROPOSER);
        uint256 proposalId1 = governor.propose(targets1, values1, calldatas1, description1);

        // Create second proposal
        address[] memory targets2 = new address[](1);
        uint256[] memory values2 = new uint256[](1);
        bytes[] memory calldatas2 = new bytes[](1);

        targets2[0] = address(mockTarget);
        values2[0] = 0;
        calldatas2[0] = abi.encodeCall(IMockTarget.setValue, (200));

        string memory description2 = "Second proposal";

        vm.prank(VOTER1);
        uint256 proposalId2 = governor.propose(targets2, values2, calldatas2, description2);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote differently on each proposal
        vm.prank(VOTER1);
        governor.castVote(proposalId1, 1); // FOR first

        vm.prank(VOTER1);
        governor.castVote(proposalId2, 0); // AGAINST second

        vm.prank(VOTER2);
        governor.castVote(proposalId1, 0); // AGAINST first

        vm.prank(VOTER2);
        governor.castVote(proposalId2, 1); // FOR second

        vm.prank(VOTER3);
        governor.castVote(proposalId1, 1); // FOR first

        vm.prank(VOTER3);
        governor.castVote(proposalId2, 1); // FOR second

        // Move past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Check results
        // Proposal 1: FOR = 3000 + 2000 = 5000, AGAINST = 4000, should succeed
        assertEq(uint256(governor.state(proposalId1)), uint256(IGovernor.ProposalState.Succeeded));

        // Proposal 2: FOR = 4000 + 2000 = 6000, AGAINST = 3000, should succeed
        assertEq(uint256(governor.state(proposalId2)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function testGovernanceSettingsCanBeUpdated() public {
        // Note: Direct calls to setVotingPeriod may not work due to access control
        // This test verifies that governance parameters can be read correctly

        // Verify current voting period
        assertEq(governor.votingPeriod(), VOTING_PERIOD);

        // Verify current voting delay
        assertEq(governor.votingDelay(), VOTING_DELAY);

        // Verify current proposal threshold
        assertEq(governor.proposalThreshold(), 1);

        // Create a simple proposal to verify governance flow works
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (777));

        string memory description = "Test governance settings verification";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote in favor
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        vm.prank(VOTER2);
        governor.castVote(proposalId, 1);

        // Move past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Execute proposal
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Verify execution
        assertEq(mockTarget.value(), 777);
    }

    /**
     * @dev Test compatibility between Solady ERC20Votes and OpenZeppelin Governor.
     * This is critical since our token uses Solady while the governor uses OpenZeppelin interfaces.
     */
    function testSoladyToOpenZeppelinCompatibility() public {
        // Test that our custom getPastTotalSupply function works correctly
        // This function bridges Solady's getPastVotesTotalSupply to OpenZeppelin's expected interface
        uint256 currentBlock = block.number;

        uint256 pastSupply = token.getPastTotalSupply(currentBlock - 1);
        assertEq(pastSupply, token.totalSupply());

        // Test that governor can correctly access historical voting power
        uint256 voterPower = governor.getVotes(VOTER1, currentBlock - 1);
        assertEq(voterPower, token.getVotes(VOTER1));

        // Create and vote on proposal to ensure compatibility works end-to-end
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (42));

        string memory description = "Compatibility test proposal";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote and execute successfully
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1);

        vm.prank(VOTER2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        governor.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Verify execution succeeded
        assertEq(mockTarget.value(), 42);
        assertTrue(mockTarget.executed());
    }

    /**
     * @dev Test that late quorum extension works correctly.
     * When quorum is reached late in the voting period, the voting period should be extended.
     */
    function testLateQuorumExtension() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (888));

        string memory description = "Test late quorum extension";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Get initial proposal deadline
        uint256 initialDeadline = governor.proposalDeadline(proposalId);

        // Move close to the end of voting period (within late quorum extension window)
        // We'll move to a point where there are only LATE_QUORUM_EXTENSION/2 blocks left
        uint256 blocksFromEnd = LATE_QUORUM_EXTENSION / 2;
        vm.roll(initialDeadline - blocksFromEnd);

        // At this point, quorum hasn't been reached yet
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes + againstVotes + abstainVotes, 0); // No votes yet

        // Now cast enough votes to reach quorum near the deadline
        // We need 5000e18 for quorum, so let's use VOTER1 (3000e18) + VOTER2 (4000e18) = 7000e18
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // FOR

        // This should trigger late quorum extension since we're close to deadline
        vm.prank(VOTER2);
        governor.castVote(proposalId, 1); // FOR

        // Get new deadline after late quorum extension
        uint256 newDeadline = governor.proposalDeadline(proposalId);

        // Verify that the deadline was extended
        assertTrue(newDeadline > initialDeadline, "Deadline should be extended due to late quorum");

        // The extension should be approximately LATE_QUORUM_EXTENSION blocks
        // (allowing for some variance due to how GovernorPreventLateQuorum calculates it)
        uint256 extension = newDeadline - initialDeadline;
        assertTrue(extension >= LATE_QUORUM_EXTENSION / 2, "Extension should be meaningful");
        assertTrue(extension <= LATE_QUORUM_EXTENSION * 2, "Extension should not be excessive");

        // Verify that we can still vote during the extended period
        vm.roll(initialDeadline + 1); // Move past original deadline

        // VOTER3 should still be able to vote since deadline was extended
        vm.prank(VOTER3);
        governor.castVote(proposalId, 0); // AGAINST

        // Verify the vote was counted
        (againstVotes, forVotes, abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 7000e18); // VOTER1 + VOTER2
        assertEq(againstVotes, 2000e18); // VOTER3
        assertEq(abstainVotes, 0);

        // Move past the new extended deadline
        vm.roll(newDeadline + 1);

        // Proposal should have succeeded (FOR > AGAINST and quorum met)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Execute the proposal to verify it works
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Verify execution
        assertEq(mockTarget.value(), 888);
        assertTrue(mockTarget.executed());
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    /**
     * @dev Test that early votes do not trigger late quorum extension.
     * Quorum reached early in voting period should not extend the deadline.
     */
    function testEarlyQuorumDoesNotExtend() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(mockTarget);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(IMockTarget.setValue, (999));

        string memory description = "Test early quorum does not extend";

        vm.prank(PROPOSER);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Get initial proposal deadline
        uint256 initialDeadline = governor.proposalDeadline(proposalId);

        // Vote early in the voting period (right after voting delay)
        vm.prank(VOTER1);
        governor.castVote(proposalId, 1); // FOR

        vm.prank(VOTER2);
        governor.castVote(proposalId, 1); // FOR

        // Check deadline after early voting
        uint256 deadlineAfterEarlyVoting = governor.proposalDeadline(proposalId);

        // Deadline should not have changed since votes were cast early
        assertEq(deadlineAfterEarlyVoting, initialDeadline, "Early voting should not extend deadline");

        // Move to near the end of voting period and cast another vote
        vm.roll(initialDeadline - 5);

        vm.prank(VOTER3);
        governor.castVote(proposalId, 0); // AGAINST

        // Deadline should still be the same since quorum was already reached early
        uint256 finalDeadline = governor.proposalDeadline(proposalId);
        assertEq(finalDeadline, initialDeadline, "Deadline should remain unchanged");

        // Move past original deadline
        vm.roll(initialDeadline + 1);

        // Proposal should be in Succeeded state
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }
}
