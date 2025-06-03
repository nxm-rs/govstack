// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract TokenGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorPreventLateQuorum
{
    constructor(
        string memory name,
        address token,
        uint256 initialVotingDelay,
        uint256 initialVotingPeriod,
        uint256 quorumNumerator,
        uint48 lateQuorumExtension
    )
        Governor(name)
        GovernorVotes(IVotes(token))
        GovernorVotesQuorumFraction(quorumNumerator)
        GovernorSettings(uint48(initialVotingDelay), uint32(initialVotingPeriod), 0)
        GovernorPreventLateQuorum(lateQuorumExtension)
    {}

    /**
     * @dev Override to resolve conflict between Governor and GovernorSettings
     */
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }

    /**
     * @dev Override to resolve conflict between Governor and GovernorPreventLateQuorum
     */
    function _tallyUpdated(uint256 proposalId) internal override(Governor, GovernorPreventLateQuorum) {
        GovernorPreventLateQuorum._tallyUpdated(proposalId);
    }

    /// @dev Override to resolve conflict between Governor and GovernorPreventLateQuorum
    function proposalDeadline(uint256 proposalId)
        public
        view
        override(Governor, GovernorPreventLateQuorum)
        returns (uint256)
    {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }
}
