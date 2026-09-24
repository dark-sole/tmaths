// SPDX-License-Identifier: UNLICENSED
// © 2025-2026 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";

/// @title DaletOption - European option pricing with the Dalet distribution
/// @notice Prices options in log space under the Dalet CDF D(x) = (1 + x/sqrt(1+x^2))/2.
/// @dev The standard is PERP/reference/fundingbond/model.py (`dalet_price`) and its vectors.json.
///
///      Log-return y = mu + s X, X Dalet, with
///        m  = ln(S/K)                  log-moneyness
///        mu = (r - sigma^2/2) T        drift
///        s  = sigma sqrt(T)            scale
///        w  = (m + mu)/s               standardised forward moneyness (w = -x*)
///
///      The log-space legs in closed form (dalet_updated.tex eq. (5) integrated out):
///        call_log = e^{-rT} s (sqrt(1+w^2) + w)/2
///        put_log  = e^{-rT} s (sqrt(1+w^2) - w)/2
///      Where the sign of w makes one a difference, it is evaluated as
///        s / (2 (sqrt(1+w^2) + |w|)): no CDF and no subtraction of near-equal terms.
///
///      Ruling 22 (PERP HANDOFF, dalet_updated.tex section 2.3 and section 5): the
///      out-of-the-money leg is priced in log space, S <= K the call and S > K the put, and
///      converted to price as S expm1(leg_log). The other leg follows by price-space parity,
///      C - P = S - K e^{-rT}.
///
///      Maths: Solady FixedPointMathLib v0.1.26 (`lnWad`, `expWad`, `sqrt`), ruling 23. The scale,
///      w and the log legs are carried at 1e27 (RAY) so that the WAD output is not rounded twice.
///
///      Rounding: call and put are amounts a payer is charged, so each is rounded up: the result
///      is never below the exact price (tested against the vectors). The margin covering the
///      approximation error of lnWad and expWad is MARGIN_WEI plus MARGIN_PER_UNIT wei per unit
///      of S + K; see `_margin`.
///
///      Deltas are the probabilities of exercise, as in dalet_updated.tex Table 3:
///        delta_call = 1 - D(x*) = D(w),  delta_put = D(x*) = D(-w),  summing to exactly 1e18,
///      the smaller computed by the stable tail D(-a) = 1/(2 q (q + a)), q = sqrt(1+a^2), a >= 0.
///
///      Inputs (all scaled 1e18):
///        S     - spot price (e.g. 100e18 = $100)
///        K     - strike price (e.g. 110e18 = $110)
///        T     - time to expiry in years (e.g. 25e16 = 0.25 = 3 months)
///        r     - risk-free rate (e.g. 5e16 = 5%)
///        sigma - volatility (e.g. 20e16 = 20%)
///
///      Outputs (all scaled 1e18):
///        call_price  - call option price in quote terms, rounded up
///        put_price   - put option price in quote terms, rounded up
///        delta_call  - call probability of exercise in [0, 1e18]
///        delta_put   - put probability of exercise in [0, 1e18] (represents a negative delta)
///
///      Reverts: ZeroSpot, ZeroStrike, ZeroTime, ZeroVol on a zero input; ZeroScale when
///      s = sigma sqrt(T) is below 1e-18 (it would round to zero at WAD); NegativeParityLeg when
///      the leg derived by parity is below zero (at the money when r is large against sigma).
library DaletOption {

    error ZeroSpot();
    error ZeroStrike();
    error ZeroTime();
    error ZeroVol();
    error ZeroScale();
    error NegativeParityLeg();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    /// @dev expm1 sums its Taylor series below this argument (0.5, RAY) and uses expWad above.
    ///      At 0.5 the series needs 27 terms to reach 1e-27; above it, expm1 >= 0.65 and the
    ///      subtraction of 1 from expWad costs no significant figure.
    uint256 internal constant EXPM1_SERIES_BELOW = 5e26;

    /// @dev |w| above which sqrt(1 + w^2) is taken as |w| (relative error below 1e-22) and
    ///      w^2 at RAY would overflow.
    uint256 internal constant W_LARGE = 1e38;

    /// @dev Rounding margin: covers lnWad (about 1 wei each of ln S and ln K) and expWad
    ///      (about 1e-18 relative) carried through the price conversion and K e^{-rT}: about
    ///      1 wei per unit of S + K each, bounded here by 4. Measured against the vectors the
    ///      error before the margin is below 0.1 wei per unit of S + K (118 wei at S = 2500).
    uint256 internal constant MARGIN_WEI = 4;
    uint256 internal constant MARGIN_PER_UNIT = 4;

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

        // s^2 = sigma^2 T, exact at 1e54; s at RAY.
        uint256 s2 = sigma * sigma * T;
        uint256 s = FPML.sqrt(s2);
        if (s < 1e9) revert ZeroScale();

        // m + mu at RAY: m from lnWad, mu = rT - s^2/2.
        int256 mm = (FPML.lnWad(int256(S)) - FPML.lnWad(int256(K))) * 1e9
            + int256(r * T / 1e9) - int256(s2 / (2 * RAY));

        // |w| and q = sqrt(1 + w^2), RAY.
        uint256 a = FPML.fullMulDiv(uint256(mm < 0 ? -mm : mm), RAY, s);
        uint256 q = _sqrt1p(a);

        // Deltas: the smaller by the stable tail, the other its complement.
        uint256 tail = _tail(q, a);
        (delta_call, delta_put) = mm > 0 ? (WAD - tail, tail) : (tail, WAD - tail);

        // Discount e^{-rT}, WAD.
        uint256 disc = uint256(FPML.expWad(-int256(r * T / WAD)));

        // The out-of-the-money leg, log space, RAY. The call's closed form is a difference
        // when w < 0, the put's when w > 0; those are evaluated as s / (2 (q + |w|)).
        bool callLeg = S <= K;
        bool tailForm = callLeg ? mm < 0 : mm > 0;
        uint256 leg = tailForm
            ? FPML.fullMulDiv(s, RAY, 2 * (q + a))
            : FPML.fullMulDiv(s, q + a, 2 * RAY);
        leg = FPML.fullMulDiv(leg, disc, WAD);

        uint256 margin = _margin(S, K);
        uint256 otm = FPML.fullMulDivUp(S, _expm1Ray(leg), RAY) + margin;

        if (callLeg) {
            // P = C - S + K e^{-rT}: K e^{-rT} rounded up, so the put is too.
            uint256 kd = FPML.fullMulDivUp(K, disc, WAD) + margin;
            if (otm + kd < S) revert NegativeParityLeg();
            call_price = otm;
            put_price = otm + kd - S;
        } else {
            // C = P + S - K e^{-rT}: K e^{-rT} rounded down, so the call is rounded up.
            uint256 kd = FPML.fullMulDiv(K, disc, WAD);
            kd = kd > margin ? kd - margin : 0;
            if (otm + S < kd) revert NegativeParityLeg();
            put_price = otm;
            call_price = otm + S - kd;
        }
    }

    /// @notice The Dalet CDF D(x), x and result WAD, by the stable tail: for x < 0,
    ///         D(x) = 1/(2 q (q - x)), q = sqrt(1 + x^2); D(x) = 1 - D(-x) for x >= 0.
    function daletCdf(int256 x) internal pure returns (uint256) {
        uint256 a = uint256(x < 0 ? -x : x) * 1e9;
        uint256 tail = _tail(_sqrt1p(a), a);
        return x < 0 ? tail : WAD - tail;
    }

    /// @notice e^y - 1 for y >= 0, argument and result at RAY. Below EXPM1_SERIES_BELOW the
    ///         Taylor series is summed until its term vanishes at RAY; above, expWad at WAD
    ///         with a first-order correction for the argument's digits below WAD.
    function expm1Ray(uint256 y) internal pure returns (uint256) {
        return _expm1Ray(y);
    }

    function _expm1Ray(uint256 y) private pure returns (uint256 sum) {
        if (y == 0) return 0;
        if (y < EXPM1_SERIES_BELOW) {
            uint256 term = y;
            sum = y;
            for (uint256 n = 2; ; ++n) {
                term = term * y / (RAY * n);
                if (term == 0) break;
                sum += term;
            }
            return sum;
        }
        uint256 e = uint256(FPML.expWad(int256(y / 1e9)));
        return e * 1e9 + e * (y % 1e9) / WAD - RAY;
    }

    /// @dev sqrt(1 + a^2), a at RAY.
    function _sqrt1p(uint256 a) private pure returns (uint256) {
        if (a >= W_LARGE) return a;
        return FPML.sqrt(RAY * RAY + a * a);
    }

    /// @dev D(-a) = 1/(2 q (q + a)), q and a at RAY, result WAD.
    function _tail(uint256 q, uint256 a) private pure returns (uint256) {
        uint256 t = FPML.fullMulDiv(q, q + a, RAY);
        return FPML.fullMulDiv(WAD, RAY, 2 * t);
    }

    /// @dev The rounding margin in wei for prices on S and K (WAD).
    function _margin(uint256 S, uint256 K) private pure returns (uint256) {
        return MARGIN_WEI + FPML.mulDivUp(S + K, MARGIN_PER_UNIT, WAD);
    }
}
