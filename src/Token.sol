// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8;

import "solady/auth/Ownable.sol";
import "solady/tokens/ERC20.sol";
import "solady/tokens/ERC20Votes.sol";

contract Token is ERC20Votes, Ownable {
    string private _name;
    string private _symbol;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address owner_
    ) ERC20Votes() {
        _name = name_;
        _symbol = symbol_;
        _initializeOwner(owner_);
        if (initialSupply > 0) {
            _mint(owner_, initialSupply);
        }
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Mint tokens to a specified address. Only the owner can call this function.
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external virtual onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from a specified address. Only the owner can call this function.
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @dev Burn tokens from the caller's balance. Only the owner can call this function.
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Required as ERC20Votes from solady differs to IVotes from OpenZeppelin
     */
    function getPastTotalSupply(
        uint256 timepoint
    ) public view returns (uint256) {
        return getPastVotesTotalSupply(timepoint);
    }
}
