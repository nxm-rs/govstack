// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "./Token.sol";
import "./Governor.sol";
import "./TokenSplitter.sol";

/**
 * @title AbstractDeployer
 * @dev Abstract base contract for deploying Token, Governor, and TokenSplitter contracts
 * with initial configuration using CREATE2. Uses chain ID and block hash as salt to ensure
 * unique addresses across different chains. This contract enables atomic deployment and
 * initial configuration in a single transaction.
 *
 * The deployer automatically self-destructs after successful deployment, leaving only the
 * deployed contracts.
 */
abstract contract AbstractDeployer {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error FinalOwnerZeroAddress();
    error TokenNameEmpty();
    error TokenSymbolEmpty();
    error GovernorNameEmpty();
    error TooManyDistributions();
    error RecipientZeroAddress();
    error AmountMustBeGreaterThanZero();
    error DuplicateRecipient();
    error PayeesSharesLengthMismatch();

    struct TokenConfig {
        string name;
        string symbol;
        uint256 initialSupply;
    }

    struct GovernorConfig {
        string name;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 quorumNumerator;
        uint48 lateQuorumExtension;
    }

    struct SplitterConfig {
        bytes packedPayeesData;
    }

    struct TokenDistribution {
        address recipient;
        uint256 amount;
    }

    struct DeploymentAddresses {
        address token;
        address governor;
        address splitter;
    }

    event TokenDeployed(address indexed tokenAddress, string name, string symbol);
    event GovernorDeployed(address indexed governorAddress, string name, address indexed token);
    event SplitterDeployed(address indexed splitterAddress, address indexed governor);
    event TokensDistributed(address indexed tokenAddress, address indexed recipient, uint256 amount);
    event DeploymentCompleted(
        address indexed token,
        address indexed governor,
        address indexed splitter,
        address finalOwner,
        uint256 totalDistributed,
        bytes32 salt
    );
    event DeployerSelfDestructed(DeploymentAddresses addresses);
    event SaltGenerated(bytes32 indexed salt, uint256 chainId, bytes32 blockHash, address deployer);

    /**
     * @dev Deploys Token, Governor, and TokenSplitter contracts with initial configuration.
     * All operations are atomic within the constructor. Uses CREATE2 with chain ID and block hash
     * as salt to ensure unique addresses across different chains.
     *
     * @param tokenConfig Configuration for the token
     * @param governorConfig Configuration for the governor
     * @param splitterConfig Configuration for the splitter
     * @param distributions Array of initial token distributions
     * @param finalOwner The final owner of the token contract (receives ownership after distribution)
     */
    constructor(
        TokenConfig memory tokenConfig,
        GovernorConfig memory governorConfig,
        SplitterConfig memory splitterConfig,
        TokenDistribution[] memory distributions,
        address finalOwner
    ) {
        require(finalOwner != address(0), FinalOwnerZeroAddress());
        require(bytes(tokenConfig.name).length > 0, TokenNameEmpty());
        require(bytes(tokenConfig.symbol).length > 0, TokenSymbolEmpty());
        require(bytes(governorConfig.name).length > 0, GovernorNameEmpty());

        // Validate distributions
        if (distributions.length > 0) {
            _validateDistributions(distributions);
        }



        // Generate unique salt
        bytes32 salt = _generateSalt();
        emit SaltGenerated(salt, block.chainid, blockhash(block.number - 1), address(this));

        DeploymentAddresses memory addresses;

        // Deploy Token contract
        addresses.token = address(
            new Token{salt: salt}(tokenConfig.name, tokenConfig.symbol, tokenConfig.initialSupply, address(this))
        );
        emit TokenDeployed(addresses.token, tokenConfig.name, tokenConfig.symbol);

        // Deploy Governor contract
        addresses.governor = address(
            new TokenGovernor{salt: salt}(
                governorConfig.name,
                addresses.token,
                governorConfig.votingDelay,
                governorConfig.votingPeriod,
                governorConfig.quorumNumerator,
                governorConfig.lateQuorumExtension
            )
        );
        emit GovernorDeployed(addresses.governor, governorConfig.name, addresses.token);

        // Deploy TokenSplitter contract if payees data is provided
        if (splitterConfig.packedPayeesData.length > 0) {
            addresses.splitter = address(new TokenSplitter{salt: salt}(address(this)));
            emit SplitterDeployed(addresses.splitter, addresses.governor);

            // Configure the splitter with pre-generated packed calldata
            TokenSplitter splitter = TokenSplitter(addresses.splitter);
            splitter.updatePayees(splitterConfig.packedPayeesData);

            // Transfer ownership to the governor
            splitter.transferOwnership(addresses.governor);
        }

        Token token = Token(addresses.token);
        uint256 totalDistributed = 0;

        // Distribute tokens to specified addresses
        for (uint256 i = 0; i < distributions.length; i++) {
            TokenDistribution memory dist = distributions[i];
            token.mint(dist.recipient, dist.amount);
            totalDistributed += dist.amount;
            emit TokensDistributed(addresses.token, dist.recipient, dist.amount);
        }

        // Transfer token ownership to the final owner
        token.transferOwnership(finalOwner);

        emit DeploymentCompleted(
            addresses.token, addresses.governor, addresses.splitter, finalOwner, totalDistributed, salt
        );

        // Emit self-destruct event
        emit DeployerSelfDestructed(addresses);

        // Self-destruct the deployer contract after successful deployment
        selfdestruct(payable(finalOwner));
    }

    /**
     * @dev Internal function to generate a unique salt for CREATE2 deployment
     */
    function _generateSalt() internal view returns (bytes32 salt) {
        salt = keccak256(
            abi.encodePacked(block.chainid, blockhash(block.number - 1), address(this), block.timestamp, tx.origin)
        );
    }

    /**
     * @dev Internal function to validate distributions
     */
    function _validateDistributions(TokenDistribution[] memory distributions) internal pure {
        require(distributions.length <= 100, TooManyDistributions());

        for (uint256 i = 0; i < distributions.length; i++) {
            require(distributions[i].recipient != address(0), RecipientZeroAddress());
            require(distributions[i].amount > 0, AmountMustBeGreaterThanZero());

            // Check for duplicate recipients
            for (uint256 j = i + 1; j < distributions.length; j++) {
                require(distributions[i].recipient != distributions[j].recipient, DuplicateRecipient());
            }
        }
    }


}

/**
 * @title Deployer
 * @dev Production implementation with minimal bytecode - utility functions are internal
 */
contract Deployer is AbstractDeployer {
    constructor(
        TokenConfig memory tokenConfig,
        GovernorConfig memory governorConfig,
        SplitterConfig memory splitterConfig,
        TokenDistribution[] memory distributions,
        address finalOwner
    ) AbstractDeployer(tokenConfig, governorConfig, splitterConfig, distributions, finalOwner) {}
}

/**
 * @title TestableDeployer
 * @dev Test implementation with full utility functions exposed as public/external
 */
contract TestableDeployer is AbstractDeployer {
    constructor(
        TokenConfig memory tokenConfig,
        GovernorConfig memory governorConfig,
        SplitterConfig memory splitterConfig,
        TokenDistribution[] memory distributions,
        address finalOwner
    ) AbstractDeployer(tokenConfig, governorConfig, splitterConfig, distributions, finalOwner) {}

    function predictDeploymentAddresses(
        address deployer,
        TokenConfig memory tokenConfig,
        GovernorConfig memory governorConfig,
        SplitterConfig memory splitterConfig,
        bytes32 salt
    ) external pure returns (DeploymentAddresses memory addresses) {
        // Predict Token address
        bytes32 tokenBytecodeHash = keccak256(
            abi.encodePacked(
                type(Token).creationCode,
                abi.encode(tokenConfig.name, tokenConfig.symbol, tokenConfig.initialSupply, deployer)
            )
        );
        addresses.token =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, tokenBytecodeHash)))));

        // Predict Governor address
        bytes32 governorBytecodeHash = keccak256(
            abi.encodePacked(
                type(TokenGovernor).creationCode,
                abi.encode(
                    governorConfig.name,
                    addresses.token,
                    governorConfig.votingDelay,
                    governorConfig.votingPeriod,
                    governorConfig.quorumNumerator
                )
            )
        );
        addresses.governor =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, governorBytecodeHash)))));

        // Predict Splitter address if payees data is provided
        if (splitterConfig.packedPayeesData.length > 0) {
            bytes32 splitterBytecodeHash =
                keccak256(abi.encodePacked(type(TokenSplitter).creationCode, abi.encode(deployer)));
            addresses.splitter = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, splitterBytecodeHash))))
            );
        }
    }

    function generatePredictableSalt(address deployerAddress) external view returns (bytes32 salt) {
        salt = keccak256(
            abi.encodePacked(block.chainid, blockhash(block.number - 1), deployerAddress, block.timestamp, tx.origin)
        );
    }

    function validateDistributions(TokenDistribution[] memory distributions) external pure returns (bool valid) {
        require(distributions.length <= 100, TooManyDistributions());

        for (uint256 i = 0; i < distributions.length; i++) {
            require(distributions[i].recipient != address(0), RecipientZeroAddress());
            require(distributions[i].amount > 0, AmountMustBeGreaterThanZero());

            // Check for duplicate recipients
            for (uint256 j = i + 1; j < distributions.length; j++) {
                require(distributions[i].recipient != distributions[j].recipient, DuplicateRecipient());
            }
        }

        return true;
    }

    function validateSplitterConfig(SplitterConfig memory /* splitterConfig */) external pure returns (bool valid) {
        // Validation is now handled by TokenSplitter.updatePayees() to avoid redundant gas costs
        // Empty config is valid (no splitter will be deployed)
        return true;
    }

    function calculateTotalDistribution(TokenDistribution[] memory distributions)
        external
        pure
        returns (uint256 total)
    {
        for (uint256 i = 0; i < distributions.length; i++) {
            total += distributions[i].amount;
        }
    }
}
