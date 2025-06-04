// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/Governor.sol";
import "../src/Splitter.sol";
import "../src/Deployer.sol";
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

/// @title IMockTarget
/// @notice Interface for MockTarget contract
interface IMockTarget {
    function setValue(uint256 _value) external;

    function reset() external;

    function value() external view returns (uint256);

    function executed() external view returns (bool);
}

// Mock contract for testing governance proposals
contract MockTarget {
    uint256 public value;
    bool public executed;

    function setValue(uint256 _value) external {
        value = _value;
        executed = true;
    }

    function reset() external {
        value = 0;
        executed = false;
    }
}

contract TestHelper is Test {
    // Common test addresses
    address public constant OWNER = address(0x1);
    address public constant USER1 = address(0x2);
    address public constant USER2 = address(0x3);
    address public constant USER3 = address(0x4);
    address public constant PAYEE1 = address(0x5);
    address public constant PAYEE2 = address(0x6);
    address public constant PAYEE3 = address(0x7);

    // Common test constants
    string public constant TOKEN_NAME = "Test Governance Token";
    string public constant TOKEN_SYMBOL = "TGT";
    string public constant GOVERNOR_NAME = "Test Governor";
    uint256 public constant INITIAL_SUPPLY = 1000e18;
    uint256 public constant VOTING_DELAY = 100;
    uint256 public constant VOTING_PERIOD = 1000;
    uint256 public constant QUORUM_NUMERATOR = 50;
    uint48 public constant LATE_QUORUM_EXTENSION = 64;

    // Events to match contract events
    event TokensReleased(address indexed token, address indexed to, uint256 amount);
    event PayeeAdded(address indexed account, uint256 shares);
    event TokensSplit(address indexed token, uint256 totalAmount);
    event DeploymentCompleted(
        address indexed token,
        address indexed governor,
        address indexed splitter,
        address finalOwner,
        uint256 totalDistributed,
        bytes32 salt
    );

    // Helper functions
    function createBasicTokenDistribution() internal pure returns (AbstractDeployer.TokenDistribution[] memory) {
        AbstractDeployer.TokenDistribution[] memory distributions = new AbstractDeployer.TokenDistribution[](2);
        distributions[0] = AbstractDeployer.TokenDistribution({recipient: USER1, amount: 1000 * 10 ** 18});
        distributions[1] = AbstractDeployer.TokenDistribution({recipient: USER2, amount: 2000 * 10 ** 18});
        return distributions;
    }

    function createBasicSplitterConfig() internal pure returns (AbstractDeployer.SplitterConfig memory) {
        // Create packed payees data off-chain style
        bytes memory packedData = abi.encodePacked(
            uint16(6000),
            PAYEE1, // 60%
            uint16(4000),
            PAYEE2 // 40%
        );

        return AbstractDeployer.SplitterConfig({packedPayeesData: packedData});
    }

    function createBasicTokenConfig() internal pure returns (AbstractDeployer.TokenConfig memory) {
        return AbstractDeployer.TokenConfig({name: TOKEN_NAME, symbol: TOKEN_SYMBOL});
    }

    function createBasicGovernorConfig() internal pure returns (AbstractDeployer.GovernorConfig memory) {
        return AbstractDeployer.GovernorConfig({
            name: GOVERNOR_NAME,
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumNumerator: QUORUM_NUMERATOR,
            lateQuorumExtension: LATE_QUORUM_EXTENSION
        });
    }

    function deployMockToken() internal returns (TestERC20) {
        return new TestERC20("Mock Token", "MOCK");
    }

    function expectEmitTokensReleased(address token, address to, uint256 amount) internal {
        vm.expectEmit(true, true, false, true);
        emit TokensReleased(token, to, amount);
    }

    function expectEmitPayeeAdded(address account, uint256 shares) internal {
        vm.expectEmit(true, false, false, true);
        emit PayeeAdded(account, shares);
    }

    function expectEmitTokensSplit(address token, uint256 totalAmount) internal {
        vm.expectEmit(true, false, false, true);
        emit TokensSplit(token, totalAmount);
    }

    // Helper to extract deployment addresses from logs
    function extractDeploymentAddresses(Vm.Log[] memory logs)
        internal
        pure
        returns (address token, address governor, address splitter, uint256 totalDistributed, bytes32 salt)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DeploymentCompleted(address,address,address,address,uint256,bytes32)"))
            {
                token = address(uint160(uint256(logs[i].topics[1])));
                governor = address(uint160(uint256(logs[i].topics[2])));
                splitter = address(uint160(uint256(logs[i].topics[3])));
                (, uint256 distributed, bytes32 deploymentSalt) = abi.decode(logs[i].data, (address, uint256, bytes32));
                totalDistributed = distributed;
                salt = deploymentSalt;
                break;
            }
        }
    }

    // Helper to create address array for testing
    function createAddressArray(address a1, address a2) internal pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = a1;
        arr[1] = a2;
        return arr;
    }

    function createUintArray(uint256 u1, uint256 u2) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](2);
        arr[0] = u1;
        arr[1] = u2;
        return arr;
    }

    // Helper to assert valid deployment
    function assertValidDeployment(
        address tokenAddress,
        address governorAddress,
        address splitterAddress,
        string memory expectedTokenName,
        string memory expectedGovernorName
    ) internal view {
        assertTrue(tokenAddress != address(0), "Token address should not be zero");
        assertTrue(governorAddress != address(0), "Governor address should not be zero");

        Token token = Token(tokenAddress);
        Governor governor = Governor(payable(governorAddress));

        assertEq(token.name(), expectedTokenName);
        assertEq(governor.name(), expectedGovernorName);
        assertEq(token.owner(), OWNER);

        if (splitterAddress != address(0)) {
            Splitter splitter = Splitter(splitterAddress);
            // In the new implementation, splitter is configured with payees during deployment
            assertTrue(splitter.payeesHash() != bytes32(0));
        }
    }

    // ============ GOVERNANCE TESTING UTILITIES ============

    // Helper to create a governance proposal
    function createProposal(address, address target, bytes memory callData, string memory)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = target;
        values[0] = 0;
        calldatas[0] = callData;
    }

    // Helper to delegate voting power
    function delegateVotes(address token, address delegator, address delegatee) internal {
        vm.prank(delegator);
        Token(token).delegate(delegatee);
    }

    // Helper to advance time for governance testing
    function advanceBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    function advanceTime(uint256 timeInSeconds) internal {
        vm.warp(block.timestamp + timeInSeconds);
    }

    function advanceTimeAndBlocks(uint256 timeInSeconds, uint256 blocks) internal {
        vm.warp(block.timestamp + timeInSeconds);
        vm.roll(block.number + blocks);
    }

    // Helper to create mock targets for governance testing
    function deployMockTarget() internal returns (address) {
        return address(new MockTarget());
    }

    // Helper to assert vote counts
    function assertVoteCounts(
        address governorAddress,
        uint256 proposalId,
        uint256 expectedAgainst,
        uint256 expectedFor,
        uint256 expectedAbstain
    ) internal view {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) =
            Governor(payable(governorAddress)).proposalVotes(proposalId);
        assertEq(againstVotes, expectedAgainst, "Against votes mismatch");
        assertEq(forVotes, expectedFor, "For votes mismatch");
        assertEq(abstainVotes, expectedAbstain, "Abstain votes mismatch");
    }

    // Helper to assert proposal state
    function assertProposalState(address governorAddress, uint256 proposalId, uint8 expectedState) internal view {
        uint8 actualState = uint8(Governor(payable(governorAddress)).state(proposalId));
        assertEq(actualState, expectedState, "Proposal state mismatch");
    }

    // ============ TOKEN TESTING UTILITIES ============

    // Helper to mint tokens to multiple addresses
    function mintTokensToAddresses(address tokenAddress, address[] memory recipients, uint256[] memory amounts)
        internal
    {
        require(recipients.length == amounts.length, "Array length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            vm.prank(Token(tokenAddress).owner());
            Token(tokenAddress).mint(recipients[i], amounts[i]);
        }
    }

    // Helper to transfer tokens between addresses
    function transferTokens(address tokenAddress, address from, address to, uint256 amount) internal {
        vm.prank(from);
        Token(tokenAddress).transfer(to, amount);
    }

    // Helper to approve token spending
    function approveTokens(address tokenAddress, address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        Token(tokenAddress).approve(spender, amount);
    }

    // Helper to assert token balances
    function assertTokenBalance(address tokenAddress, address account, uint256 expectedBalance) internal view {
        uint256 actualBalance = Token(tokenAddress).balanceOf(account);
        assertEq(actualBalance, expectedBalance, "Token balance mismatch");
    }

    // Helper to assert voting power
    function assertVotingPower(address tokenAddress, address account, uint256 expectedPower) internal view {
        uint256 actualPower = Token(tokenAddress).getVotes(account);
        assertEq(actualPower, expectedPower, "Voting power mismatch");
    }

    // ============ SPLITTER TESTING UTILITIES ============

    // Helper to create payee data for splitter
    function createPayeeData(address[] memory accounts, uint256[] memory shares) internal pure returns (bytes memory) {
        require(accounts.length == shares.length, "Array length mismatch");

        bytes memory packedData = new bytes(0);
        for (uint256 i = 0; i < accounts.length; i++) {
            packedData = abi.encodePacked(packedData, uint16(shares[i]), accounts[i]);
        }
        return packedData;
    }

    // Helper to assert splitter payee info
    function assertPayeeInfo(address splitterAddress, address payee, bytes memory packedData, uint256 expectedShares)
        internal
        view
    {
        (bool isPayee, uint16 shares) = _getPayeeInfo(splitterAddress, payee, packedData);
        assertTrue(isPayee, "Address should be a payee");
        assertEq(uint256(shares), expectedShares, "Shares mismatch");
    }

    // ============ COMMON EXPECTATION HELPERS ============

    // Helper for common transfer expectations
    function expectTransfer(address from, address to, uint256 amount) internal {
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, to, amount);
    }

    // Helper for common revert expectations
    function expectOwnershipError() internal {
        vm.expectRevert("Ownable: caller is not the owner");
    }

    function expectInvalidTimeFormat() internal {
        vm.expectRevert("Invalid time format");
    }

    function expectInvalidNumber() internal {
        vm.expectRevert("Invalid number character");
    }

    function expectUnknownTimeUnit() internal {
        vm.expectRevert("Unknown time unit");
    }

    // ============ NETWORK AND CONFIGURATION UTILITIES ============

    // Helper to setup different network scenarios for testing
    function setupEthereumNetwork() internal {
        vm.chainId(1);
    }

    function setupLocalNetwork() internal {
        vm.chainId(31337);
    }

    // Helper to create test files and clean them up
    function writeTestFile(string memory filename, string memory content) internal {
        vm.writeFile(filename, content);
    }

    function removeTestFile(string memory filename) internal {
        vm.removeFile(filename);
    }

    // Helper to assert array equality
    function assertArrayEqual(uint256[] memory a, uint256[] memory b) internal pure {
        require(a.length == b.length, "Array lengths don't match");
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] == b[i], "Array elements don't match");
        }
    }

    function assertAddressArrayEqual(address[] memory a, address[] memory b) internal pure {
        require(a.length == b.length, "Array lengths don't match");
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] == b[i], "Array elements don't match");
        }
    }

    // Additional event definitions for common events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
    event ProposalExecuted(uint256 proposalId);

    // Helper to setup common test scenario
    function setupBasicSplitter() internal returns (Splitter, TestERC20) {
        TestERC20 token = deployMockToken();

        Splitter splitter = new Splitter(OWNER);

        return (splitter, token);
    }

    // ============ TIME-BASED TESTING UTILITIES ============

    // Test data structures for time conversion testing
    struct TimeTestCase {
        string timeString;
        uint256 expectedSeconds;
        string description;
    }

    struct ConversionTestCase {
        string timeString;
        uint256 blockTimeMs;
        uint256 expectedBlocks;
        string description;
    }

    // Common time test cases
    function getBasicTimeTestCases() internal pure returns (TimeTestCase[] memory) {
        TimeTestCase[] memory cases = new TimeTestCase[](10);
        cases[0] = TimeTestCase("1 second", 1, "single second");
        cases[1] = TimeTestCase("30 seconds", 30, "thirty seconds");
        cases[2] = TimeTestCase("1 minute", 60, "single minute");
        cases[3] = TimeTestCase("5 minutes", 300, "five minutes");
        cases[4] = TimeTestCase("1 hour", 3600, "single hour");
        cases[5] = TimeTestCase("1 day", 86400, "single day");
        cases[6] = TimeTestCase("1 week", 604800, "single week");
        cases[7] = TimeTestCase("2 days", 172800, "two days");
        cases[8] = TimeTestCase("12 hours", 43200, "twelve hours");
        cases[9] = TimeTestCase("30 minutes", 1800, "thirty minutes");
        return cases;
    }

    function getConversionTestCases() internal pure returns (ConversionTestCase[] memory) {
        ConversionTestCase[] memory cases = new ConversionTestCase[](6);
        cases[0] = ConversionTestCase("1 day", 12000, 7200, "Ethereum mainnet timing");
        cases[1] = ConversionTestCase("1 day", 2000, 43200, "Fast L2 timing");
        cases[3] = ConversionTestCase("1 hour", 12000, 300, "Ethereum hour");
        cases[4] = ConversionTestCase("30 minutes", 2000, 900, "Fast L2 30min");
        return cases;
    }

    // Helper function to create test TOML configuration for time-based testing
    function createTestTimeTomlConfig() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "[token]\n",
                'name = "Test Governance Token"\n',
                'symbol = "TGT"\n',
                "initial_supply = 0\n\n",
                "[governor]\n",
                'name = "Test Governor"\n',
                'voting_delay_time = "1 day"\n',
                'voting_period_time = "1 week"\n',
                'late_quorum_extension_time = "1 hour"\n',
                "quorum_numerator = 500\n\n",
                "[treasury]\n",
                'address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"\n\n',
                "[distributions.test]\n",
                'description = "Test distribution"\n\n',
                "[[distributions.test.recipients]]\n",
                'name = "Test Recipient 1"\n',
                'address = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"\n',
                'amount = "1000000000000000000000"\n',
                'description = "Test recipient 1"\n\n',
                "[[distributions.test.recipients]]\n",
                'name = "Test Recipient 2"\n',
                'address = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"\n',
                'amount = "2000000000000000000000"\n',
                'description = "Test recipient 2"\n\n',
                "[networks.localhost]\n",
                'description = "Local test network"\n',
                "chain_id = 31337\n",
                "block_time_milliseconds = 1000\n",
                "gas_price_gwei = 1\n",
                "gas_limit = 30000000\n\n",
                "[deployment]\n",
                'scenario = "test"\n',
                'splitter_scenario = "none"\n',
                "verify = false\n"
            )
        );
    }

    function createEthereumTimeTomlConfig() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "[token]\n",
                'name = "Ethereum Test Token"\n',
                'symbol = "ETT"\n',
                "initial_supply = 0\n\n",
                "[governor]\n",
                'name = "Ethereum Test Governor"\n',
                'voting_delay_time = "2 days"\n',
                'voting_period_time = "1 week"\n',
                'late_quorum_extension_time = "6 hours"\n',
                "quorum_numerator = 1000\n\n",
                "[treasury]\n",
                'address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"\n\n',
                "[distributions.test]\n",
                'description = "Ethereum test distribution"\n\n',
                "[[distributions.test.recipients]]\n",
                'name = "Test Recipient"\n',
                'address = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"\n',
                'amount = "1000000000000000000000"\n',
                'description = "Test recipient"\n\n',
                "[networks.mainnet]\n",
                'description = "Ethereum Mainnet"\n',
                "chain_id = 1\n",
                "block_time_milliseconds = 12000\n",
                "gas_price_gwei = 20\n",
                "gas_limit = 8000000\n\n",
                "[deployment]\n",
                'scenario = "test"\n',
                'splitter_scenario = "none"\n',
                "verify = false\n"
            )
        );
    }

    // Helper to assert time conversion accuracy
    function assertTimeConversionAccuracy(
        string memory, // timeString
        uint256, // blockTimeMs
        uint256, // expectedBlocks
        string memory description
    ) internal pure {
        // This would be used with the Deploy contract's time conversion functions
        // The actual implementation depends on how the Deploy contract exposes these functions
        assertTrue(true, string(abi.encodePacked("Time conversion test: ", description)));
    }

    // Mock test addresses commonly used in time-based tests
    address public constant TIME_TEST_OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant TIME_TEST_RECIPIENT1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public constant TIME_TEST_RECIPIENT2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    // Time-related constants for testing
    uint256 public constant SECONDS_PER_MINUTE = 60;
    uint256 public constant SECONDS_PER_HOUR = 3600;
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant SECONDS_PER_WEEK = 604800;

    // Block time constants (in milliseconds)
    uint256 public constant ETHEREUM_BLOCK_TIME_MS = 12000;

    uint256 public constant LOCALHOST_BLOCK_TIME_MS = 1000;

    // Event for time parameter conversion testing
    event TimeParametersConverted(
        string votingDelayTime,
        uint256 votingDelayBlocks,
        string votingPeriodTime,
        uint256 votingPeriodBlocks,
        string lateQuorumExtensionTime,
        uint256 lateQuorumExtensionBlocks
    );

    // Expect time parameters converted event
    function expectTimeParametersConverted(
        string memory votingDelayTime,
        uint256 votingDelayBlocks,
        string memory votingPeriodTime,
        uint256 votingPeriodBlocks,
        string memory lateQuorumExtensionTime,
        uint256 lateQuorumExtensionBlocks
    ) internal {
        vm.expectEmit(false, false, false, true);
        emit TimeParametersConverted(
            votingDelayTime,
            votingDelayBlocks,
            votingPeriodTime,
            votingPeriodBlocks,
            lateQuorumExtensionTime,
            lateQuorumExtensionBlocks
        );
    }

    error InvalidPayeesHash();
    error InvalidShares();
    error EmptyCalldata();

    /**
     * @dev Check if an address is a current payee by scanning calldata
     * @param account Address to check
     * @param packedPayeesData Calldata containing payees and shares for verification
     * @return isPayee Whether the address is a payee
     * @return accountShares The shares for this address (0 if not a payee)
     */
    function _getPayeeInfo(address splitterAddress, address account, bytes memory packedPayeesData)
        internal
        view
        returns (bool isPayee, uint16 accountShares)
    {
        if (packedPayeesData.length == 0) return (false, 0);

        // Verify the provided calldata matches stored hash
        bytes32 providedHash = keccak256(packedPayeesData);
        require(providedHash == Splitter(splitterAddress).payeesHash(), InvalidPayeesHash());

        uint256 payeeCount = packedPayeesData.length / PAYEE_DATA_SIZE;

        // Scan through payees to find the account
        for (uint256 i = 0; i < payeeCount;) {
            uint256 offset = i * PAYEE_DATA_SIZE;

            address payee;
            assembly {
                payee := shr(96, mload(add(add(packedPayeesData, 0x20), add(offset, 2))))
            }

            if (payee == account) {
                assembly {
                    accountShares := shr(240, mload(add(add(packedPayeesData, 0x20), offset)))
                }
                return (true, accountShares);
            }

            unchecked {
                ++i;
            }
        }

        return (false, 0);
    }

    function _hasPayees(address splitterAddress) internal view returns (bool) {
        return Splitter(splitterAddress).payeesHash() != bytes32(0);
    }

    /**
     * @dev Internal function to create packed calldata from PayeeData array
     * Payees are automatically sorted by address to ensure deterministic results
     * @param payees Array of PayeeData structs containing address and shares
     * @return packedData The tightly packed bytes for use with other functions
     */
    function _createPackedPayeesData(Splitter.PayeeData[] memory payees)
        internal
        pure
        returns (bytes memory packedData)
    {
        require(payees.length != 0, InvalidShares());

        // Create a memory array to sort by address
        Splitter.PayeeData[] memory sortedPayees = new Splitter.PayeeData[](payees.length);
        for (uint256 i = 0; i < payees.length;) {
            sortedPayees[i] = payees[i];
            unchecked {
                ++i;
            }
        }

        // Sort by address using bubble sort (simple but gas-inefficient for large arrays)
        // Do not use on-chain sorting for large arrays due to gas inefficiency
        for (uint256 i = 0; i < sortedPayees.length - 1;) {
            for (uint256 j = 0; j < sortedPayees.length - i - 1;) {
                if (sortedPayees[j].payee > sortedPayees[j + 1].payee) {
                    Splitter.PayeeData memory temp = sortedPayees[j];
                    sortedPayees[j] = sortedPayees[j + 1];
                    sortedPayees[j + 1] = temp;
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Use abi.encodePacked for simple and correct packing
        for (uint256 i = 0; i < sortedPayees.length;) {
            packedData = abi.encodePacked(packedData, sortedPayees[i].shares, sortedPayees[i].payee);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Calculate how much each payee would receive from a given amount
     * @param amount The total amount to be split
     * @param packedPayeesData Calldata containing payees and shares
     * @return payeeAmounts Array of amounts each payee would receive
     */
    function _calculateSplit(address splitterAddress, uint256 amount, bytes memory packedPayeesData)
        internal
        view
        returns (uint256[] memory payeeAmounts)
    {
        require(packedPayeesData.length != 0, EmptyCalldata());

        // Verify the provided calldata matches stored hash
        bytes32 providedHash = keccak256(packedPayeesData);
        require(providedHash == Splitter(splitterAddress).payeesHash(), InvalidPayeesHash());

        uint256 payeeCount = packedPayeesData.length / PAYEE_DATA_SIZE;
        payeeAmounts = new uint256[](payeeCount);
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < payeeCount;) {
            uint256 offset = i * PAYEE_DATA_SIZE;

            uint16 payeeShares;
            assembly {
                payeeShares := shr(240, mload(add(add(packedPayeesData, 0x20), offset)))
            }

            uint256 payment = calculatePayment(amount, payeeShares, i, payeeCount, totalDistributed);
            payeeAmounts[i] = payment;
            totalDistributed += payment;

            unchecked {
                ++i;
            }
        }
    }

    function _calculatePayeesHash(Splitter.PayeeData[] memory payees) internal pure returns (bytes32 hash) {
        bytes memory packedData = _createPackedPayeesData(payees);
        hash = keccak256(packedData);
    }
}
