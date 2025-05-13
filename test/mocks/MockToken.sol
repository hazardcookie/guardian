// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockToken
/// @notice Custom mock token with fixed decimals for testing.
/// @dev This is used to create RLUSD and USDC tokens with specific decimals for the tests.
contract MockToken is ERC20 {
    uint8 private _decimals; // Store decimals for this token

    /// @notice Constructs the mock token with a custom decimals value.
    /// @param name The token name.
    /// @param symbol The token symbol.
    /// @param decimals_ The number of decimals for this token.
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /// @notice Returns the number of decimals for this token.
    /// @return The decimals value set at construction.
    function decimals() public view virtual override returns (uint8) {
        // Return the custom decimals value
        return _decimals;
    }

    /// @notice Mint tokens to the specified address.
    /// @param to The address to mint to.
    /// @param amount The amount to mint.
    function mint(address to, uint256 amount) external {
        // Mint tokens to the specified address
        _mint(to, amount);
    }
}
