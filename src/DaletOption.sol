// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {TMaths} from "./TMaths.sol";

/// @title DaletOption - European option pricing with Dalet distribution
/// @notice Prices options in log-space using the Dalet CDF: Φ_D(x) = (1 + x/√(1+x²))/2
/// @dev All computation stays in log-space where integrals are elementary trigonometric.
///      The Dalet distribution (Student-t, ν=2) has heavier tails than Normal,
///      giving higher prices for deep OTM options.
///
///      Log-space call formula:
///        C_log = e^{-rT} · [ s·cos(θ*)/2  +  (m + μ) · (1 - Φ_D(x*)) ]
///
///      where:
///        m  = ln(S/K)                  — log-moneyness
///        μ  = (r - σ²/2)·T            — risk-neutral drift
///        s  = σ·√T                     — volatility-scaled time
///        x* = -(m + μ)/s              — standardised exercise threshold
///        θ* = arctan(x*)              — angular threshold
///        cos(θ*)/2 = 1/(2√(1+x*²))   — density integral ∫_{x*}^∞ x·φ_D(x)dx
///        Φ_D = (1+x/√(1+x²))/2       — Dalet CDF
///
///      Price conversion: C = S · (exp(C_log/S) - 1)
///      Put via log-space parity: P_log = C_log - (m + μ) · e^{-rT}
///
///      Inputs (all scaled 1e18):
///        S     - spot price (e.g. 100e18 = $100)
///        K     - strike price (e.g. 110e18 = $110)
///        T     - time to expiry in years (e.g. 25e16 = 0.25 = 3 months)
///        r     - risk-free rate (e.g. 5e16 = 5%)
///        sigma - volatility (e.g. 20e16 = 20%)
///
///      Outputs (all scaled 1e18):
///        call_price  - call option price in underlying terms
///        put_price   - put option price in underlying terms
///        delta_call  - call delta in [0, 1e18]
///        delta_put   - put delta in [0, 1e18] (represents negative value)
library DaletOption {

    error ZeroSpot();
    error ZeroStrike();
    error ZeroTime();
    error ZeroVol();

    function price(
        uint256 S,
        uint256 K,
        uint256 T,
        uint256 r,
        uint256 sigma
    ) internal pure returns (
        uint256 call_price,
        uint256 put_price,
        uint256 delta_call,
        uint256 delta_put
    ) {
        if (S == 0) revert ZeroSpot();
        if (K == 0) revert ZeroStrike();
        if (T == 0) revert ZeroTime();
        if (sigma == 0) revert ZeroVol();

        // ═══════════════════════════════════════════════════
        // Library calls (Solidity) — cannot be inlined into assembly
        // ═══════════════════════════════════════════════════

        // K_norm = K/S (normalise to S=1)
        uint256 K_norm = K * 1e18 / S;

        // √T
        uint256 sqrtT = TMaths.sqrt(T);

        // ln(K/S) — we need ln(S/K) = -ln(K/S)
        (bool ln_neg, uint256 ln_val) = TMaths.ln(K_norm);

        // ═══════════════════════════════════════════════════
        // Compute x* (standardised threshold) in assembly
        //   m = ln(S/K) = -ln(K/S)
        //   μ = (r - σ²/2)·T
        //   s = σ·√T
        //   x* = -(m + μ)/s
        // ═══════════════════════════════════════════════════
        uint256 x_star;
        uint256 x_star_neg;    // 0 = positive, 1 = negative
        uint256 s_vol;         // σ√T
        uint256 m_plus_mu;     // |m + μ|
        uint256 m_plus_mu_neg; // sign of (m + μ)

        assembly {
            let P := 1000000000000000000

            // s = σ·√T
            s_vol := div(mul(sigma, sqrtT), P)

            // ln(S/K): flip sign of ln(K/S)
            // lnSK_neg = !ln_neg
            let lnSK_neg := iszero(ln_neg)
            let lnSK_val := ln_val

            // μ = (r - σ²/2)·T
            let sigma_sq_half := div(mul(sigma, sigma), 2000000000000000000)
            let mu_neg := gt(sigma_sq_half, r)
            let mu_val := 0
            switch mu_neg
            case 1 { mu_val := div(mul(sub(sigma_sq_half, r), T), P) }
            default { mu_val := div(mul(sub(r, sigma_sq_half), T), P) }

            // m + μ = lnSK + mu (signed addition)
            switch eq(lnSK_neg, mu_neg)
            case 1 {
                // same sign: add magnitudes
                m_plus_mu_neg := lnSK_neg
                m_plus_mu := add(lnSK_val, mu_val)
            }
            default {
                // different signs: subtract
                switch gt(lnSK_val, mu_val)
                case 1 {
                    m_plus_mu_neg := lnSK_neg
                    m_plus_mu := sub(lnSK_val, mu_val)
                }
                default {
                    m_plus_mu_neg := mu_neg
                    m_plus_mu := sub(mu_val, lnSK_val)
                }
            }

            // x* = -(m + μ)/s — flip sign
            x_star := div(mul(m_plus_mu, P), s_vol)
            x_star_neg := iszero(m_plus_mu_neg) // flip: -(positive) = negative
            if iszero(m_plus_mu) { x_star_neg := 0 }
        }

        // ═══════════════════════════════════════════════════
        // Dalet CDF and density integral from single sqrt
        //   √(1 + x*²)   — one sqrt call
        //   Φ_D(x*) = (1 + x*/√(1+x*²)) / 2      — CDF
        //   survival = 1 - Φ_D(x*)                  — tail probability
        //   cos(θ*)/2 = 1/(2·√(1+x*²))             — density integral
        //
        //   The integral ∫_{x*}^{∞} x·φ_D(x)dx = cos(θ*)/2
        //   NOT φ_D(x*). The PDF is cos³θ/2 but the
        //   integral of x·φ(x) = ∫ sinθ dθ = cosθ.
        // ═══════════════════════════════════════════════════
        uint256 denom;
        assembly {
            let P := 1000000000000000000
            denom := add(div(mul(x_star, x_star), P), P) // 1 + x*²
        }
        uint256 sqrt_denom = TMaths.sqrt(denom); // √(1 + x*²)

        uint256 survival;        // 1 - Φ_D(x*)
        uint256 cos_theta_half;  // cos(θ*)/2 = 1/(2√(1+x*²))

        assembly {
            let P := 1000000000000000000

            // sin_theta = x* / √(1+x*²)
            let sin_theta := div(mul(x_star, P), sqrt_denom)

            // CDF = (1 ± sinθ)/2 depending on sign
            // survival = 1 - CDF
            switch x_star_neg
            case 1 {
                // x* negative: CDF = (1 - sinθ)/2, survival = (1 + sinθ)/2
                survival := div(add(P, sin_theta), 2)
            }
            default {
                // x* positive or zero: CDF = (1 + sinθ)/2, survival = (1 - sinθ)/2
                survival := div(sub(P, sin_theta), 2)
            }

            // cos(θ*)/2 = 1/(2·√(1+x*²))
            // sqrt_denom is 1e18-scaled, so:
            //   1/(2·sqrt_denom_real) = 1e18/(2·sqrt_denom/1e18) = 1e36/(2·sqrt_denom)
            cos_theta_half := div(mul(P, P), mul(2, sqrt_denom))
        }

        // ═══════════════════════════════════════════════════
        // Discount factor: e^{-rT}
        // ═══════════════════════════════════════════════════
        uint256 rT;
        assembly {
            rT := div(mul(r, T), 1000000000000000000)
        }
        uint256 discount = TMaths.exp(false, rT); // e^{-rT}

        // ═══════════════════════════════════════════════════
        // Log-space call:
        //   C_log = e^{-rT} · [ s·cos(θ*)/2  +  (m+μ) · survival ]
        //
        //   where s·cos(θ*)/2 = s/(2√(1+x*²)) is the density integral
        //   and (m+μ)·survival is the intrinsic contribution.
        //
        // Log-space put via parity:
        //   P_log = C_log - (m+μ) · e^{-rT}
        //
        // Price conversion:
        //   C_price = S · (exp(C_log_norm) - 1)
        //   where C_log_norm = C_log (normalised, S=1)
        // ═══════════════════════════════════════════════════

        // exp for final conversion — compute after assembling C_log
        uint256 call_log_norm;
        uint256 put_log_norm;

        assembly {
            let P := 1000000000000000000

            // density_term = s · cos(θ*)/2 = s/(2√(1+x*²))
            let density_term := div(mul(s_vol, cos_theta_half), P)

            // intrinsic_term = |m+μ| · survival
            let intrinsic_term := div(mul(m_plus_mu, survival), P)

            // C_log_raw = density_term + intrinsic_term  (if m+μ > 0)
            // C_log_raw = density_term - intrinsic_term  (if m+μ < 0)
            // Note: density_term is always positive
            // When m+μ < 0 (OTM call), intrinsic_term contribution is negative
            let c_log_raw := 0
            switch m_plus_mu_neg
            case 1 {
                // m+μ < 0 (OTM): C_log = density - |intrinsic|
                // density_term is always >= intrinsic when m+μ is negative
                // because the PDF contribution dominates near the threshold
                switch gt(density_term, intrinsic_term)
                case 1 { c_log_raw := sub(density_term, intrinsic_term) }
                default { c_log_raw := 0 }
            }
            default {
                // m+μ >= 0 (ITM or ATM): both terms positive
                c_log_raw := add(density_term, intrinsic_term)
            }

            // Apply discount: C_log = c_log_raw · discount / 1e18
            call_log_norm := div(mul(c_log_raw, discount), P)

            // Put via parity: P_log = C_log - (m+μ)·e^{-rT}
            // forward = (m+μ) · discount
            let forward_disc := div(mul(m_plus_mu, discount), P)

            switch m_plus_mu_neg
            case 1 {
                // m+μ < 0: put = call + |forward|
                put_log_norm := add(call_log_norm, forward_disc)
            }
            default {
                // m+μ >= 0: put = call - forward (could be zero)
                switch gt(call_log_norm, forward_disc)
                case 1 { put_log_norm := sub(call_log_norm, forward_disc) }
                default { put_log_norm := 0 }
            }

            // Deltas (log-space): probability of exercise
            delta_call := survival
            delta_put := sub(P, survival)
        }

        // ═══════════════════════════════════════════════════
        // Convert from log-space to price-space
        //   C_price = S · (exp(C_log_norm) - 1)
        //   For small values, exp(x)-1 ≈ x, so price ≈ S · C_log_norm
        // ═══════════════════════════════════════════════════
        if (call_log_norm > 0) {
            uint256 exp_call = TMaths.exp(true, call_log_norm);
            assembly {
                let P := 1000000000000000000
                // exp_call - 1 (both are 1e18-scaled, so subtract 1e18)
                let call_norm := sub(exp_call, P)
                call_price := div(mul(call_norm, S), P)
            }
        }

        if (put_log_norm > 0) {
            uint256 exp_put = TMaths.exp(true, put_log_norm);
            assembly {
                let P := 1000000000000000000
                let put_norm := sub(exp_put, P)
                put_price := div(mul(put_norm, S), P)
            }
        }
    }
}
