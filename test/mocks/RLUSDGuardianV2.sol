// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {RLUSDGuardian} from "../../src/RLUSDGuardian.sol";

/// @title RLUSDGuardianV2
/// @notice Dummy new implementation for upgrade testing (UUPS V2 with an extra feature).
/// @dev This contract is used to test upgradeability of the RLUSDGuardian contract.
contract RLUSDGuardianV2 is RLUSDGuardian {
    // New storage variable (to test storage layout compatibility)
    uint256 public newValue;

    /// @notice Returns a constant value to verify upgrade worked.
    /// @dev New function in V2 implementation.
    /// @return Always returns 42.
    function getNewValue() external pure returns (uint256) {
        return 42;
    }

    /// @notice Set a new value (onlyOwner) to test state changes in upgraded contract.
    /// @param _val The new value to set.
    function setNewValue(uint256 _val) external onlyOwner {
        newValue = _val;
    }
}
