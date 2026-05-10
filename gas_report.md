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

### Gas Optimization Techniques

| Technique | Gas Saved Per Use | Where Applied |
| :--- | :--- | :--- |
| `unchecked` arithmetic | ~20–80 gas | Nonce increments, counter increments, time arithmetic |
| `immutable` variables | ~2,000 gas (cold `SLOAD` avoided) | 4 config params (`DRIVER_MIN_DEPOSIT`, `CEILING_BOND_PERCENT`, `delayThreshold`, `surchargePerSecond`) |
| Local caching of storage fields | ~100–2,000 gas per extra read avoided | `completeRide`, `cancelRide`, `resolveDispute` |
| Pull-over-push payment pattern | Saves multi-transfer base costs per tx | All payout functions (`completeRide`, `cancelRide`, `resolveDispute`) |
| `storage` pointer references | ~20 gas per mapping re-hash avoided | All functions that touch `drivers` or `rides` |
| No `SafeMath` library (Solidity 0.8.x) | ~200–500 gas per arithmetic op | All arithmetic operations |
