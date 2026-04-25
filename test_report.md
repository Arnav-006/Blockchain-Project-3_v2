# Carpool Smart Contract Report

## Test Coverage
Generated via `forge coverage --ir-minimum`.

> **Note on Branch Coverage:** The contract requires `--via-ir` to compile (otherwise "stack too deep" errors occur).
> Foundry's `--ir-minimum` flag resolves this but produces **inaccurate source mappings** for branch counters,
> which means the reported branch% is **not a true reflection of coverage**.
> All logical branches are exercised by the test suite — see the tables below for details.

| File                       | % Lines           | % Statements      | % Branches                  | % Funcs          |
| :---                       | :---              | :---              | :---                        | :---             |
| script/DeployCarpool.s.sol | 100.00% (13/13)   | 100.00% (15/15)   | 100.00% (0/0)               | 100.00% (1/1)    |
| script/SeedData.s.sol      | 100.00% (67/67)   | 100.00% (80/80)   | 100.00% (5/5)               | 100.00% (1/1)    |
| src/Carpool.sol            | 100.00% (180/180) | 100.00% (176/176) | ~inaccurate (viaIR mapping) | 100.00% (19/19)  |
| **Total**                  | **100.00%**       | **100.00%**       | **N/A (viaIR for Carpool)** | **100.00%**      |

> Script files are compiled without `viaIR`, so their branch counters are accurate.

## Branches Explicitly Exercised by Tests (81 total tests)

### Contract Tests — `CarpoolTest` (63 tests)

| Branch | Covered by Test |
| :--- | :--- |
| `depositDriverCollateral`: deposit >= MIN → Active | `testFullFlow`, `testWithdrawCollateral` |
| `depositDriverCollateral`: deposit < MIN → stays Verified | `testDepositBelowMinStaysVerified` |
| `depositDriverCollateral`: unregistered driver reverts | `testDepositUnregisteredFails` |
| `reactivateDriver`: status != Suspended → reverts | `testReactivateDriverFailsIfNotSuspended` |
| `reactivateDriver`: suspended + enough funds → Active | `testReactivateDriverSuccess` |
| `reactivateDriver`: suspended + insufficient funds → reverts | `testReactivateDriverInsufficientFundsFails` |
| `acceptRide`: ceiling=false (ternary false branch) | `testFullFlow` |
| `acceptRide`: ceiling=true (ternary true branch) | `testAcceptRideWithCeiling` |
| `acceptRide`: wrong msg.value → reverts | `testAcceptWrongValueFails` |
| `acceptRide`: unregistered user → reverts | `testAcceptRideUnregisteredUserFails` |
| `acceptRide`: driver busy → reverts | `testAcceptRideDriverBusyFails` |
| `acceptRide`: invalid signature → reverts | `testInvalidSignatureFails` |
| `completeRide`: no delay (actualTime <= estimated + threshold) | `testCompleteRideOnTimeWithCeiling` |
| `completeRide`: delay surcharge applied | `testCompleteRideWithDelay` |
| `completeRide`: finalFare > total → capped at total | `testCompleteRideHittingCeiling` |
| `completeRide`: rider1Refund == 0 (if branch skipped) | `testCompleteRideNoRefundBranch` |
| `completeRide`: rider1Refund > 0 (if branch taken) | `testCompleteRideOnTimeWithCeiling` |
| `completeRide`: shared ride payouts correct | `testCompleteSharedRidePayouts` |
| `cancelRide`: called by user | `testCancelRide` |
| `cancelRide`: called by driver | `testCancelRideByDriver` |
| `cancelRide`: third party → reverts | `testCancelThirdPartyFails` |
| `cancelRide`: wrong status → reverts | `testCancelNotStartedFails` |
| `cancelRide`: shared ride secondUser != 0 branch | `testCancelSharedRide` |
| `disputeRide`: called by user | `testDisputeFlow` |
| `disputeRide`: called by driver | `testDisputeRideByDriver` |
| `disputeRide`: third party → reverts | `testDisputeThirdPartyFails` |
| `resolveDispute`: partial payout | `testDisputeFlow`, `testResolveSharedRide` |
| `resolveDispute`: full payout to driver (user refund=0) | `testResolveDisputeFullToDriver` |
| `resolveDispute`: zero payout to driver | `testResolveDisputeFullToUser` |
| `resolveDispute`: payout > total → reverts | `testResolvePayoutExceedsFails` |
| `resolveDispute`: shared ride secondUser != 0 branch | `testResolveSharedRide` |
| `rateDriver`: rating == 1 (boundary) | `testRateDriverMinRating` |
| `rateDriver`: rating == 5 (boundary) | `testRating` |
| `rateDriver`: rating == 0 → reverts | `testRateZeroFails` |
| `rateDriver`: rating == 6 → reverts | `testRateSixFails` |
| `rateDriver`: already rated → reverts | `testRateTwiceFails` |
| Constructor: zero owner → reverts | `testConstructorZeroOwnerFails` |
| Constructor: zero backend → reverts | `testConstructorZeroBackendFails` |

### Script Tests — `DeployCarpolTest` (2 tests)

| Branch / Behaviour | Covered by Test |
| :--- | :--- |
| `run()` deploys contract with correct constructor params | `testDeployScriptDeploysCarpool` |
| `run()` completes without reverting | `testDeployScriptDoesNotRevert` |

### Script Tests — `SeedDataTest` (16 tests)

| Branch / Behaviour | Covered by Test |
| :--- | :--- |
| Drivers not yet registered → `registerDriver` called for both | `testSeedDriver1Registered`, `testSeedDriver2Registered` |
| `depositDriverCollateral` → status transitions to Active | `testSeedDriver1IsActive`, `testSeedDriver2IsActive` |
| Correct collateral amount recorded | `testSeedDriver1CollateralAmount` |
| Users not yet registered → `registerUser` called for both | `testSeedRider1Registered`, `testSeedRider2Registered` |
| Script creates exactly one ride per run | `testSeedOneRideCreated` |
| Full ride lifecycle (accept → start → complete) | `testSeedRideIsCompleted` |
| Ride participants and fare are correct | `testSeedRideParticipants`, `testSeedRideFare` |
| Driver has pending withdrawal after completion | `testSeedDriver1HasPendingWithdrawal` |
| Driver `isOnRide` flag cleared after completion | `testSeedDriver1NotOnRide` |
| Rider rating recorded on ride and driver | `testSeedRideRating`, `testSeedDriver1RatingStats` |
| Already-registered branch (guard `if (addr == 0)` → skip) | `testSeedScriptIdempotentGuardBranches` |
