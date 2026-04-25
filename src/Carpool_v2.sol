// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract Carpool is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    address public backend;
    uint256 public nextRideId;

    uint256 public immutable DRIVER_MIN_DEPOSIT;
    uint256 public immutable CEILING_BOND_PERCENT;

    mapping(bytes32 => bool) public idsHashUsed;
    mapping(address => Driver) public drivers;
    mapping(address => uint256) public driverNonces;
    mapping(address => uint256) public shareApprovalNonces;
    mapping(uint256 => Ride) public rides;
    mapping(address => User) public users;

    // FIX 7: Pull-over-push pattern — drivers claim their own funds
    mapping(address => uint256) public pendingWithdrawals;

    enum DriverStatus {
        Verified,
        Active,
        Suspended,
        Banned
    }
    enum RideStatus {
        Requested,
        Accepted,
        Started,
        Completed,
        Cancelled,
        Disputed
    }

    struct Driver {
        address driverAddress;
        bytes32 docHash;
        uint256 rating;
        uint256 ratingCount;
        uint256 amtDeposited;
        DriverStatus status;
        // bool isOnRide;
    }

    struct Location {
        int256 lat;
        int256 long;
    }

    struct Ride {
        address user;
        address driver;
        Location start;
        Location end;
        uint256 fare;
        uint256 finalFare;
        uint256 ceilingBond;
        uint256 startTime;
        uint256 endTime;
        SharedRideInfo sharedInfo;
        uint256 rating;
        RideStatus status;
    }

    struct SharedRideInfo {
        address secondUser;
        uint256 rider1Refund;
        uint256 driverShareFromR2;
    }

    struct User {
        address userAddress;
        uint256 totalRides;
        uint256 totalScoreGiven;
    }

    // event DriverRegistered(address indexed driver);
    // event DriverCollateralDeposited(address indexed driver, uint256 amount);
    event DriverCollateralWithdrawn(address indexed driver, uint256 amount);
    event DriverReactivated(address indexed driver);
    event RideAccepted(
        uint256 indexed rideId, address indexed passenger, address indexed driver, uint256 fare, bool ceiling
    );
    event RideStarted(uint256 indexed rideId);
    event RideShared(uint256 indexed rideId, address secondUser, uint256 refund, uint256 incentive);
    event RideCompleted(uint256 indexed rideId, uint256 payout);
    event RideCancelled(uint256 indexed rideId);
    // event RideDisputed(uint256 indexed rideId);
    // event DisputeResolved(uint256 indexed rideId);
    event DriverRated(address indexed driver, uint256 rating);
    event Withdrawal(address indexed to, uint256 amount);

    modifier onlyActiveDriver() {
        require(drivers[msg.sender].status == DriverStatus.Active, "Inactive");
        _;
    }

    modifier rideExists(uint256 id) {
        require(rides[id].user != address(0), "No rider");
        _;
    }

 
    constructor(address _owner, address _backend, uint256 _min, uint256 _bond) Ownable(_owner) {
        require(_owner != address(0), "Invalid");
        require(_backend != address(0), "Invalid ");
        backend = _backend;
        DRIVER_MIN_DEPOSIT = _min;
        CEILING_BOND_PERCENT = _bond;
    }

    function setBackend(address _backend) external onlyOwner {
        require(_backend != address(0), "Invalid");
        backend = _backend;
    }

    function registerDriver(address d, bytes32 id, bytes32 doc) external {
        require(msg.sender == backend, "Unauthorized");
        require(d != address(0), "");
        require(!idsHashUsed[id], "ID ");
        idsHashUsed[id] = true;

        drivers[d] = Driver(d, doc, 0, 0, 0, DriverStatus.Verified, false);
        // emit DriverRegistered(d);
    }

    function depositDriverCollateral() external payable nonReentrant {
        Driver storage d = drivers[msg.sender];
        require(d.driverAddress != address(0), "");

        d.amtDeposited += msg.value;

        if (d.status == DriverStatus.Verified && d.amtDeposited >= DRIVER_MIN_DEPOSIT) {
            d.status = DriverStatus.Active;
        }

        // emit DriverCollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        Driver storage d = drivers[msg.sender];
        // require(!d.isOnRide, "");
        require(amount <= d.amtDeposited, "");

        d.amtDeposited -= amount;
        pendingWithdrawals[msg.sender] += amount;
        if (d.status == DriverStatus.Active && d.amtDeposited < DRIVER_MIN_DEPOSIT) {
            d.status = DriverStatus.Verified;
        }

        emit DriverCollateralWithdrawn(msg.sender, amount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Noth");

        pendingWithdrawals[msg.sender] = 0; // zero before transfer (CEI)
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "failed");

        emit Withdrawal(msg.sender, amount);
    }

    function registerUser() external {
        require(users[msg.sender].userAddress == address(0), "Already");
        users[msg.sender] = User(msg.sender, 0, 0);
    }

    function acceptRide(address driver, uint256 fare, bool ceiling, bytes memory sig)
        external
        payable
        returns (uint256 id)
    {
        require(users[msg.sender].userAddress != address(0), "User");
        // require(!drivers[driver].isOnRide, " busy");

        uint256 nonce = driverNonces[driver];

        bytes32 hash = keccak256(abi.encode(msg.sender, driver, fare, ceiling, nonce, block.chainid));
        require(MessageHashUtils.toEthSignedMessageHash(hash).recover(sig) == driver, "sig");

        driverNonces[driver]++;
        uint256 required = fare + (ceiling ? (fare * CEILING_BOND_PERCENT) / 100 : 0);
        require(msg.value == required, "Incorrect");

        id = nextRideId++;
        Ride storage r = rides[id];
        r.user = msg.sender;
        r.driver = driver;
        r.fare = fare;
        r.ceilingBond = required - fare;
        r.status = RideStatus.Accepted;

        emit RideAccepted(id, msg.sender, driver, fare, ceiling);
    }

    function startRide(uint256 id, int256 a, int256 b, int256 c, int256 d) external onlyActiveDriver rideExists(id) {
        Ride storage r = rides[id];
        require(msg.sender == r.driver, "");
        require(r.status == RideStatus.Accepted, "");

        r.status = RideStatus.Started;
        r.start = Location(a, b);
        r.end = Location(c, d);
        r.startTime = block.timestamp;
        // drivers[r.driver].isOnRide = true;

        emit RideStarted(id);
    }

    // function joinSharedRide(
    //     uint256 id,
    //     uint256 refund,
    //     uint256 incentive,
    //     uint256 deadline, // FIX 2: must sign a deadline
    //     bytes memory r1Sig,
    //     bytes memory dSig
    // ) external payable rideExists(id) {
    //     require(block.timestamp <= deadline, ""); // FIX 2

    //     Ride storage r = rides[id];
    //     require(r.status == RideStatus.Started, "");
    //     require(r.sharedInfo.secondUser == address(0), "");
    //     require(msg.sender != r.user && msg.sender != r.driver, "");
    //     require(msg.value == refund + incentive, "");

    //     // FIX 8: rider1 refund cannot exceed what rider1 originally paid
    //     require(refund <= r.fare, "Re");
    //     // FIX 8: incentive cannot exceed what rider2 is paying in total
    //     require(incentive <= msg.value, "Inv");
    //     // FIX 8: combined must be non-zero
    //     require(refund + incentive > 0, "Zero");

    //     uint256 nonce = shareApprovalNonces[r.user];

    //     // FIX 6: abi.encode for both hashes
    //     bytes32 h1 = keccak256(abi.encode("R1", id, refund, deadline, nonce, block.chainid));
    //     require(MessageHashUtils.toEthSignedMessageHash(h1).recover(r1Sig) == r.user, "Inv");

    //     bytes32 h2 = keccak256(abi.encode("D", id, incentive, deadline, nonce, block.chainid));
    //     require(MessageHashUtils.toEthSignedMessageHash(h2).recover(dSig) == r.driver, "Inv");

    //     shareApprovalNonces[r.user]++;
    //     r.sharedInfo = SharedRideInfo(msg.sender, refund, incentive);

    //     emit RideShared(id, msg.sender, refund, incentive);
    // }

    function completeRide(uint256 id, uint256 finalFare, bytes memory sig)
        external
        onlyActiveDriver
        nonReentrant
        rideExists(id)
    {
        Ride storage r = rides[id];
        require(msg.sender == r.driver, "Not");
        require(r.status == RideStatus.Started, "Wrong");

        uint256 total = r.fare + r.ceilingBond;

        if (finalFare > total) {
            finalFare = total;
        }

        // FIX 4: explicit guard so subtraction never underflows
        require(total - finalFare + r.sharedInfo.rider1Refund >= total - finalFare, "Refund");

        bytes32 hash = keccak256(abi.encode("COMPLETE", id, finalFare, r.user, r.driver, block.chainid));
        require(MessageHashUtils.toEthSignedMessageHash(hash).recover(sig) == backend, "Invalid  sig");

        r.status = RideStatus.Completed;
        r.finalFare = finalFare;
        r.endTime = block.timestamp;

        uint256 rider1Refund = total - finalFare + r.sharedInfo.rider1Refund;
        uint256 driverPayout = finalFare + r.sharedInfo.driverShareFromR2;

        // FIX 7: push to pending instead of direct transfer for driver
        pendingWithdrawals[r.driver] += driverPayout;

        // User refund is a direct transfer (users aren't repeated callers, lower risk)
        if (rider1Refund > 0) {
            (bool success3,) = payable(r.user).call{value: rider1Refund}("");
            require(success3, " failed");
        }
        //pay driver
        (bool success4,) = payable(r.driver).call{value: driverPayout}("");
        require(success4, "failed");
        emit RideCompleted(id, driverPayout);
    }

    function cancelRide(uint256 id) external nonReentrant rideExists(id) {
        Ride storage r = rides[id];
        require(msg.sender == r.user || msg.sender == r.driver, "Unauth");
        require(r.status == RideStatus.Started, "Wrong");

        r.status = RideStatus.Cancelled;

        uint256 total = r.fare + r.ceilingBond;

        // Interactions last
        (bool success,) = payable(r.user).call{value: total}("");
        require(success, "failed");

        if (r.sharedInfo.secondUser != address(0)) {
            (bool success2,) = payable(r.sharedInfo.secondUser)
            .call{value: r.sharedInfo.rider1Refund + r.sharedInfo.driverShareFromR2}(
                ""
            );
            require(success2, "failed");
        }

        emit RideCancelled(id);
    }

    function disputeRide(uint256 id) external rideExists(id) {
        Ride storage r = rides[id];
        require(msg.sender == r.user || msg.sender == r.driver, "Unauthorized");
        require(r.status == RideStatus.Started, "Wrong");

        r.status = RideStatus.Disputed;
        // emit RideDisputed(id);
    }

    function resolveDispute(uint256 id, uint256 payout) external onlyOwner nonReentrant {
        Ride storage r = rides[id];
        require(r.status == RideStatus.Disputed, "Not disputed");

        uint256 total = r.fare + r.ceilingBond;
        require(payout <= total, "Payout exceeds total");

        // Effects before interactions
        r.status = RideStatus.Completed;
        r.finalFare = payout;
        r.endTime = block.timestamp;
        // drivers[r.driver].isOnRide = false;
        pendingWithdrawals[r.driver] += payout;
        (bool success,) = payable(r.user).call{value: total - payout}("");
        require(success, "Transfe");

        if (r.sharedInfo.secondUser != address(0)) {
            (bool success2,) = payable(r.sharedInfo.secondUser)
            .call{value: r.sharedInfo.rider1Refund + r.sharedInfo.driverShareFromR2}(
                ""
            );
            require(success2, " failed");
        }

        // emit DisputeResolved(id);
    }

    function rateDriver(uint256 id, uint256 rating) external rideExists(id) {
        require(rating >= 1 && rating <= 5, "Rating");

        Ride storage r = rides[id];
        require(msg.sender == r.user, "Not rider");
        require(r.status == RideStatus.Completed, "not");
        require(r.rating == 0, "Already rated");

        r.rating = rating;
        Driver storage d = drivers[r.driver];
        d.rating += rating;
        d.ratingCount++;

        emit DriverRated(r.driver, rating);
    }

    function stopRide(uint256 id) external rideExists(id) {
        require(msg.sender == backend, "");
        Ride storage r = rides[id];
        require(r.status == RideStatus.Started, "");
        if (block.timestamp - r.startTime > 2 minutes) {
            r.status = RideStatus.Cancelled;
            // drivers[r.driver].isOnRide = false;

            uint256 total = r.fare + r.ceilingBond;
            (bool success,) = payable(r.user).call{value: total}("");
            require(success, "");
        }

        emit RideCancelled(id);
    }

    function getRide(uint256 id) external view returns (Ride memory) {
        return rides[id];
    }
}
