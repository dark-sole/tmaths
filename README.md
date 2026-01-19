# TMaths

Gas-efficient mathematical functions for Solidity, implemented in pure assembly.

## Overview

TMaths provides `exp(x)`, `ln(x)`, and `sqrt(x)` functions optimized for EVM execution. All functions use 2^k decomposition to normalize inputs, then apply Taylor series (for exp/ln) or Newton-Raphson (for sqrt) on the bounded remainder.

**Requirements:** Solidity 0.8.31+ with Osaka EVM (`clz` opcode)

## Installation

```bash
forge install tokenisys/tmaths
```

Or copy `src/TMaths.sol` directly into your project.

## Usage

```solidity
import {TMaths} from "tmaths/TMaths.sol";

contract MyContract {
    function example() external pure {
        // Exponential: e^x
        uint256 growth = TMaths.exp(true, 2e18);      // e^2 ≈ 7.389e18
        uint256 decay = TMaths.exp(false, 1e18);      // e^-1 ≈ 0.368e18
        
        // Natural logarithm: ln(x)
        (bool neg, uint256 val) = TMaths.ln(5e18);    // ln(5) ≈ 1.609e18
        (bool neg2, uint256 val2) = TMaths.ln(5e17);  // ln(0.5) ≈ -0.693e18
        
        // Square root: sqrt(x)
        uint256 root = TMaths.sqrt(10e18);            // sqrt(10) ≈ 3.162e18
    }
}
```

All inputs and outputs are scaled by 1e18 (18 decimal fixed-point).

## Functions

### `exp(bool positive, uint256 exponent) → uint256`

Calculates e^x (or e^-x if `positive` is false).

| Parameter | Description |
|-----------|-------------|
| `positive` | `true` for e^x, `false` for e^-x |
| `exponent` | The exponent, scaled by 1e18 |
| **Returns** | Result scaled by 1e18 |

Reverts with `ExponentTooLarge()` if exponent > 61e18 (would overflow uint256).

### `ln(uint256 antilog) → (bool negative, uint256 result)`

Calculates the natural logarithm.

| Parameter | Description |
|-----------|-------------|
| `antilog` | The value to take ln of, scaled by 1e18 |
| **Returns** | `negative`: true if result < 0 (when input < 1e18) |
| | `result`: absolute value, scaled by 1e18 |

Reverts with `ZeroInput()` if antilog is 0.

### `sqrt(uint256 x) → uint256`

Calculates the square root.

| Parameter | Description |
|-----------|-------------|
| `x` | The value to take sqrt of, scaled by 1e18 |
| **Returns** | Result scaled by 1e18 |

Reverts with `ZeroInput()` if x is 0.

## Performance

| Function | Gas | Max Error |
|----------|-----|-----------|
| `exp(true, x)` | ~654-745 | 0 bps |
| `exp(false, x)` | ~757 | 0 bps |
| `ln(x)` | ~859-930 | 8 bps* |
| `sqrt(x)` | ~680-724 | 0 bps |

*Worst case error for ln() occurs at x = 1.5 and its multiples by powers of 2.

## How It Works

All three functions use **2^k decomposition** to normalize inputs to a small range, then apply iterative methods:

### exp(x)
1. Decompose: `x = k * ln(2) + r` where `r ∈ [0, ln(2))`
2. Compute `e^r` using 5-term Taylor series
3. Result: `e^x = 2^k * e^r`

### ln(x)
1. Find `k = floor(log2(x))` using `clz` opcode
2. Normalize: `m = x / 2^k` where `m ∈ [1, 2)`
3. If `m > 1.5`: use `ln(1-y)` series from above
4. Else: use `ln(1+y)` series from below
5. Result: `ln(x) = k * ln(2) ± taylor(y)`

### sqrt(x)
1. Find `k = floor(log2(x))`, rounded to even
2. Normalize: `ratio = x / 2^k` where `ratio ∈ [1, 2)`
3. Compute `sqrt(ratio)` using 4-iteration Newton-Raphson
4. Result: `sqrt(x) = 2^(k/2) * sqrt(ratio)`

## Testing

```bash
forge test -vv
```

Run the accuracy report:

```bash
forge test --match-test AccuracyReport -vv
```

## Foundry Configuration

Add to `foundry.toml`:

```toml
[profile.default]
solc = "0.8.31"
evm_version = "osaka"
```

## License

UNLICENSED - © 2025 Tokenisys. All rights reserved.

## Contributing

Issues and pull requests welcome at [github.com/tokenisys/tmaths](https://github.com/tokenisys/tmaths).
