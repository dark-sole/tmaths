// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

// To deploy on a non-Fusaka chain (e.g. Base, OP Mainnet, Unichain as of May 2026),
// change the import below to: import {TMathLegacy as TMaths} from "./TMathLegacy.sol";
import {TMathFusaka as TMaths} from "./TMathFusaka.sol";

/// @title DaletCDF - Dalet distribution CDF
/// @notice Computes Φ_D(x) = (1 + x/√(1+x²)) / 2
/// @dev A trigonometric CDF derived from angular parameters of implied tangent.
///      Heavier tails than Normal, lighter than Cauchy.
///      Two implementations provided:
///        daletCdf     - geometric route via half-angle decomposition (2 sqrt calls)
///        daletCdfFast - closed-form algebraic simplification (1 sqrt call)
///      Both produce identical results (within ±1 wei from rounding).
///      All values scaled by 1e18.
library DaletCDF {

    /// @notice Geometric route: angular decomposition via half-angle space
    /// @dev Algorithm:
    ///   1. cos²θ = 1/(1+x²)           — recover cosine from implied tangent
    ///   2. cosθ  = √(cos²θ)            — first sqrt
    ///   3. cos²(θ/2) = (1+cosθ)/2      — half-angle identity
    ///   4. prod = cos²(θ/2)·sin²(θ/2)  — Bernoulli variance = sin²θ/4
    ///   5. sinθ/2 = √(prod)            — second sqrt
    ///   6. tail = (1 - sinθ)/2
    /// @param negative If true, computes Φ_D(-|x|)
    /// @param x The absolute value of the input, scaled by 1e18
    /// @return cdf The result in [0, 1e18]
    function daletCdf(
        bool negative,
        uint256 x
    ) internal pure returns (uint256 cdf) {

        if (x == 0) return 0.5e18;
        // x²  overflows uint256 above ~3.4e38, i.e. x ~ 340e18.
        // At x=340 the tail is ~0.0015 — not negligible, so we clamp conservatively.
        if (x >= 340e18) return negative ? 0 : 1e18;

        // Step 1: sigma_log = 1/(1 + x²)
        uint256 sigma_log;
        assembly {
            let P := 1000000000000000000
            let x_sq := div(mul(x, x), P)
            sigma_log := div(mul(P, P), add(x_sq, P))
        }

        // Step 2: cosθ = √(1/(1+x²))
        uint256 sigma_root = TMaths.sqrt(sigma_log);

        // Steps 3-4: s_sq = (1+cosθ)/2, prod = s_sq·(1-s_sq) = sin²θ/4
        uint256 prod;
        assembly {
            let P := 1000000000000000000
            let s_sq := div(add(P, sigma_root), 2)
            prod := div(mul(s_sq, sub(P, s_sq)), P)
        }

        // Step 5: sinθ/2 = √(prod)
        uint256 root_prod = TMaths.sqrt(prod);

        // Step 6: tail = (1 - sinθ)/2, apply sign
        assembly {
            let P := 1000000000000000000
            let cdf_raw := div(sub(P, mul(2, root_prod)), 2)

            switch negative
            case 1 { cdf := cdf_raw }
            default { cdf := sub(P, cdf_raw) }
        }
    }

    /// @notice Simplified closed-form: Φ_D(x) = (1 ± x/√(1+x²)) / 2
    /// @dev Single sqrt call. Algebraically identical to daletCdf.
    ///   sin(arctan(x)) = x/√(1+x²), so tail = (1 - x/√(1+x²))/2
    /// @param negative If true, computes Φ_D(-|x|)
    /// @param x The absolute value of the input, scaled by 1e18
    /// @return cdf The result in [0, 1e18]
    function daletCdfFast(
        bool negative,
        uint256 x
    ) internal pure returns (uint256 cdf) {

        if (x == 0) return 0.5e18;
        if (x >= 340e18) return negative ? 0 : 1e18;

        // sqrt(1 + x²)
        uint256 denom;
        assembly {
            let P := 1000000000000000000
            denom := add(div(mul(x, x), P), P) // x² + 1 (scaled)
        }
        uint256 sqrt_denom = TMaths.sqrt(denom);

        // sin(arctan(x)) = x / √(1+x²), then CDF = (1 ± sinθ) / 2
        assembly {
            let P := 1000000000000000000

            // sin_theta = x * 1e18 / sqrt_denom
            let sin_theta := div(mul(x, P), sqrt_denom)

            // tail = (1 - sin_theta) / 2
            let tail := div(sub(P, sin_theta), 2)

            switch negative
            case 1 { cdf := tail }
            default { cdf := sub(P, tail) }
        }
    }
}
