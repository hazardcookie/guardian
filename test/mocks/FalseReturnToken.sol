// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

/// @title FalseReturnToken
/// @notice ERC20 mock that always returns false on transfer/transferFrom instead of reverting.
/// @dev Used to test handling of non-standard ERC20s that signal failure by returning false.
contract FalseReturnToken {
    string public name; // Token name
    string public symbol; // Token symbol
    uint8 public decimals; // Number of decimals
    mapping(address => uint256) public balanceOf; // Mapping of address to balance
    mapping(address => mapping(address => uint256)) public allowance; // Allowance mapping

    event Transfer(address indexed from, address indexed to, uint256 value); // Standard ERC20 event
    event Approval(address indexed owner, address indexed spender, uint256 value); // Standard ERC20 event

    /// @notice Constructs the FalseReturnToken mock.
    /// @param name_ The token name.
    /// @param symbol_ The token symbol.
    /// @param decimals_ The number of decimals.
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @notice Simulates a transfer that always fails by returning false.
    /// @param _to The recipient address (ignored).
    /// @param _amount The amount to transfer (ignored).
    /// @return Always returns false.
    function transfer(address _to, uint256 _amount) public pure returns (bool) {
        // Reference parameters to avoid unused-variable compiler warnings.
        (_to, _amount);
        return false;
    }

    /// @notice Simulates a transferFrom that always fails by returning false.
    /// @param _from The sender address (ignored).
    /// @param _to The recipient address (ignored).
    /// @param _amount The amount to transfer (ignored).
    /// @return Always returns false.
    function transferFrom(address _from, address _to, uint256 _amount) public pure returns (bool) {
        // Reference parameters to avoid unused-variable compiler warnings.
        (_from, _to, _amount);
        return false;
    }

    /// @notice Approves a spender for a given value.
    /// @param spender The address to approve.
    /// @param value The amount to approve.
    /// @return Always returns true.
    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Mint tokens to an address for testing purposes.
    /// @param to The address to mint to.
    /// @param amount The amount to mint.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
