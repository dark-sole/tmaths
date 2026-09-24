// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

// To deploy on a non-Fusaka chain (e.g. Base, OP Mainnet, Unichain as of May 2026),
// change the import below to: import {TMathLegacy as TMaths} from "./TMathLegacy.sol";
import {TMathFusaka as TMaths} from "./TMathFusaka.sol";
import {NormalCDF} from "./NormalCDF.sol";

/// @title BlackScholes - European option pricing
/// @notice Computes call/put prices and deltas using Black-Scholes model
/// @dev Normalises S=1 internally, all values scaled by 1e18
///
///      Inputs:
///        S     - spot price (e.g. 100e18 = $100)
///        K     - strike price (e.g. 110e18 = $110)
///        T     - time to expiry in years (e.g. 25e16 = 0.25 = 3 months)
///        r     - risk-free rate as decimal (e.g. 5e16 = 5%)
///        y     - dividend/carry yield as decimal (e.g. 2e16 = 2%)
///        sigma - volatility as decimal (e.g. 20e16 = 20%)
///
///      Outputs (all scaled 1e18):
///        call_price  - call option price in underlying terms
///        put_price   - put option price in underlying terms
///        delta_call  - call delta in [0, 1e18]
///        delta_put   - put delta in [0, 1e18] (represents negative value)
library BlackScholes {

    error ZeroSpot();
    error ZeroStrike();
    error ZeroTime();
    error ZeroVol();

    function price(
        uint256 S,
        uint256 K,
        uint256 T,
        uint256 r,
        uint256 y,
        uint256 sigma
    ) internal pure returns (
        uint256 call_price,
        uint256 put_price,
        uint256 delta_call,
        uint256 delta_put
    ) {
        // Input validation
        if (S == 0) revert ZeroSpot();
        if (K == 0) revert ZeroStrike();
        if (T == 0) revert ZeroTime();
        if (sigma == 0) revert ZeroVol();

        // ═══════════════════════════════════════════════════
        // Library calls (Solidity) — results go to local vars
        // ═══════════════════════════════════════════════════
        uint256 K_norm = K * 1e18 / S;
        uint256 sqrtT = TMaths.sqrt(T);
        (bool ln_neg, uint256 ln_val) = TMaths.ln(K_norm);

        // ═══════════════════════════════════════════════════
        // Compute d1, d2 in assembly
        // Inputs: sigma, sqrtT, r, y, ln_neg, ln_val
        // Outputs: d1, d1_neg, d2, d2_neg via memory scratch
        // ═══════════════════════════════════════════════════
        uint256 d1;
        uint256 d1_neg;  // 0 = positive, 1 = negative
        uint256 d2;
        uint256 d2_neg;

        assembly {
            let P := 1000000000000000000

            // sigmaRootT = sigma * sqrtT / 1e18
            let sigmaRootT := div(mul(sigma, sqrtT), P)

            // ln(S/K) = -ln(K_norm): flip sign
            // lnSK_neg = 1 if ln_neg==0, 0 if ln_neg==1
            let lnSK_neg := iszero(ln_neg)

            // sigma_sq_half = sigma * sigma / 2e18
            let sigma_sq_half := div(mul(sigma, sigma), 2000000000000000000)

            // rate = |r - y|, rate_neg = (y > r) ? 1 : 0
            let rate_neg := gt(y, r)
            let rate := sub(r, y)
            if rate_neg { rate := sub(y, r) }

            // drift = rate + sigma_sq_half (signed)
            // If rate_neg: drift = sigma_sq_half - rate (can be negative)
            // Else: drift = rate + sigma_sq_half (always positive)
            let drift_neg := 0
            let drift := add(rate, sigma_sq_half)
            if rate_neg {
                switch gt(sigma_sq_half, rate)
                case 1 {
                    drift := sub(sigma_sq_half, rate)
                    // drift_neg stays 0
                }
                default {
                    drift := sub(rate, sigma_sq_half)
                    drift_neg := 1
                }
            }

            // driftT = drift * T / 1e18
            let driftT := div(mul(drift, T), P)

            // d1_num = lnSK + driftT (signed addition)
            let d1_num := 0

            switch eq(lnSK_neg, drift_neg)
            case 1 {
                // same sign: add magnitudes
                d1_neg := lnSK_neg
                d1_num := add(ln_val, driftT)
            }
            default {
                // different signs: subtract
                switch gt(ln_val, driftT)
                case 1 {
                    d1_neg := lnSK_neg
                    d1_num := sub(ln_val, driftT)
                }
                default {
                    d1_neg := drift_neg
                    d1_num := sub(driftT, ln_val)
                }
            }

            // d1 = d1_num * 1e18 / sigmaRootT
            d1 := div(mul(d1_num, P), sigmaRootT)

            // d2 = d1 - sigmaRootT (signed)
            switch d1_neg
            case 1 {
                // d1 negative: d2 = -(|d1| + sigmaRootT)
                d2_neg := 1
                d2 := add(d1, sigmaRootT)
            }
            default {
                switch gt(d1, sigmaRootT)
                case 1 {
                    d2_neg := 0
                    d2 := sub(d1, sigmaRootT)
                }
                default {
                    d2_neg := 1
                    d2 := sub(sigmaRootT, d1)
                }
            }
        }

        // ═══════════════════════════════════════════════════
        // CDF calls — only 2 needed, derive complements
        // N(-x) = 1 - N(x) exactly (verified in NormalCDF tests)
        // ═══════════════════════════════════════════════════
        uint256 Nd1 = NormalCDF.normalCdf(d1_neg != 0, d1);
        uint256 Nd2 = NormalCDF.normalCdf(d2_neg != 0, d2);

        // Discount factor
        uint256 rateT;
        bool _rateNeg;
        assembly {
            _rateNeg := gt(y, r)
            let rate := sub(r, y)
            if _rateNeg { rate := sub(y, r) }
            rateT := div(mul(rate, T), 1000000000000000000)
        }
        uint256 discount = TMaths.exp(_rateNeg, rateT);

        // ═══════════════════════════════════════════════════
        // Final pricing in assembly
        // Put via put-call parity: P = C - 1 + Kdisc (normalised, S=1)
        // ═══════════════════════════════════════════════════
        assembly {
            let P := 1000000000000000000

            // Kdisc = K_norm * discount / 1e18
            let Kdisc := div(mul(K_norm, discount), P)

            // call_norm = max(0, Nd1 - Kdisc * Nd2 / 1e18)
            let kn2 := div(mul(Kdisc, Nd2), P)
            let call_norm := 0
            if gt(Nd1, kn2) { call_norm := sub(Nd1, kn2) }

            // put_norm = call_norm + Kdisc - 1  (put-call parity, normalised)
            // Kdisc can be > or < 1e18, so handle sign
            let put_norm := 0
            switch gt(Kdisc, P)
            case 1 {
                // Kdisc > 1: put = call + (Kdisc - 1)
                put_norm := add(call_norm, sub(Kdisc, P))
            }
            default {
                // Kdisc <= 1: put = call - (1 - Kdisc)
                let gap := sub(P, Kdisc)
                if gt(call_norm, gap) { put_norm := sub(call_norm, gap) }
            }

            // Scale by S
            call_price := div(mul(call_norm, S), P)
            put_price := div(mul(put_norm, S), P)
            delta_call := Nd1
            delta_put := sub(P, Nd1)
        }
    }
}
