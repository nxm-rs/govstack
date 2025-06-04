// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import {Governor as OZGovernor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorPreventLateQuorum} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title TokenGovernor
/// @author Nexum Contributors
contract Governor is
    OZGovernor,
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
        uint256 quorumPercentage,
        uint48 lateQuorumExtension,
        uint256 initialProposalThreshold
    )
        OZGovernor(name)
        GovernorVotes(IVotes(token))
        GovernorVotesQuorumFraction(quorumPercentage)
        GovernorSettings(uint48(initialVotingDelay), uint32(initialVotingPeriod), initialProposalThreshold)
        GovernorPreventLateQuorum(lateQuorumExtension)
    {}

    /// @dev Override to resolve conflict between Governor and GovernorSettings
    function proposalThreshold() public view override(OZGovernor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }

    /// @dev Override to resolve conflict between Governor and GovernorPreventLateQuorum
    function _tallyUpdated(uint256 proposalId) internal override(OZGovernor, GovernorPreventLateQuorum) {
        GovernorPreventLateQuorum._tallyUpdated(proposalId);
    }

    /// @dev Override to resolve conflict between Governor and GovernorPreventLateQuorum
    function proposalDeadline(uint256 proposalId)
        public
        view
        override(OZGovernor, GovernorPreventLateQuorum)
        returns (uint256)
    {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }
}
