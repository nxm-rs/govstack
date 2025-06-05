// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "@openzeppelin/contracts/governance/Governor.sol";

/// @title OtocoManager
/// @author Nexum Contributors
/// @notice Abstract contract implementing ABI for use with https://otoco.io.
abstract contract OtocoManager is Governor {
    address private _manager;

    /// @dev Emitted when the manager is set.
    event ManagerSet(address indexed oldManager, address indexed newManager);

    /// @notice Initializes the manager address.
    /// @param manager The initial manager address.
    constructor(address manager) {
        _setManager(manager);
    }

    /// @notice Retrieve the current manager address.
    /// @return The current manager address.
    function getManager() external view returns (address) {
        return _manager;
    }

    /// @notice Sets the manager address.
    /// @param newManager The new manager address.
    function setManager(address newManager) public virtual onlyGovernance {
        _setManager(newManager);
    }

    /// @notice Internal function to set the manager address.
    /// @param newManager The new manager address.
    function _setManager(address newManager) internal {
        address oldManager = _manager;
        _manager = newManager;
        emit ManagerSet(oldManager, newManager);
    }

    /// @dev Here we stub out the `isManagerProposal` function. Always returns false.
    /// @return Always returns false.
    function isManagerProposal(uint256) public pure virtual returns (bool) {
        return false;
    }
}
