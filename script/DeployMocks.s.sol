// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/MockToken.sol";

contract DeployMocks is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_KEY"); // same hot key as before
        vm.startBroadcast(pk);

        // 18-dec RLUSD mock
        MockToken rlusd = new MockToken("Ripple USD", "RLUSD", 18);

        // 6-dec USDC mock
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);

        vm.stopBroadcast();

        console2.log("RLUSD mock  (18dec):", address(rlusd));
        console2.log("USDC  mock  (6dec):", address(usdc));
    }
}
