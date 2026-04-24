// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Carpool.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract CarpoolTest is Test {
    Carpool carpool;

    address owner = address(1);

    uint256 driverPk = 2;
    uint256 userPk = 3;
    uint256 treasuryPk = 4;
    uint256 user2Pk = 5;

    address driver;
    address user;
    address treasury;
    address user2;

    uint256 constant MIN = 1 ether;
    uint256 constant BOND = 20;

    function setUp() public {
        driver = vm.addr(driverPk);
        user = vm.addr(userPk);
        treasury = vm.addr(treasuryPk);
        user2 = vm.addr(user2Pk);

        vm.prank(owner);
        carpool = new Carpool(owner, treasury, MIN, BOND, 300, 100);

        vm.deal(driver, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(user2, 10 ether);

        // driver setup
        vm.prank(owner);
        carpool.registerDriver(driver, keccak256("id"), keccak256("doc"));

        vm.prank(driver);
        carpool.depositDriverCollateral{value: MIN}();

        // users
        vm.prank(user);
        carpool.registerUser();

        vm.prank(user2);
        carpool.registerUser();
    }

    // ---------------- SIGN HELPERS ----------------

    function signAccept(uint256 fare, bool ceiling, uint256 nonce) internal view returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode(address(carpool), user, driver, fare, ceiling, nonce, block.chainid));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(driverPk, MessageHashUtils.toEthSignedMessageHash(hash));

        return abi.encodePacked(r, s, v);
    }

    function signShareR1(uint256 id, uint256 refund, uint256 deadline, uint256 nonce) internal view returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode("R1", address(carpool), user2, id, refund, deadline, nonce, block.chainid));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, MessageHashUtils.toEthSignedMessageHash(hash));

        return abi.encodePacked(r, s, v);
    }

    function signShareDriver(uint256 id, uint256 incentive, uint256 deadline, uint256 nonce) internal view returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode("D", address(carpool), user2, id, incentive, deadline, nonce, block.chainid));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(driverPk, MessageHashUtils.toEthSignedMessageHash(hash));

        return abi.encodePacked(r, s, v);
    }

    // ---------------- TESTS ----------------

    function testFullFlow() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.completeRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Completed));
    }

    function testSharedRide() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        uint256 refund = 0.2 ether;
        uint256 incentive = 0.1 ether;

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, refund, deadline, 0);
        bytes memory dSig = signShareDriver(id, incentive, deadline, 0);

        vm.prank(user2);
        carpool.joinSharedRide{value: refund + incentive}(id, refund, incentive, deadline, r1Sig, dSig);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(r.sharedInfo.secondUser, user2);
    }

    function testCancelRide() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(user);
        carpool.cancelRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Cancelled));
    }

    function testDisputeFlow() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(user);
        carpool.disputeRide(id);

        vm.prank(owner);
        carpool.resolveDispute(id, 0.5 ether);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Completed));
    }

    function testRating() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.completeRide(id);

        vm.prank(user);
        carpool.rateDriver(id, 5);

        (,, uint256 rating, uint256 count,,,) = carpool.drivers(driver);

        assertEq(rating, 5);
        assertEq(count, 1);
    }

    // ---------------- NEGATIVE TESTS ----------------

    function testInvalidSignatureFails() public {
        vm.prank(user);
        vm.expectRevert();
        carpool.acceptRide{value: 1 ether}(driver, 1 ether, false, hex"1234");
    }

    function testReplayCompleteFails() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.completeRide(id);

        vm.prank(driver);
        vm.expectRevert();
        carpool.completeRide(id);
    }

    function testAcceptWrongValueFails() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        vm.expectRevert();
        carpool.acceptRide{value: fare - 1}(driver, fare, false, sig);
    }

    function testStartRideWrongCallerFails() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(user);
        vm.expectRevert();
        carpool.startRide(id, 1, 2, 3, 4, 3600);
    }

    function testStartRideTwiceFails() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        vm.expectRevert();
        carpool.startRide(id, 1, 2, 3, 4, 3600);
    }

    function testNonUserCannotRate() public {
        uint256 fare = 1 ether;

        bytes memory sig = signAccept(fare, false, 0);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.completeRide(id);

        vm.prank(user2);
        vm.expectRevert();
        carpool.rateDriver(id, 5);
    }
}
