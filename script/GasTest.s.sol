// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "../src/Deployer.sol";

/**
 * @title GasTest
 * @dev Simplified deployment script for gas testing that bypasses TOML parsing
 */
contract GasTest is Script {
    // Test constants
    string public constant TOKEN_NAME = "Gas Test Token";
    string public constant TOKEN_SYMBOL = "GASTEST";
    string public constant GOVERNOR_NAME = "Gas Test Governor";

    // Governor parameters
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 5760;
    uint256 public constant QUORUM_NUMERATOR = 4;
    uint48 public constant LATE_QUORUM_EXTENSION = 10;

    // Distribution amounts (in wei)
    uint256 public constant RECIPIENT_1_AMOUNT = 1000e18; // 1000 tokens
    uint256 public constant RECIPIENT_2_AMOUNT = 2000e18; // 2000 tokens
    uint256 public constant RECIPIENT_3_AMOUNT = 3000e18; // 3000 tokens

    // Anvil test addresses
    address public constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant RECIPIENT_1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public constant RECIPIENT_2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address public constant RECIPIENT_3 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    event GasTestDeploymentStarted(string scenario);
    event GasTestDeploymentCompleted(
        address indexed token, address indexed governor, address indexed splitter, uint256 totalDistributed
    );

    function run() external {
        runBasicScenario();
    }

    /**
     * @dev Run basic gas test scenario with 3 recipients, no splitter
     */
    function runBasicScenario() public {
        console.log("=== Gas Test: Basic Scenario ===");
        emit GasTestDeploymentStarted("basic");

        // Create token configuration
        AbstractDeployer.TokenConfig memory tokenConfig =
            AbstractDeployer.TokenConfig({name: TOKEN_NAME, symbol: TOKEN_SYMBOL});

        // Create governor configuration
        AbstractDeployer.GovernorConfig memory governorConfig = AbstractDeployer.GovernorConfig({
            name: GOVERNOR_NAME,
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumNumerator: QUORUM_NUMERATOR,
            lateQuorumExtension: LATE_QUORUM_EXTENSION
        });

        // Create token distributions
        AbstractDeployer.TokenDistribution[] memory distributions = new AbstractDeployer.TokenDistribution[](3);
        distributions[0] = AbstractDeployer.TokenDistribution({recipient: RECIPIENT_1, amount: RECIPIENT_1_AMOUNT});
        distributions[1] = AbstractDeployer.TokenDistribution({recipient: RECIPIENT_2, amount: RECIPIENT_2_AMOUNT});
        distributions[2] = AbstractDeployer.TokenDistribution({recipient: RECIPIENT_3, amount: RECIPIENT_3_AMOUNT});

        // Empty splitter config (no splitter)
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;

        // Record logs to capture deployment details
        vm.recordLogs();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy contracts
        new Deployer(tokenConfig, governorConfig, emptySplitterConfig, distributions, OWNER);

        vm.stopBroadcast();

        // Extract deployment addresses from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress, address governorAddress, address splitterAddress, uint256 totalDistributed) =
            _extractDeploymentAddresses(logs);

        // Log deployment details
        console.log("=== Deployment Results ===");
        console.log("Token Address:", tokenAddress);
        console.log("Governor Address:", governorAddress);
        console.log("Splitter Address:", splitterAddress);
        console.log("Total Distributed:", totalDistributed);
        console.log("==========================");

        // Verify deployment
        _verifyBasicDeployment(tokenAddress, governorAddress, totalDistributed);

        emit GasTestDeploymentCompleted(tokenAddress, governorAddress, splitterAddress, totalDistributed);

        console.log("=== Gas Test Completed Successfully ===");
    }

    /**
     * @dev Run gas test scenario with splitter
     */
    function runWithSplitter() public {
        console.log("=== Gas Test: Splitter Scenario ===");
        emit GasTestDeploymentStarted("splitter");

        // Create token configuration
        AbstractDeployer.TokenConfig memory tokenConfig =
            AbstractDeployer.TokenConfig({name: TOKEN_NAME, symbol: TOKEN_SYMBOL});

        // Create governor configuration
        AbstractDeployer.GovernorConfig memory governorConfig = AbstractDeployer.GovernorConfig({
            name: GOVERNOR_NAME,
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumNumerator: QUORUM_NUMERATOR,
            lateQuorumExtension: LATE_QUORUM_EXTENSION
        });

        // Create token distributions
        AbstractDeployer.TokenDistribution[] memory distributions = new AbstractDeployer.TokenDistribution[](2);
        distributions[0] = AbstractDeployer.TokenDistribution({recipient: RECIPIENT_1, amount: RECIPIENT_1_AMOUNT});
        distributions[1] = AbstractDeployer.TokenDistribution({recipient: RECIPIENT_2, amount: RECIPIENT_2_AMOUNT});

        // Create splitter configuration (60/40 split)
        // Create packed payees data
        bytes memory packedData = abi.encodePacked(
            uint16(6000),
            RECIPIENT_2, // 60%
            uint16(4000),
            RECIPIENT_3 // 40%
        );

        AbstractDeployer.SplitterConfig memory splitterConfig =
            AbstractDeployer.SplitterConfig({packedPayeesData: packedData});

        // Record logs to capture deployment details
        vm.recordLogs();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy contracts
        new Deployer(tokenConfig, governorConfig, splitterConfig, distributions, OWNER);

        vm.stopBroadcast();

        // Extract deployment addresses from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (address tokenAddress, address governorAddress, address splitterAddress, uint256 totalDistributed) =
            _extractDeploymentAddresses(logs);

        // Log deployment details
        console.log("=== Deployment Results ===");
        console.log("Token Address:", tokenAddress);
        console.log("Governor Address:", governorAddress);
        console.log("Splitter Address:", splitterAddress);
        console.log("Total Distributed:", totalDistributed);
        console.log("==========================");

        // Verify deployment with splitter
        _verifySplitterDeployment(tokenAddress, governorAddress, splitterAddress, totalDistributed);

        emit GasTestDeploymentCompleted(tokenAddress, governorAddress, splitterAddress, totalDistributed);

        console.log("=== Gas Test with Splitter Completed Successfully ===");
    }

    /**
     * @dev Extract deployment addresses from recorded logs
     */
    function _extractDeploymentAddresses(Vm.Log[] memory logs)
        internal
        pure
        returns (address token, address governor, address splitter, uint256 totalDistributed)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DeploymentCompleted(address,address,address,address,uint256,bytes32)"))
            {
                token = address(uint160(uint256(logs[i].topics[1])));
                governor = address(uint160(uint256(logs[i].topics[2])));
                splitter = address(uint160(uint256(logs[i].topics[3])));
                (, uint256 distributed,) = abi.decode(logs[i].data, (address, uint256, bytes32));
                totalDistributed = distributed;
                break;
            }
        }
    }

    /**
     * @dev Verify basic deployment without splitter
     */
    function _verifyBasicDeployment(address tokenAddress, address governorAddress, uint256 totalDistributed)
        internal
        view
    {
        require(tokenAddress != address(0), "Token address is zero");
        require(governorAddress != address(0), "Governor address is zero");

        Token token = Token(tokenAddress);
        TokenGovernor governor = TokenGovernor(payable(governorAddress));

        // Verify token properties
        require(keccak256(bytes(token.name())) == keccak256(bytes(TOKEN_NAME)), "Token name mismatch");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes(TOKEN_SYMBOL)), "Token symbol mismatch");
        require(token.owner() == OWNER, "Token owner mismatch");

        // Verify governor properties
        require(keccak256(bytes(governor.name())) == keccak256(bytes(GOVERNOR_NAME)), "Governor name mismatch");
        require(governor.votingDelay() == VOTING_DELAY, "Voting delay mismatch");
        require(governor.votingPeriod() == VOTING_PERIOD, "Voting period mismatch");

        // Verify distributions
        require(token.balanceOf(RECIPIENT_1) == RECIPIENT_1_AMOUNT, "Recipient 1 balance mismatch");
        require(token.balanceOf(RECIPIENT_2) == RECIPIENT_2_AMOUNT, "Recipient 2 balance mismatch");
        require(token.balanceOf(RECIPIENT_3) == RECIPIENT_3_AMOUNT, "Recipient 3 balance mismatch");
        require(
            totalDistributed == RECIPIENT_1_AMOUNT + RECIPIENT_2_AMOUNT + RECIPIENT_3_AMOUNT,
            "Total distributed mismatch"
        );

        console.log("+ Basic deployment verification passed");
    }

    /**
     * @dev Verify deployment with splitter
     */
    function _verifySplitterDeployment(
        address tokenAddress,
        address governorAddress,
        address splitterAddress,
        uint256 totalDistributed
    ) internal view {
        require(tokenAddress != address(0), "Token address is zero");
        require(governorAddress != address(0), "Governor address is zero");
        require(splitterAddress != address(0), "Splitter address is zero");

        Token token = Token(tokenAddress);
        TokenGovernor governor = TokenGovernor(payable(governorAddress));
        TokenSplitter splitter = TokenSplitter(splitterAddress);

        // Verify token properties
        require(keccak256(bytes(token.name())) == keccak256(bytes(TOKEN_NAME)), "Token name mismatch");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes(TOKEN_SYMBOL)), "Token symbol mismatch");
        require(token.owner() == OWNER, "Token owner mismatch");

        // Verify governor properties
        require(keccak256(bytes(governor.name())) == keccak256(bytes(GOVERNOR_NAME)), "Governor name mismatch");

        // Verify splitter properties
        require(splitter.payeesHash() != bytes32(0), "Splitter payees should be set");

        // Verify distributions
        require(token.balanceOf(RECIPIENT_1) == RECIPIENT_1_AMOUNT, "Recipient 1 balance mismatch");
        require(token.balanceOf(RECIPIENT_2) == RECIPIENT_2_AMOUNT, "Recipient 2 balance mismatch");
        require(totalDistributed == RECIPIENT_1_AMOUNT + RECIPIENT_2_AMOUNT, "Total distributed mismatch");

        console.log("+ Splitter deployment verification passed");
    }

    /**
     * @dev Run large-scale gas test with many recipients
     */
    function runLargeScaleTest() public {
        console.log("=== Gas Test: Large Scale Scenario ===");
        emit GasTestDeploymentStarted("large_scale");

        // Create token configuration
        AbstractDeployer.TokenConfig memory tokenConfig =
            AbstractDeployer.TokenConfig({name: "Large Scale Gas Test", symbol: "LSGT"});

        // Create governor configuration
        AbstractDeployer.GovernorConfig memory governorConfig = AbstractDeployer.GovernorConfig({
            name: "Large Scale Governor",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumNumerator: QUORUM_NUMERATOR,
            lateQuorumExtension: LATE_QUORUM_EXTENSION
        });

        // Create many token distributions (10 recipients)
        AbstractDeployer.TokenDistribution[] memory distributions = new AbstractDeployer.TokenDistribution[](10);
        for (uint256 i = 0; i < 10; i++) {
            distributions[i] = AbstractDeployer.TokenDistribution({
                recipient: address(uint160(0x1000 + i)),
                amount: 1000e18 // 1000 tokens each
            });
        }

        // Empty splitter config
        AbstractDeployer.SplitterConfig memory emptySplitterConfig;

        // Record logs and measure gas
        vm.recordLogs();

        vm.startBroadcast();

        new Deployer(tokenConfig, governorConfig, emptySplitterConfig, distributions, OWNER);

        vm.stopBroadcast();

        console.log("=== Large Scale Gas Report ===");
        console.log("Recipients:", distributions.length);
        console.log("==============================");

        emit GasTestDeploymentCompleted(
            address(0), // We don't extract addresses for this test
            address(0),
            address(0),
            10000e18 // Total tokens distributed
        );

        console.log("=== Large Scale Gas Test Completed ===");
    }
}
