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
| 4,602,829 | 22,392 bytes |

### Function Call Costs
| Function Name | Min (gas) | Avg (gas) | Median (gas) | Max (gas) | # Calls |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `acceptRide` | 35,181 | 141,234 | 161,859 | 161,859 | 11 |
| `cancelRide` | 72,992 | 72,992 | 72,992 | 72,992 | 1 |
| `completeRide` | 37,644 | 109,141 | 127,016 | 127,016 | 5 |
| `depositDriverCollateral` | 57,814 | 57,814 | 57,814 | 57,814 | 11 |
| `disputeRide` | 30,842 | 30,842 | 30,842 | 30,842 | 1 |
| `drivers` | 13,228 | 13,228 | 13,228 | 13,228 | 1 |
| `getRide` | 43,241 | 43,241 | 43,241 | 43,241 | 4 |
| `joinSharedRide` | 146,689 | 146,689 | 146,689 | 146,689 | 1 |
| `rateDriver` | 26,461 | 62,859 | 62,859 | 99,257 | 2 |
| `registerDriver` | 106,109 | 106,109 | 106,109 | 106,109 | 11 |
| `registerUser` | 51,165 | 51,165 | 51,165 | 51,165 | 22 |
| `resolveDispute` | 142,999 | 142,999 | 142,999 | 142,999 | 1 |
| `startRide` | 26,310 | 143,591 | 172,166 | 172,166 | 10 |
