# TMaths

Gas-efficient mathematical functions and option pricing for Solidity, implemented in pure assembly.

## Overview

TMaths provides a suite of on-chain mathematical libraries:

| Library | Purpose | Gas |
|---------|---------|-----|
| **TMaths** | Core math: `exp`, `ln`, `sqrt`, `sin`, `cos`, `tan` | 200–1,400 |
| **NormalCDF** | Gaussian cumulative distribution function | ~1,460 |
| **DaletCDF** | Heavy-tailed CDF (Student-*t*, ν=2) | ~1,000 |
| **BlackScholes** | European option pricing (Normal model) | ~6,200 |
| **DaletOption** | European option pricing (Dalet model, log-space) | ~4,500 |

All functions use decomposition techniques and assembly-only implementations optimised for EVM execution. Values are scaled by 1e18 (18-decimal fixed-point).

**Requirements:** Solidity 0.8.31+ with Osaka EVM (`clz` opcode)

## Installation

```bash
forge install tokenisys/tmaths
```

Or copy the `src/` directory into your project.

## Quick Start

```solidity
import {TMaths} from "tmaths/TMaths.sol";
import {NormalCDF} from "tmaths/NormalCDF.sol";
import {DaletCDF} from "tmaths/DaletCDF.sol";
import {BlackScholes} from "tmaths/BlackScholes.sol";
import {DaletOption} from "tmaths/DaletOption.sol";

contract Example {
    function priceOptions() external pure {
        // Black-Scholes: S=100, K=100, T=1yr, r=5%, y=0%, σ=20%
        (uint256 call, uint256 put, uint256 dc, uint256 dp) =
            BlackScholes.price(100e18, 100e18, 1e18, 5e16, 0, 20e16);
        // call ≈ 10.45e18, put ≈ 5.57e18

        // Dalet option (fat-tailed model, same inputs minus yield)
        (uint256 callD, uint256 putD, uint256 dcD, uint256 dpD) =
            DaletOption.price(100e18, 100e18, 1e18, 5e16, 20e16);
        // callD ≈ 11.68e18, putD ≈ 8.54e18 (heavier tails → higher prices)
    }
}
```

---

## TMaths — Core Mathematical Functions

```solidity
import {TMaths} from "tmaths/TMaths.sol";

// Exponential: e^x and e^-x
uint256 growth = TMaths.exp(true, 2e18);       // e^2 ≈ 7.389e18
uint256 decay  = TMaths.exp(false, 1e18);      // e^-1 ≈ 0.368e18

// Natural logarithm
(bool neg, uint256 val) = TMaths.ln(5e18);     // ln(5) ≈ 1.609e18

// Square root
uint256 root = TMaths.sqrt(10e18);             // √10 ≈ 3.162e18

// Trigonometry (radians, scaled by 1e18)
(uint256 s, bool sSign) = TMaths.sin(1e18);   // sin(1) ≈ 0.841e18
(uint256 c, bool cSign) = TMaths.cos(1e18);   // cos(1) ≈ 0.540e18
(uint256 t, bool tSign) = TMaths.tan(1e18);   // tan(1) ≈ 1.557e18

// Squared trig (more efficient than squaring)
uint256 sin2 = TMaths.sin_sq(1e18);           // sin²(1) ≈ 0.708e18
uint256 cos2 = TMaths.cos_sq(1e18);           // cos²(1) ≈ 0.292e18
```

### Functions

| Function | Description | Gas | Max Error |
|----------|-------------|-----|-----------|
| `exp(bool positive, uint256 exponent)` | e^x or e^-x | 200–400 | < 0.01% |
| `ln(uint256 antilog)` | Natural logarithm | 300–500 | 8 bps |
| `sqrt(uint256 x)` | Square root | 200–400 | 0 bps |
| `sin(uint256 x)` | Sine (radians) | 440–690 | 5 ppm |
| `cos(uint256 x)` | Cosine (radians) | 440–690 | 5 ppm |
| `tan(uint256 x)` | Tangent (radians) | 880–1,380 | 5 ppm |
| `sin_sq(uint256 x)` | sin²(x) | 440–690 | 5 ppm |
| `cos_sq(uint256 x)` | cos²(x) | 440–690 | 5 ppm |

### How It Works

All functions use **2^k decomposition** to normalise inputs to a small range, then apply iterative methods:

- **exp(x):** Decompose `x = k·ln(2) + r`, compute `e^r` via 5-term Taylor, result = `2^k · e^r`
- **ln(x):** Find `k = floor(log2(x))` via `clz` opcode, normalise to `[1, 2)`, Taylor series on remainder
- **sqrt(x):** Find `k` rounded to even, normalise, 4-iteration Newton-Raphson, result = `2^(k/2) · sqrt(ratio)`
- **sin/cos(x):** Octant reduction via `x · (4/π)`, 4-term Taylor series on reduced angle `θ < π/4`

---

## NormalCDF — Gaussian Distribution

```solidity
import {NormalCDF} from "tmaths/NormalCDF.sol";

// Φ(1.96) ≈ 0.975
uint256 cdf = NormalCDF.normalCdf(false, 1_960000000000000000);

// Φ(-1.96) ≈ 0.025
uint256 cdf_neg = NormalCDF.normalCdf(true, 1_960000000000000000);
```

### `normalCdf(bool negative, uint256 x) → uint256`

Computes Φ(x), the standard normal CDF, using polynomial–exponential approximation (Abramowitz & Stegun). Exact symmetry: Φ(x) + Φ(-x) = 1e18.

| Parameter | Description |
|-----------|-------------|
| `negative` | `true` for Φ(-\|x\|), `false` for Φ(\|x\|) |
| `x` | Absolute value of input, scaled by 1e18 |
| **Returns** | CDF value in [0, 1e18] |
| **Gas** | ~1,460 |

---

## DaletCDF — Heavy-Tailed Distribution

The Dalet distribution is a Student-*t* with ν=2, the heaviest-tailed distribution in the Student-*t* family with a finite mean. CDF: `Φ_D(x) = (1 + x/√(1+x²)) / 2`.

```solidity
import {DaletCDF} from "tmaths/DaletCDF.sol";

// Fast version (1 sqrt, recommended)
uint256 cdf = DaletCDF.daletCdfFast(false, 2e18);  // Φ_D(2) ≈ 0.947e18

// Geometric route (2 sqrts, angular decomposition)
uint256 cdf2 = DaletCDF.daletCdf(false, 2e18);     // same result
```

### Functions

| Function | Description | Gas |
|----------|-------------|-----|
| `daletCdfFast(bool negative, uint256 x)` | Algebraic form, 1 sqrt | ~1,000 |
| `daletCdf(bool negative, uint256 x)` | Geometric route, 2 sqrts | ~1,470 |

Both produce identical results (within ±1 wei from rounding). Exact symmetry: Φ_D(x) + Φ_D(-x) = 1e18.

### Why Dalet?

The Normal distribution assigns ~0.27% probability to 3σ events. BTC-USD empirical data shows ~2% at 3σ. The Dalet distribution captures this: it predicts ~3.3% at 3σ, providing a conservative (safe) bound for tail risk. See the [research paper](dalet_paper.pdf) for the full analysis.

---

## BlackScholes — Normal-Based Option Pricing

```solidity
import {BlackScholes} from "tmaths/BlackScholes.sol";

(uint256 call, uint256 put, uint256 delta_call, uint256 delta_put) =
    BlackScholes.price(
        100e18,  // S: spot price
        100e18,  // K: strike price
        1e18,    // T: time to expiry (years)
        5e16,    // r: risk-free rate (5%)
        0,       // y: dividend yield (0%)
        20e16    // sigma: volatility (20%)
    );
// call ≈ 10.45e18, put ≈ 5.57e18
// delta_call ≈ 0.637e18, delta_put ≈ 0.363e18
```

### `price(S, K, T, r, y, sigma) → (call_price, put_price, delta_call, delta_put)`

Standard Black-Scholes European option pricing. Put computed via put-call parity (single pricing path). Only 2 CDF evaluations using the identity N(-x) = 1 - N(x).

| Parameter | Description |
|-----------|-------------|
| `S` | Spot price, scaled by 1e18 |
| `K` | Strike price, scaled by 1e18 |
| `T` | Time to expiry in years, scaled by 1e18 |
| `r` | Risk-free rate as decimal, scaled by 1e18 |
| `y` | Dividend/carry yield as decimal, scaled by 1e18 |
| `sigma` | Volatility as decimal, scaled by 1e18 |
| **Returns** | `call_price`, `put_price`, `delta_call`, `delta_put` — all scaled by 1e18 |
| **Gas** | ~6,200 |

---

## DaletOption — Fat-Tailed Option Pricing

Options priced in log-return space using the Dalet distribution. All integrals are elementary trigonometric functions — no divergent exponential moments. Converts to price space via a single `exp` call at the end.

```solidity
import {DaletOption} from "tmaths/DaletOption.sol";

(uint256 call, uint256 put, uint256 delta_call, uint256 delta_put) =
    DaletOption.price(
        100e18,  // S: spot price
        100e18,  // K: strike price
        1e18,    // T: time to expiry (years)
        5e16,    // r: risk-free rate (5%)
        20e16    // sigma: volatility (20%)
    );
// call ≈ 11.68e18, put ≈ 8.54e18
// delta_call ≈ 0.574e18, delta_put ≈ 0.426e18
```

### `price(S, K, T, r, sigma) → (call_price, put_price, delta_call, delta_put)`

Log-space call formula:

```
C_log = e^{-rT} · [ s·cos(θ*)/2  +  (m + μ) · (1 - Φ_D(x*)) ]
```

where `s = σ√T`, `m = ln(S/K)`, `μ = (r - σ²/2)T`, `x* = -(m+μ)/s`.

| Parameter | Description |
|-----------|-------------|
| `S` | Spot price, scaled by 1e18 |
| `K` | Strike price, scaled by 1e18 |
| `T` | Time to expiry in years, scaled by 1e18 |
| `r` | Risk-free rate as decimal, scaled by 1e18 |
| `sigma` | Volatility as decimal, scaled by 1e18 |
| **Returns** | `call_price`, `put_price`, `delta_call`, `delta_put` — all scaled by 1e18 |
| **Gas** | ~4,500 (ATM) to ~5,200 (OTM) |

### Dalet vs Black-Scholes

| Scenario | Dalet | Black-Scholes | Ratio |
|----------|-------|---------------|-------|
| ATM call (K=100, T=1yr) | 11.68 | 10.45 | 1.12× |
| OTM call (K=120, T=0.25) | 1.32 | 0.20 | 6.6× |
| Deep OTM call (K=150, T=0.25) | 0.61 | 0.0001 | ~5,200× |

The Dalet model prices OTM options significantly higher due to heavier tails, better reflecting empirical tail risk in cryptocurrency markets.

---

## Performance Summary

| Library | Function | Gas |
|---------|----------|-----|
| TMaths | `exp` | 200–400 |
| TMaths | `ln` | 300–500 |
| TMaths | `sqrt` | 200–400 |
| TMaths | `sin`/`cos` | 440–690 |
| NormalCDF | `normalCdf` | ~1,460 |
| DaletCDF | `daletCdfFast` | ~1,000 |
| BlackScholes | `price` | ~6,200 |
| DaletOption | `price` | ~4,500–5,200 |

## Testing

```bash
forge test -vv
```

Run accuracy reports:

```bash
forge test --match-test AccuracyReport -vv
```

## Foundry Configuration

Add to `foundry.toml`:

```toml
[profile.default]
solc = "0.8.31"
evm_version = "osaka"
via_ir = true
```

## License

UNLICENSED — © 2025 Tokenisys. All rights reserved.

## Contributing

Issues and pull requests welcome at [github.com/tokenisys/tmaths](https://github.com/tokenisys/tmaths).
