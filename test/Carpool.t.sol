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

        (,,,, uint256 rating, uint256 count,) = carpool.drivers(driver);

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

    // ---------------- ADMIN & WITHDRAWAL TESTS ----------------

    function testSetBackend() public {
        vm.prank(owner);
        carpool.setBackend(address(999));
        assertEq(carpool.backend(), address(999));
    }

    function testWithdrawCollateral() public {
        vm.prank(driver);
        carpool.withdrawCollateral(0.5 ether);
        (,,,,,, uint256 amtDeposited) = carpool.drivers(driver);
        assertEq(amtDeposited, 0.5 ether);
    }

    function testWithdraw() public {
        vm.prank(driver);
        carpool.withdrawCollateral(1 ether);

        uint256 balanceBefore = driver.balance;
        
        vm.prank(driver);
        carpool.withdraw();

        assertEq(driver.balance, balanceBefore + 1 ether);
    }

    function testReactivateDriverFailsIfNotSuspended() public {
        vm.prank(driver);
        // Should revert because driver is Active, not Suspended
        vm.expectRevert();
        carpool.reactivateDriver();
    }
    // ---------------- EXTRA NEGATIVE TESTS FOR BRANCH COVERAGE ----------------

    function testSetBackendZeroFails() public {
        vm.prank(owner);
        vm.expectRevert();
        carpool.setBackend(address(0));
    }
    
    function testRegisterDriverZeroFails() public {
        vm.prank(owner);
        vm.expectRevert();
        carpool.registerDriver(address(0), keccak256("id2"), keccak256("doc"));
    }

    function testRegisterDriverDuplicateIDFails() public {
        vm.prank(owner);
        vm.expectRevert();
        carpool.registerDriver(driver, keccak256("id"), keccak256("doc"));
    }

    function testDepositUnregisteredFails() public {
        vm.deal(address(999), 10 ether);
        vm.prank(address(999));
        vm.expectRevert();
        carpool.depositDriverCollateral{value: MIN}();
    }

    function testRegisterUserTwiceFails() public {
        vm.prank(user);
        vm.expectRevert();
        carpool.registerUser();
    }

    function testWithdrawCollateralWhileOnRideFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        carpool.acceptRide{value: fare}(driver, fare, false, sig);
        
        vm.prank(driver);
        vm.expectRevert();
        carpool.withdrawCollateral(0.1 ether);
    }

    function testWithdrawCollateralExceedsFails() public {
        vm.prank(driver);
        vm.expectRevert();
        carpool.withdrawCollateral(MIN + 1);
    }

    function testWithdrawEmptyFails() public {
        vm.prank(user2);
        vm.expectRevert();
        carpool.withdraw();
    }

    function testAcceptRideUnregisteredUserFails() public {
        address unregistered = address(0x12345);
        vm.deal(unregistered, 10 ether);
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        
        vm.prank(unregistered);
        vm.expectRevert();
        carpool.acceptRide{value: fare}(driver, fare, false, sig);
    }

    function testAcceptRideDriverBusyFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        carpool.acceptRide{value: fare}(driver, fare, false, sig);

        bytes memory sig2 = signAccept(fare, false, 1);
        vm.prank(user2);
        vm.expectRevert();
        carpool.acceptRide{value: fare}(driver, fare, false, sig2);
    }

    function testStartRideInactiveDriverFails() public {
        address d2 = vm.addr(treasuryPk);
        vm.prank(owner);
        carpool.registerDriver(d2, keccak256("id2"), keccak256("doc2"));
        
        uint256 fare = 1 ether;
        bytes32 hash = keccak256(abi.encode(address(carpool), user, d2, fare, false, 0, block.chainid));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(treasuryPk, MessageHashUtils.toEthSignedMessageHash(hash));
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(d2, fare, false, sig);

        vm.prank(d2);
        vm.expectRevert();
        carpool.startRide(id, 1, 2, 3, 4, 3600);
    }

    function testCompleteRideWrongCallerFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(user);
        vm.expectRevert();
        carpool.completeRide(id);
    }

    function testCompleteRideNotStartedFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        vm.expectRevert();
        carpool.completeRide(id);
    }

    function testCompleteRideWithDelay() public {
        uint256 fare = 1 ether;
        // Must use ceiling true, otherwise total = fare and surcharge is capped!
        bytes memory sig = signAccept(fare, true, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: 1.2 ether}(driver, fare, true, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.warp(block.timestamp + 4000);

        vm.prank(driver);
        carpool.completeRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(r.finalFare, fare + 10000);
    }

    function testCompleteRideHittingCeiling() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, true, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: 1.2 ether}(driver, fare, true, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600); 

        vm.warp(block.timestamp + 3600 + 300 + 2e15 + 1);

        vm.prank(driver);
        carpool.completeRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(r.finalFare, 1.2 ether);
    }

    function testJoinSharedRideExpiredFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp - 1;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);

        vm.prank(user2);
        vm.expectRevert();
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);
    }

    function testJoinSharedRideNotStartedFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);

        vm.prank(user2);
        vm.expectRevert();
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);
    }

    function testJoinSharedRideTwiceFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);

        vm.prank(user2);
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);

        bytes memory r1Sig2 = signShareR1(id, 0.2 ether, deadline, 1);
        bytes memory dSig2 = signShareDriver(id, 0.1 ether, deadline, 1);
        
        vm.prank(user2);
        vm.expectRevert();
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig2, dSig2);
    }

    function testJoinSharedRideWrongCallerFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);

        vm.prank(user);
        vm.expectRevert();
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);
    }

    function testJoinSharedRideWrongValueFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);

        vm.prank(user2);
        vm.expectRevert();
        carpool.joinSharedRide{value: 0.2 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);
    }

    function testJoinSharedRideRefundTooHigh() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 1.1 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);

        vm.prank(user2);
        vm.expectRevert();
        carpool.joinSharedRide{value: 1.2 ether}(id, 1.1 ether, 0.1 ether, deadline, r1Sig, dSig);
    }

    function testJoinSharedRideZeroValue() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0, deadline, 0);

        vm.prank(user2);
        vm.expectRevert();
        carpool.joinSharedRide{value: 0}(id, 0, 0, deadline, r1Sig, dSig);
    }

    function testCancelThirdPartyFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(address(0x444));
        vm.expectRevert();
        carpool.cancelRide(id);
    }

    function testCancelNotStartedFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(user);
        vm.expectRevert();
        carpool.cancelRide(id);
    }

    function testCancelSharedRide() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);
        vm.prank(user2);
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);

        vm.prank(user);
        carpool.cancelRide(id); 

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Cancelled));
    }

    function testDisputeThirdPartyFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(address(0x444));
        vm.expectRevert();
        carpool.disputeRide(id);
    }

    function testDisputeNotStartedFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(user);
        vm.expectRevert();
        carpool.disputeRide(id);
    }

    function testResolveNonDisputedFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(owner);
        vm.expectRevert();
        carpool.resolveDispute(id, 0);
    }

    function testResolvePayoutExceedsFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(user);
        carpool.disputeRide(id);

        vm.prank(owner);
        vm.expectRevert();
        carpool.resolveDispute(id, 1.1 ether);
    }

    function testResolveSharedRide() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, 0.2 ether, deadline, 0);
        bytes memory dSig = signShareDriver(id, 0.1 ether, deadline, 0);
        vm.prank(user2);
        carpool.joinSharedRide{value: 0.3 ether}(id, 0.2 ether, 0.1 ether, deadline, r1Sig, dSig);

        vm.prank(user);
        carpool.disputeRide(id);

        vm.prank(owner);
        carpool.resolveDispute(id, 0.5 ether);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Completed));
    }

    function testRateZeroFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);
        vm.prank(driver);
        carpool.completeRide(id);

        vm.prank(user);
        vm.expectRevert();
        carpool.rateDriver(id, 0);
    }

    function testRateSixFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);
        vm.prank(driver);
        carpool.completeRide(id);

        vm.prank(user);
        vm.expectRevert();
        carpool.rateDriver(id, 6);
    }

    function testRateIncompleteFails() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(user);
        vm.expectRevert();
        carpool.rateDriver(id, 5);
    }

    function testRateTwiceFails() public {
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

        vm.prank(user);
        vm.expectRevert();
        carpool.rateDriver(id, 4);
    }
}
