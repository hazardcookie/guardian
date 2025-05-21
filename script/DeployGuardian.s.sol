// SPDX-License-Identifier: UNLICENSED
/// @custom:security-contact bugs@ripple.com
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "../src/RLUSDGuardian.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployGuardian is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address coldOwner = vm.envAddress("COLD_OWNER");
        address rlusd = vm.envAddress("RLUSD_TOKEN");
        address usdc = vm.envAddress("USDC_TOKEN");

        vm.startBroadcast(deployerKey);

        // Implementation + proxy
        RLUSDGuardian impl = new RLUSDGuardian();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");

        // Initialise: guardian owner becomes the cold wallet
        RLUSDGuardian(address(proxy)).initialize(rlusd, usdc, coldOwner);

        vm.stopBroadcast();

        console2.log("Guardian proxy:", address(proxy));
        console2.log("Impl:", address(impl));
        console2.log("Cold owner:", coldOwner);
    }
}
