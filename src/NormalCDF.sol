// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {TMaths} from "./TMaths.sol";

/// @title NormalCDF - Standard Normal Cumulative Distribution Function
/// @notice Computes Φ(x) for Black-Scholes N(d1), N(d2)
/// @dev Algorithm: Abramowitz & Stegun 26.2.17 (5-term rational approximation)
///      Uses TMaths.exp() for exp(-x²/2). Pure assembly for the polynomial.
///      < 5 ppm error for |x| ≤ 3. All values scaled by 1e18.
///
///      Constants (inlined as literals):
///        SQRT_2PI = 2506628274631000502   // √(2π) * 1e18
///        p        = 231641900000000000    // 0.2316419 * 1e18
///        a1       = 319381530000000000    // +0.319381530 * 1e18
///        a2       = 356563782000000000    //  0.356563782 * 1e18 (negative)
///        a3       = 1781477937000000000   // +1.781477937 * 1e18
///        a4       = 1821255978000000000   //  1.821255978 * 1e18 (negative)
///        a5       = 1330274429000000000   // +1.330274429 * 1e18
library NormalCDF {

    /// @notice Standard normal CDF: Φ(x)
    /// @param negative If true, computes Φ(-|x|)
    /// @param x The absolute value of the input, scaled by 1e18
    /// @return cdf The result in [0, 1e18]
    function normalCdf(
        bool negative,
        uint256 x
    ) internal pure returns (uint256 cdf) {

        // ════════════════════════════════════════════════
        // Early exits (no assembly needed)
        // ════════════════════════════════════════════════
        if (x == 0) {
            return 0.5e18;
        }

        if (x > 8.5e18) {
            return negative ? 0 : 1e18;
        }

        // ════════════════════════════════════════════════
        // Step 1: exp(-x²/2) via TMaths
        // ════════════════════════════════════════════════
        uint256 x_sq_half = (x * x) / 2e18;
        uint256 exp_val = TMaths.exp(false, x_sq_half);

        // ════════════════════════════════════════════════
        // Steps 2-4: φ(x), t, Q(t), combine — in assembly
        // ════════════════════════════════════════════════
        assembly {
            // φ(x) = exp(-x²/2) / √(2π)
            let phi := div(
                mul(exp_val, 1000000000000000000),
                2506628274631000502 // SQRT_2PI
            )

            // t = 1 / (1 + p·|x|)
            let t := div(
                1000000000000000000000000000000000000, // 1e36
                add(
                    1000000000000000000,
                    div(
                        mul(231641900000000000, x), // p * x
                        1000000000000000000
                    )
                )
            )

            // ════════════════════════════════════════════
            // Horner evaluation of Q(t)
            //   Q = t·(a1 + t·(a2 + t·(a3 + t·(a4 + t·a5))))
            //   a2, a4 negative — track sign with h_neg
            // ════════════════════════════════════════════

            // h = t*a5 - |a4|
            let h := div(
                mul(t, 1330274429000000000), // t * a5
                1000000000000000000
            )
            let h_neg := 0
            switch gt(h, 1821255978000000000) // |a4|
            case 1 { h := sub(h, 1821255978000000000) }
            default {
                h := sub(1821255978000000000, h)
                h_neg := 1
            }

            // h = a3 ± t*|h|
            {
                let th := div(mul(t, h), 1000000000000000000)
                switch h_neg
                case 1 { h := sub(1781477937000000000, th) } // a3 - th
                default { h := add(1781477937000000000, th) } // a3 + th
                h_neg := 0
            }

            // h = t*h - |a2|
            {
                let th := div(mul(t, h), 1000000000000000000)
                switch gt(th, 356563782000000000) // |a2|
                case 1 {
                    h := sub(th, 356563782000000000)
                    h_neg := 0
                }
                default {
                    h := sub(356563782000000000, th)
                    h_neg := 1
                }
            }

            // h = a1 ± t*|h|
            {
                let th := div(mul(t, h), 1000000000000000000)
                switch h_neg
                case 1 { h := sub(319381530000000000, th) } // a1 - th
                default { h := add(319381530000000000, th) } // a1 + th
            }

            // Q = t * h
            let Q := div(mul(t, h), 1000000000000000000)

            // ════════════════════════════════════════════
            // tail = φ(x) · Q(t)
            // Φ(|x|)  = 1 - tail
            // Φ(-|x|) = tail
            // ════════════════════════════════════════════
            let tail := div(mul(phi, Q), 1000000000000000000)

            switch negative
            case 1 { cdf := tail }
            default { cdf := sub(1000000000000000000, tail) }
        }
    }
}
