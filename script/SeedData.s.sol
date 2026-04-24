// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Carpool.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SeedData is Script {
    function run() external {
        // Fetch the deployed contract address from env, or use the default Anvil first-deploy address
        address contractAddr = vm.envOr("CARPOOL_ADDR", address(0x5FbDB2315678afecb367f032d93F642f64180aa3));
        Carpool carpool = Carpool(contractAddr);

        // Load predefined Anvil Private Keys
        uint256 ownerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // Account 0
        uint256 driver1Pk = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // Account 1
        uint256 driver2Pk = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a; // Account 2
        uint256 rider1Pk = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6; // Account 3
        uint256 rider2Pk = 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a; // Account 4

        address driver1 = vm.addr(driver1Pk);
        address driver2 = vm.addr(driver2Pk);
        address rider1 = vm.addr(rider1Pk);
        address rider2 = vm.addr(rider2Pk);

        console.log("Seeding data into Carpool Contract at:", address(carpool));

        // ----------------------------------------------------
        // 1. ADMIN SETUP: Register Drivers
        // ----------------------------------------------------
        vm.startBroadcast(ownerPk);
        // Only register if not already registered (to allow re-running script)
        (address d1Addr,,,,,,) = carpool.drivers(driver1);
        if (d1Addr == address(0)) {
            carpool.registerDriver(driver1, keccak256("D1_ID"), keccak256("D1_DOC"));
            carpool.registerDriver(driver2, keccak256("D2_ID"), keccak256("D2_DOC"));
            console.log("-> Drivers Registered by Admin");
        }
        vm.stopBroadcast();

        // ----------------------------------------------------
        // 2. DRIVER SETUP: Deposit Collateral
        // ----------------------------------------------------
        vm.startBroadcast(driver1Pk);
        (, Carpool.DriverStatus d1Status,,,,,) = carpool.drivers(driver1);
        if (uint256(d1Status) == uint256(Carpool.DriverStatus.Verified)) {
            carpool.depositDriverCollateral{value: 1 ether}();
            console.log("-> Driver 1 Deposited Collateral & is Active");
        }
        vm.stopBroadcast();

        vm.startBroadcast(driver2Pk);
        (, Carpool.DriverStatus d2Status,,,,,) = carpool.drivers(driver2);
        if (uint256(d2Status) == uint256(Carpool.DriverStatus.Verified)) {
            carpool.depositDriverCollateral{value: 1 ether}();
            console.log("-> Driver 2 Deposited Collateral & is Active");
        }
        vm.stopBroadcast();

        // ----------------------------------------------------
        // 3. RIDER SETUP: Register Users
        // ----------------------------------------------------
        vm.startBroadcast(rider1Pk);
        (address r1Addr, , ) = carpool.users(rider1);
        if (r1Addr == address(0)) {
            carpool.registerUser();
            console.log("-> Rider 1 Registered");
        }
        vm.stopBroadcast();

        vm.startBroadcast(rider2Pk);
        (address r2Addr, , ) = carpool.users(rider2);
        if (r2Addr == address(0)) {
            carpool.registerUser();
            console.log("-> Rider 2 Registered");
        }
        vm.stopBroadcast();

        // ----------------------------------------------------
        // 4. RIDE LIFECYCLE: Create a Completed Ride
        // ----------------------------------------------------
        uint256 fare = 0.5 ether;
        
        // Step 4a: Driver 1 creates a cryptographic signature for Rider 1
        uint256 nonce = 0; // Assuming this is Rider 1's first ride
        bytes32 hash = keccak256(abi.encode(address(carpool), rider1, driver1, fare, false, nonce, block.chainid));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(driver1Pk, MessageHashUtils.toEthSignedMessageHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        // Step 4b: Rider 1 accepts the ride with the signature
        vm.startBroadcast(rider1Pk);
        uint256 rideId = carpool.acceptRide{value: fare}(driver1, fare, false, sig);
        console.log("-> Rider 1 Accepted Ride #", rideId);
        vm.stopBroadcast();

        // Step 4c: Driver 1 starts and completes the ride
        vm.startBroadcast(driver1Pk);
        carpool.startRide(rideId, 1, 2, 3, 4, 3600);
        console.log("-> Driver 1 Started Ride #", rideId);
        
        carpool.completeRide(rideId);
        console.log("-> Driver 1 Completed Ride #", rideId);
        vm.stopBroadcast();

        // Step 4d: Rider 1 rates Driver 1
        vm.startBroadcast(rider1Pk);
        carpool.rateDriver(rideId, 5);
        console.log("-> Rider 1 Rated Driver 1 with 5 stars");
        vm.stopBroadcast();

        console.log("\n====== SEEDING COMPLETE ======");
        console.log("Driver 1 Address: ", driver1);
        console.log("Rider 1 Address:  ", rider1);
        console.log("Try interacting with these on your frontend!");
    }
}
