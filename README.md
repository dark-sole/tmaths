# TMaths

Gas-efficient mathematical functions for Solidity, implemented in pure assembly.

## Overview

TMaths provides `exp(x)`, `ln(x)`, `sqrt(x)`, and trigonometric functions (`sin`, `cos`, `tan`) optimized for EVM execution. All functions use decomposition techniques to normalize inputs, then apply Taylor series or Newton-Raphson on the bounded remainder.

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

        // Trigonometry (radians, scaled by 1e18)
        (uint256 sinVal, bool sinSign) = TMaths.sin(1e18);  // sin(1) ≈ 0.841e18
        (uint256 cosVal, bool cosSign) = TMaths.cos(1e18);  // cos(1) ≈ 0.540e18
        (uint256 tanVal, bool tanSign) = TMaths.tan(1e18);  // tan(1) ≈ 1.557e18

        // Squared trig (more efficient than squaring)
        uint256 sin2 = TMaths.sin_sq(1e18);           // sin²(1) ≈ 0.708e18
        uint256 cos2 = TMaths.cos_sq(1e18);           // cos²(1) ≈ 0.292e18
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

### `sin(uint256 x) → (uint256 result, bool sign)`

Calculates the sine of an angle in radians.

| Parameter | Description |
|-----------|-------------|
| `x` | The angle in radians, scaled by 1e18 |
| **Returns** | `result`: absolute value, scaled by 1e18 |
| | `sign`: true if positive, false if negative |

### `cos(uint256 x) → (uint256 result, bool sign)`

Calculates the cosine of an angle in radians.

| Parameter | Description |
|-----------|-------------|
| `x` | The angle in radians, scaled by 1e18 |
| **Returns** | `result`: absolute value, scaled by 1e18 |
| | `sign`: true if positive, false if negative |

### `tan(uint256 x) → (uint256 result, bool sign)`

Calculates the tangent of an angle in radians.

| Parameter | Description |
|-----------|-------------|
| `x` | The angle in radians, scaled by 1e18 |
| **Returns** | `result`: absolute value, scaled by 1e18 |
| | `sign`: true if positive, false if negative |

Note: Reverts when cos(x) ≈ 0 (at π/2, 3π/2, etc.) due to division by zero.

### `sin_sq(uint256 x) → uint256`

Calculates sin²(x) using the identity `sin²(x) = (1 - cos(2x)) / 2`.

| Parameter | Description |
|-----------|-------------|
| `x` | The angle in radians, scaled by 1e18 |
| **Returns** | Result scaled by 1e18 (always positive) |

### `cos_sq(uint256 x) → uint256`

Calculates cos²(x) using the identity `cos²(x) = (1 + cos(2x)) / 2`.

| Parameter | Description |
|-----------|-------------|
| `x` | The angle in radians, scaled by 1e18 |
| **Returns** | Result scaled by 1e18 (always positive) |

## Performance

| Function | Gas | Max Error |
|----------|-----|-----------|
| `exp(true, x)` | ~200-400 | < 0.01% |
| `exp(false, x)` | ~200-400 | < 0.01% |
| `ln(x)` | ~300-500 | 8 bps* |
| `sqrt(x)` | ~200-400 | 0 bps |
| `sin(x)` | ~440-690 | 5 ppm |
| `cos(x)` | ~440-690 | 5 ppm |
| `tan(x)` | ~880-1380 | 5 ppm |
| `sin_sq(x)` | ~440-690 | 5 ppm |
| `cos_sq(x)` | ~440-690 | 5 ppm |

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

### sin(x) / cos(x)
1. **Fast path** (x < π/2): Direct Taylor series, always positive
2. **Full path**: Octant reduction using `x * (4/π)` to get octant index
3. Map to Taylor series for sin or cos based on octant
4. Determine sign using bit patterns (cos: `0b11000011`, sin: `0b00001111`)
5. Apply 4-term Taylor series on reduced angle θ < π/4

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
