// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "solady/utils/SafeTransferLib.sol";
import "solady/utils/ReentrancyGuard.sol";
import "solady/auth/Ownable.sol";

/// @dev Size of each payee data entry in bytes (2 bytes for shares + 20 bytes for address)
uint256 constant PAYEE_DATA_SIZE = 22;
/// @dev Total shares in basis points (10000 = 100%)
uint256 constant TOTAL_SHARES_BPS = 10000;

/// @notice Free function to calculate payment amount for a payee
/// @param totalAmount The total amount to be split
/// @param payeeShares The shares for this payee
/// @param currentIndex The current payee index
/// @param totalPayees The total number of payees
/// @param totalDistributed The amount already distributed
/// @return payment The payment amount for this payee
function calculatePayment(
    uint256 totalAmount,
    uint16 payeeShares,
    uint256 currentIndex,
    uint256 totalPayees,
    uint256 totalDistributed
) pure returns (uint256 payment) {
    /// For last payee, give remaining amount to avoid rounding dust
    if (currentIndex == totalPayees - 1) {
        payment = totalAmount - totalDistributed;
    } else {
        payment = (totalAmount * payeeShares) / TOTAL_SHARES_BPS;
    }
}

/// @title TokenSplitter
/// @author Nexum Contributors
/// @notice Gas-optimized contract for splitting ERC20 tokens using calldata verification.
/// @dev Payees and shares are stored as a hash only, with all data provided via calldata.
/// The owner grants token approvals to this contract, and anyone can call splitToken
/// to distribute tokens from the owner to the configured payees.
/// Maximizes calldata usage and minimizes storage for optimal gas efficiency.
contract TokenSplitter is ReentrancyGuard, Ownable {
    using SafeTransferLib for address;

    /// @notice Struct for payee data
    struct PayeeData {
        address payee;
        uint16 shares;
    }

    error InvalidShares();
    error ZeroAmount();
    error InvalidTotalShares();
    error InvalidPayeesHash();
    error EmptyCalldata();
    error InvalidCalldataLength();

    event TokensReleased(address indexed token, address indexed to, uint256 amount);
    event TokensSplit(address indexed token, uint256 totalAmount);
    event PayeeAdded(address indexed payee, uint256 shares);
    event PayeesUpdated(bytes32 indexed newPayeesHash);

    /// @dev Hash of current payees and their shares (keccak of packed calldata)
    bytes32 public payeesHash;

    /// @notice Constructor sets the owner who can update payees
    /// @param _owner The address that will own this contract (typically the governor)
    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    /// @notice Update payees from tightly packed calldata (owner only)
    /// @param packedPayeesData Calldata containing alternating uint16 (shares) and address (payee)
    function updatePayees(bytes calldata packedPayeesData) external onlyOwner {
        require(packedPayeesData.length != 0, EmptyCalldata());
        require(packedPayeesData.length % PAYEE_DATA_SIZE == 0, InvalidCalldataLength());

        uint256 payeeCount = packedPayeesData.length / PAYEE_DATA_SIZE;
        require(payeeCount != 0, InvalidShares());

        // Calculate hash consistently with other functions
        bytes32 newHash = keccak256(packedPayeesData);
        uint256 totalShares = 0;

        // Validate payees and emit events
        for (uint256 i = 0; i < payeeCount;) {
            uint256 offset = i * PAYEE_DATA_SIZE;

            (uint16 payeeShares, address payee) = _extractPayeeData(packedPayeesData, offset);

            require(payee != address(0), InvalidShares());
            require(payeeShares != 0, InvalidShares());

            totalShares += payeeShares;
            emit PayeeAdded(payee, payeeShares);

            unchecked {
                ++i;
            }
        }

        require(totalShares == TOTAL_SHARES_BPS, InvalidTotalShares());

        payeesHash = newHash;
        emit PayeesUpdated(newHash);
    }

    /// @notice Split tokens among payees using provided calldata for verification.
    /// @dev Transfers tokens from the contract owner to the payees. Anyone can call this function.
    /// The owner must have previously approved this contract to spend the tokens.
    /// @param token The ERC20 token address to split
    /// @param amount The amount of tokens to split
    /// @param packedPayeesData Calldata containing payees and shares for verification
    function splitToken(address token, uint256 amount, bytes calldata packedPayeesData) external nonReentrant {
        require(amount != 0, ZeroAmount());
        require(packedPayeesData.length != 0, EmptyCalldata());

        // Verify the provided calldata matches stored hash
        bytes32 providedHash = keccak256(packedPayeesData);
        require(providedHash == payeesHash, InvalidPayeesHash());

        // Cache owner address to avoid multiple storage reads
        address tokenOwner = owner();
        uint256 totalDistributed = 0;
        uint256 payeeCount = packedPayeesData.length / PAYEE_DATA_SIZE;

        // Iterate through packed data and distribute tokens
        for (uint256 i = 0; i < payeeCount;) {
            uint256 offset = i * PAYEE_DATA_SIZE;

            (uint16 payeeShares, address payee) = _extractPayeeData(packedPayeesData, offset);

            uint256 payment = calculatePayment(amount, payeeShares, i, payeeCount, totalDistributed);

            if (payment > 0) {
                totalDistributed += payment;
                token.safeTransferFrom(tokenOwner, payee, payment);
                emit TokensReleased(token, payee, payment);
            }

            unchecked {
                ++i;
            }
        }

        emit TokensSplit(token, totalDistributed);
    }

    /// @notice Internal function to extract payee data from packed calldata
    /// @param packedPayeesData The packed calldata
    /// @param offset The offset to read from
    /// @return payeeShares The shares for this payee
    /// @return payee The payee address
    function _extractPayeeData(bytes calldata packedPayeesData, uint256 offset)
        internal
        pure
        returns (uint16 payeeShares, address payee)
    {
        assembly {
            // Load shares (first 2 bytes, big endian)
            payeeShares := shr(240, calldataload(add(packedPayeesData.offset, offset)))
            // Load address (next 20 bytes)
            payee := shr(96, calldataload(add(packedPayeesData.offset, add(offset, 2))))
        }
    }
}
