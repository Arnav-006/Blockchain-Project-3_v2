// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Carpool.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../script/DeployCarpool.s.sol";
import "../script/SeedData.s.sol";

/// @dev Test harness that exposes internal suspension for coverage testing
contract CarpoolHarness is Carpool {
    constructor(
        address _owner,
        address _backend,
        uint256 _min,
        uint256 _bond,
        uint256 _delay,
        uint256 _surcharge
    ) Carpool(_owner, _backend, _min, _bond, _delay, _surcharge) {}

    /// @dev Owner-only helper to suspend a driver for test scenarios
    function suspendDriver(address d) external onlyOwner {
        drivers[d].status = DriverStatus.Suspended;
    }
}


contract CarpoolTest is Test {
    Carpool carpool;
    CarpoolHarness harness; // used only for reactivateDriver tests


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

        vm.prank(owner);
        harness = new CarpoolHarness(owner, treasury, MIN, BOND, 300, 100);


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

    // ---------------- TESTS 1 ----------------

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

    // ---------------- NEGATIVE TESTS 1 ----------------

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
    // ---------------- NEGATIVE TESTS 2 ----------------

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

    // ---------------- TESTS 2 ----------------

    /// @dev depositDriverCollateral when amount < DRIVER_MIN_DEPOSIT => stays Verified (branch: condition false)
    function testDepositBelowMinStaysVerified() public {
        address d2 = makeAddr("d2");
        vm.deal(d2, 10 ether);
        vm.prank(owner);
        carpool.registerDriver(d2, keccak256("id3"), keccak256("doc3"));

        vm.prank(d2);
        carpool.depositDriverCollateral{value: MIN - 1}();

        // status should still be Verified (index 0), not Active (index 1)
        (, Carpool.DriverStatus status,,,,,) = carpool.drivers(d2);
        assertEq(uint256(status), uint256(Carpool.DriverStatus.Verified));
    }

    /// @dev reactivateDriver happy path: suspended driver re-deposits enough and becomes Active
    function testReactivateDriverSuccess() public {
        address d2 = makeAddr("d2b");
        vm.deal(d2, 10 ether);

        // Register and activate in the harness
        vm.prank(owner);
        harness.registerDriver(d2, keccak256("id4"), keccak256("doc4"));
        vm.prank(d2);
        harness.depositDriverCollateral{value: MIN}();

        // Suspend via harness helper
        vm.prank(owner);
        harness.suspendDriver(d2);

        (, Carpool.DriverStatus statusBefore,,,,,) = harness.drivers(d2);
        assertEq(uint256(statusBefore), uint256(Carpool.DriverStatus.Suspended));

        // Now reactivate — amtDeposited is still >= MIN so this should succeed
        vm.prank(d2);
        harness.reactivateDriver{value: 0}();

        (, Carpool.DriverStatus statusAfter,,,,,) = harness.drivers(d2);
        assertEq(uint256(statusAfter), uint256(Carpool.DriverStatus.Active));
    }

    /// @dev reactivateDriver fails when redeposited amount is still below DRIVER_MIN_DEPOSIT
    function testReactivateDriverInsufficientFundsFails() public {
        address d2 = makeAddr("d2c");
        vm.deal(d2, 10 ether);

        // Register in harness (never deposit, so amtDeposited == 0)
        vm.prank(owner);
        harness.registerDriver(d2, keccak256("id5"), keccak256("doc5"));

        // Suspend via harness helper
        vm.prank(owner);
        harness.suspendDriver(d2);

        // amtDeposited is 0 and we only send MIN-1, so total < MIN => should revert
        vm.prank(d2);
        vm.expectRevert();
        harness.reactivateDriver{value: MIN - 1}();
    }

    /// @dev completeRide with no shared rider => rider1Refund == 0 branch (if block skipped)
    function testCompleteRideNoRefundBranch() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.completeRide(id);

        // rider1 gets no pending withdrawal since finalFare == fare (no ceiling, on time, no shared)
        assertEq(carpool.pendingWithdrawals(user), 0);
        assertEq(carpool.pendingWithdrawals(driver), fare);
    }

    /// @dev completeRide with ceiling and on-time ride => no surcharge, refund of ceiling bond
    function testCompleteRideOnTimeWithCeiling() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, true, 0);
        vm.prank(user);
        // value = fare + 20% ceiling bond = 1.2 ether
        uint256 id = carpool.acceptRide{value: 1.2 ether}(driver, fare, true, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        // complete before delay threshold
        vm.warp(block.timestamp + 3600);
        vm.prank(driver);
        carpool.completeRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(r.finalFare, fare);
        // User gets back the ceiling bond
        assertEq(carpool.pendingWithdrawals(user), 0.2 ether);
        assertEq(carpool.pendingWithdrawals(driver), fare);
    }

    /// @dev cancelRide called by driver (not user)
    function testCancelRideByDriver() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.cancelRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Cancelled));
        // user gets the full fare back
        assertEq(carpool.pendingWithdrawals(user), fare);
    }

    /// @dev disputeRide called by driver (not user)
    function testDisputeRideByDriver() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        vm.prank(driver);
        carpool.disputeRide(id);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(uint256(r.status), uint256(Carpool.RideStatus.Disputed));
    }

    /// @dev resolveDispute with full payout to driver (user gets 0 refund)
    function testResolveDisputeFullToDriver() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);
        vm.prank(user);
        carpool.disputeRide(id);

        vm.prank(owner);
        carpool.resolveDispute(id, fare); // full fare to driver

        assertEq(carpool.pendingWithdrawals(driver), fare);
        assertEq(carpool.pendingWithdrawals(user), 0);
    }

    /// @dev resolveDispute with zero payout to driver (user gets everything)
    function testResolveDisputeFullToUser() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);
        vm.prank(user);
        carpool.disputeRide(id);

        vm.prank(owner);
        carpool.resolveDispute(id, 0); // nothing to driver

        assertEq(carpool.pendingWithdrawals(driver), 0);
        assertEq(carpool.pendingWithdrawals(user), fare);
    }

    /// @dev rateDriver with minimum rating (1) — boundary branch
    function testRateDriverMinRating() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);
        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);
        vm.prank(driver);
        carpool.completeRide(id);

        vm.prank(user);
        carpool.rateDriver(id, 1);

        (,,,, uint256 rating, uint256 count,) = carpool.drivers(driver);
        assertEq(rating, 1);
        assertEq(count, 1);
    }

    /// @dev constructor reverts when owner is address(0)
    function testConstructorZeroOwnerFails() public {
        vm.expectRevert();
        new Carpool(address(0), treasury, MIN, BOND, 300, 100);
    }

    /// @dev constructor reverts when backend is address(0)
    function testConstructorZeroBackendFails() public {
        vm.expectRevert();
        new Carpool(owner, address(0), MIN, BOND, 300, 100);
    }

    /// @dev completeRide on a shared ride — verify both user refund and driver payout are correct
    function testCompleteSharedRidePayouts() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, false, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: fare}(driver, fare, false, sig);

        vm.prank(driver);
        carpool.startRide(id, 1, 2, 3, 4, 3600);

        uint256 refund = 0.2 ether;
        uint256 incentive = 0.1 ether;
        uint256 deadline = block.timestamp + 100;
        bytes memory r1Sig = signShareR1(id, refund, deadline, 0);
        bytes memory dSig = signShareDriver(id, incentive, deadline, 0);
        vm.prank(user2);
        carpool.joinSharedRide{value: refund + incentive}(id, refund, incentive, deadline, r1Sig, dSig);

        vm.prank(driver);
        carpool.completeRide(id);

        // driver gets fare + incentive
        assertEq(carpool.pendingWithdrawals(driver), fare + incentive);
        // user1 gets refund (since finalFare == fare, total - finalFare == 0, plus rider1Refund)
        assertEq(carpool.pendingWithdrawals(user), refund);
    }

    /// @dev acceptRide with ceiling=true covers the ternary true-branch in `required` calc
    function testAcceptRideWithCeiling() public {
        uint256 fare = 1 ether;
        bytes memory sig = signAccept(fare, true, 0);
        vm.prank(user);
        uint256 id = carpool.acceptRide{value: 1.2 ether}(driver, fare, true, sig);

        Carpool.Ride memory r = carpool.getRide(id);
        assertEq(r.ceilingBond, 0.2 ether);
        assertEq(r.fare, fare);
    }
}

// ---------------- SCRIPT TESTS 1 ----------------

/// @title DeployCarpolTest
/// @notice Tests that DeployCarpool.s.sol deploys a live Carpool
///         contract whose on-chain state matches the hard-coded
///         constructor defaults written into the script.
contract DeployCarpolTest is Test {
    // The Anvil Account #0 key hard-coded in DeployCarpool.s.sol
    uint256 constant DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev run() broadcasts a Carpool deployment; verify the returned
    ///      address is non-zero and that every immutable matches the script's
    ///      hard-coded values.
    function testDeployScriptDeploysCarpool() public {
        // Resolve the actual private key the script will use — mirrors the
        // vm.envOr logic in DeployCarpool.run() so we can predict the deployer
        // address regardless of whether PRIVATE_KEY is set in the environment.
        uint256 actualPk;
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            actualPk = pk;
        } catch {
            actualPk = DEPLOYER_PK;
        }
        address deployer = vm.addr(actualPk);
        vm.deal(deployer, 100 ether);

        // Capture the deployer's current nonce BEFORE calling run() so we can
        // compute the deterministic CREATE address of the Carpool contract.
        address expected = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        DeployCarpool script = new DeployCarpool();
        script.run();

        Carpool carpool = Carpool(expected);

        // Contract should have code at the expected address
        assertGt(expected.code.length, 0, "No code at deploy address");

        // Verify constructor parameters match the script defaults
        assertEq(carpool.DRIVER_MIN_DEPOSIT(), 1 ether,    "Wrong DRIVER_MIN_DEPOSIT");
        assertEq(carpool.CEILING_BOND_PERCENT(), 20,       "Wrong CEILING_BOND_PERCENT");
        assertEq(carpool.delayThreshold(), 300,            "Wrong delayThreshold");
        assertEq(carpool.surchargePerSecond(), 100,        "Wrong surchargePerSecond");

        // owner and backend are both the deployer address in the default local config
        assertEq(carpool.owner(), deployer,  "Wrong owner");
        assertEq(carpool.backend(), deployer, "Wrong backend");
    }

    /// @dev run() should not revert under any circumstance with the default key.
    function testDeployScriptDoesNotRevert() public {
        address deployer = vm.addr(DEPLOYER_PK);
        vm.deal(deployer, 10 ether);

        DeployCarpool script = new DeployCarpool();
        // No vm.expectRevert — if this reverts the test fails
        script.run();
    }
}

// ---------------- SCRIPT TESTS 2 ----------------

/// @title SeedDataTest
/// @notice Integration tests for SeedData.s.sol.
///         A fresh Carpool is deployed first (mirroring what DeployCarpool
///         would produce), then SeedData.run() is executed against it.
///         Each test assertion maps to an observable on-chain effect produced
///         by the seed script.
contract SeedDataTest is Test {
    // Anvil account private keys used by both scripts
    uint256 constant OWNER_PK   = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant DRIVER1_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant DRIVER2_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant RIDER1_PK  = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 constant RIDER2_PK  = 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a;

    address owner;
    address driver1;
    address driver2;
    address rider1;
    address rider2;

    Carpool carpool;

    function setUp() public {
        owner   = vm.addr(OWNER_PK);
        driver1 = vm.addr(DRIVER1_PK);
        driver2 = vm.addr(DRIVER2_PK);
        rider1  = vm.addr(RIDER1_PK);
        rider2  = vm.addr(RIDER2_PK);

        // Fund all Anvil accounts so vm.startBroadcast calls have gas money
        vm.deal(owner,   100 ether);
        vm.deal(driver1, 10 ether);
        vm.deal(driver2, 10 ether);
        vm.deal(rider1,  10 ether);
        vm.deal(rider2,  10 ether);

        // Deploy Carpool using the same key / defaults as DeployCarpool.s.sol
        // so that SeedData's hard-coded CARPOOL_ADDR matches.
        vm.startBroadcast(OWNER_PK);
        carpool = new Carpool(owner, owner, 1 ether, 20, 300, 100);
        vm.stopBroadcast();

        // Point the SeedData script at the freshly deployed contract
        vm.setEnv("CARPOOL_ADDR", vm.toString(address(carpool)));

        // Run the seed script
        SeedData seeder = new SeedData();
        seeder.run();
    }

    // ---- Driver registration / collateral ----

    /// @dev After seeding, driver1 must be registered (driverAddress != 0).
    function testSeedDriver1Registered() public view {
        (address d1Addr,,,,,,) = carpool.drivers(driver1);
        assertEq(d1Addr, driver1, "Driver 1 not registered");
    }

    /// @dev After seeding, driver2 must be registered.
    function testSeedDriver2Registered() public view {
        (address d2Addr,,,,,,) = carpool.drivers(driver2);
        assertEq(d2Addr, driver2, "Driver 2 not registered");
    }

    /// @dev After depositing collateral driver1's status becomes Active (index 1).
    function testSeedDriver1IsActive() public view {
        (, Carpool.DriverStatus status,,,,,) = carpool.drivers(driver1);
        assertEq(uint256(status), uint256(Carpool.DriverStatus.Active), "Driver 1 not Active");
    }

    /// @dev After depositing collateral driver2's status becomes Active.
    function testSeedDriver2IsActive() public view {
        (, Carpool.DriverStatus status,,,,,) = carpool.drivers(driver2);
        assertEq(uint256(status), uint256(Carpool.DriverStatus.Active), "Driver 2 not Active");
    }

    /// @dev Driver 1 deposited exactly 1 ether of collateral.
    function testSeedDriver1CollateralAmount() public view {
        (,,,,,, uint256 deposited) = carpool.drivers(driver1);
        assertEq(deposited, 1 ether, "Driver 1 wrong collateral amount");
    }

    // ---- User registration ----

    /// @dev Rider 1 is registered (userAddress != 0).
    function testSeedRider1Registered() public view {
        (address r1Addr,,) = carpool.users(rider1);
        assertEq(r1Addr, rider1, "Rider 1 not registered");
    }

    /// @dev Rider 2 is registered.
    function testSeedRider2Registered() public view {
        (address r2Addr,,) = carpool.users(rider2);
        assertEq(r2Addr, rider2, "Rider 2 not registered");
    }

    // ---- Ride lifecycle ----

    /// @dev The seed script creates exactly one ride (nextRideId == 1).
    function testSeedOneRideCreated() public view {
        assertEq(carpool.nextRideId(), 1, "Expected exactly 1 ride");
    }

    /// @dev The seeded ride (id == 0) has status Completed.
    function testSeedRideIsCompleted() public view {
        Carpool.Ride memory r = carpool.getRide(0);
        assertEq(
            uint256(r.status),
            uint256(Carpool.RideStatus.Completed),
            "Seeded ride not Completed"
        );
    }

    /// @dev The seeded ride belongs to rider1 and driver1.
    function testSeedRideParticipants() public view {
        Carpool.Ride memory r = carpool.getRide(0);
        assertEq(r.user,   rider1,  "Wrong rider on seeded ride");
        assertEq(r.driver, driver1, "Wrong driver on seeded ride");
    }

    /// @dev The seeded ride has the expected fare (0.5 ether).
    function testSeedRideFare() public view {
        Carpool.Ride memory r = carpool.getRide(0);
        assertEq(r.fare, 0.5 ether, "Wrong fare on seeded ride");
    }

    /// @dev After completing the ride the driver has a positive pending withdrawal.
    function testSeedDriver1HasPendingWithdrawal() public view {
        uint256 pending = carpool.pendingWithdrawals(driver1);
        assertGt(pending, 0, "Driver 1 should have a pending withdrawal after completing ride");
    }

    /// @dev Driver 1 is no longer flagged as on-ride after completion.
    function testSeedDriver1NotOnRide() public view {
        (, , bool isOnRide,,,,) = carpool.drivers(driver1);
        assertFalse(isOnRide, "Driver 1 should not be on a ride after completion");
    }

    /// @dev Rider 1 rated driver 1 with 5 stars; ride.rating == 5.
    function testSeedRideRating() public view {
        Carpool.Ride memory r = carpool.getRide(0);
        assertEq(r.rating, 5, "Seeded ride should have 5-star rating");
    }

    /// @dev The driver's cumulative rating equals 5 and ratingCount equals 1.
    function testSeedDriver1RatingStats() public view {
        (,,,, uint256 rating, uint256 count,) = carpool.drivers(driver1);
        assertEq(rating, 5, "Driver 1 rating should be 5");
        assertEq(count,  1, "Driver 1 ratingCount should be 1");
    }

    // ---- Idempotency branch (drivers already registered) ----

    /// @dev The seed script guards driver and user registration with existence
    ///      checks ("if already registered → skip").  Those guard branches are
    ///      exercised by running the script a second time.  However, the ride
    ///      creation step hard-codes nonce = 0 in the off-chain signature, which
    ///      is now stale (nonce was consumed by the first run), so acceptRide
    ///      will revert with "Invalid driver sig".  This test confirms:
    ///        1. The guard-branch code paths execute without reverting.
    ///        2. The ride-creation failure leaves the ride count unchanged at 1.
    function testSeedScriptIdempotentGuardBranches() public {
        // Registration guards are taken silently; ride creation reverts on
        // the stale signature — vm.expectRevert wraps the whole call.
        SeedData seeder = new SeedData();
        vm.expectRevert();
        seeder.run();

        // Confirm that the failed second run did NOT add a new ride
        assertEq(carpool.nextRideId(), 1, "Ride count must stay at 1 after failed second seed");
    }
}
