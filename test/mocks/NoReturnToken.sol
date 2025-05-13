// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// @title NoReturnToken
/// @notice ERC20 mock that does not return a boolean on transfer/transferFrom (like USDT).
/// @dev Used to test handling of non-standard ERC20s that do not return a value on transfer/transferFrom.
contract NoReturnToken {
    string public name; // Token name
    string public symbol; // Token symbol
    uint8 public decimals; // Number of decimals
    mapping(address => uint256) public balanceOf; // Mapping of address to balance
    mapping(address => mapping(address => uint256)) public allowance; // Allowance mapping

    event Transfer(address indexed from, address indexed to, uint256 value); // Standard ERC20 event
    event Approval(address indexed owner, address indexed spender, uint256 value); // Standard ERC20 event

    /// @notice Constructs the NoReturnToken mock.
    /// @param name_ The token name.
    /// @param symbol_ The token symbol.
    /// @param decimals_ The number of decimals.
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @notice Simulates a transfer that does not return a value (non-standard ERC20).
    /// @param to The recipient address.
    /// @param value The amount to transfer.
    function transfer(address to, uint256 value) public {
        require(balanceOf[msg.sender] >= value, "NoReturnToken: insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        // No return value (non-standard ERC20)
    }

    /// @notice Simulates a transferFrom that does not return a value (non-standard ERC20).
    /// @param from The sender address.
    /// @param to The recipient address.
    /// @param value The amount to transfer.
    function transferFrom(address from, address to, uint256 value) public {
        require(balanceOf[from] >= value, "NoReturnToken: insufficient balance");
        require(allowance[from][msg.sender] >= value, "NoReturnToken: insufficient allowance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        allowance[from][msg.sender] -= value;
        // No return value
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
