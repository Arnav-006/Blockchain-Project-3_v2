// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Carpool.sol";

contract DeployCarpool is Script {
    function run() external {
        // Use default Anvil Account #0 private key if PRIVATE_KEY is not set
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Default local environment parameters
        address owner = deployerAddress;
        address backend = deployerAddress;
        uint256 minDeposit = 1 ether;
        uint256 bondPercent = 20;
        uint256 delayThreshold = 300;
        uint256 surcharge = 100;

        Carpool carpool = new Carpool(
            owner,
            backend,
            minDeposit,
            bondPercent,
            delayThreshold,
            surcharge
        );

        vm.stopBroadcast();

        console.log("Carpool deployed successfully to:", address(carpool));
    }
}
