# Carpool Smart Contract Report

## Test Coverage
Generated via `forge coverage --ir-minimum`.

| File            | % Lines          | % Statements     | % Branches    | % Funcs        |
| :---            | :---             | :---             | :---          | :---           |
| src/Carpool.sol | 80.00% (136/170) | 79.65% (137/172) | 6.73% (7/104) | 78.95% (15/19) |
| **Total**       | **80.00%**       | **79.65%**       | **6.73%**     | **78.95%**     |

## Gas Report
Generated via `forge test --gas-report --via-ir`.

### Deployment Costs
| Deployment Cost | Deployment Size |
| :--- | :--- |
| 4,589,128 | 22,331 bytes |

### Function Call Costs
| Function Name | Min (gas) | Avg (gas) | Median (gas) | Max (gas) | # Calls |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `acceptRide` | 34,724 | 158,541 | 183,111 | 183,111 | 11 |
| `cancelRide` | 59,704 | 59,704 | 59,704 | 59,704 | 1 |
| `completeRide` | 39,393 | 111,641 | 129,704 | 129,704 | 5 |
| `depositDriverCollateral` | 76,908 | 76,908 | 76,908 | 76,908 | 11 |
| `disputeRide` | 32,836 | 32,836 | 32,836 | 32,836 | 1 |
| `drivers` | 15,229 | 15,229 | 15,229 | 15,229 | 1 |
| `getRide` | 45,241 | 45,241 | 45,241 | 45,241 | 4 |
| `joinSharedRide` | 147,459 | 147,459 | 147,459 | 147,459 | 1 |
| `rateDriver` | 26,461 | 63,992 | 63,992 | 101,524 | 2 |
| `registerDriver` | 108,092 | 108,092 | 108,092 | 108,092 | 11 |
| `registerUser` | 51,165 | 51,165 | 51,165 | 51,165 | 22 |
| `resolveDispute` | 132,208 | 132,208 | 132,208 | 132,208 | 1 |
| `startRide` | 26,310 | 145,386 | 174,160 | 174,160 | 10 |
