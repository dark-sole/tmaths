// SPDX-License-Identifier: UNLICENSED
// © 2025-2026 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";

/// @title DaletOption - European option pricing with the Dalet distribution
/// @notice Prices options in log space under the Dalet CDF D(x) = (1 + x/sqrt(1+x^2))/2.
/// @dev The standard is PERP/reference/fundingbond/model.py (`dalet_price`) and its vectors.json.
///
///      Ruling 22'' (PERP HANDOFF): the log law is centred on the forward F = S e^{rT}, with no
///      drift term, and each leg is priced under its own numeraire. With
///        s  = sigma sqrt(T)            scale
///        w  = ln(F/K)/s                standardised forward moneyness
///        q  = sqrt(1 + w^2)
///      the log legs are
///        C_log = s (q + w)/2,  P_log = s (q - w)/2   (C_log - P_log = ln(F/K))
///      whichever of q + w, q - w is a difference evaluated as 1/(q + |w|), and the prices
///        C = S (1 - e^{-C_log})             the call in the asset, bounded by S
///        P = K e^{-rT} (1 - e^{-P_log})     the put in cash, bounded by K e^{-rT}
///      One formula on both sides of the money: no leg selection and no parity step. Price
///      parity C - P = S - K e^{-rT} is an identity of the exact prices (F e^{-C_log} =
///      K e^{-P_log}); the prices returned depart from it by their rounding only.
///
///      Maths: Solady FixedPointMathLib v0.1.26 (`lnWad`, `expWad`, `sqrt`), ruling 23. The scale,
///      w and the log legs are carried at 1e27 (RAY) so that the WAD output is not rounded twice.
///
///      Rounding: call and put are amounts a payer is charged, so each is rounded up: the result
///      is never below the exact price (tested against the vectors). The margin covering the
///      approximation error of lnWad and expWad is MARGIN_WEI plus MARGIN_PER_UNIT wei per unit
///      of S + K; see `_margin`. Each price carries one margin, so C - P departs from
///      S - K e^{-rT} by at most the two margins. `priceLower` is the same core less the margin,
///      floored at zero: at or below the exact prices, for a leg that is subtracted.
///
///      Deltas are the derivatives of the prices in S (ruling 22''):
///        delta_call = dC/dS = 1 - e^{-C_log} (1 - D(w)),  delta_put = -dP/dS = 1 - delta_call,
///      returned as magnitudes summing to exactly 1e18; 1 - D(w) by the stable tail
///      D(-a) = 1/(2 q (q + a)), q = sqrt(1+a^2), a >= 0.
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
///        delta_call  - dC/dS in [0, 1e18]
///        delta_put   - -dP/dS in [0, 1e18] (the magnitude of a negative delta)
///
///      Reverts: ZeroSpot, ZeroStrike, ZeroTime, ZeroVol on a zero input; ZeroScale when
///      s = sigma sqrt(T) is below 1e-18 (it would round to zero at WAD).
library DaletOption {

    error ZeroSpot();
    error ZeroStrike();
    error ZeroTime();
    error ZeroVol();
    error ZeroScale();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    /// @dev expm1 and 1 - e^{-y} sum their Taylor series below this argument (0.5, RAY) and use
    ///      expWad above. At 0.5 the series needs 27 terms to reach 1e-27; above it, the result
    ///      is at least 0.39 and the subtraction from 1 costs no significant figure.
    uint256 internal constant EXPM1_SERIES_BELOW = 5e26;

    /// @dev |w| above which sqrt(1 + w^2) is taken as |w| (relative error below 1e-22) and
    ///      w^2 at RAY would overflow.
    uint256 internal constant W_LARGE = 1e38;

    /// @dev Rounding margin: covers lnWad (about 1 wei each of ln S and ln K), whose error moves
    ///      a leg by at most the same in log (dC_log/d ln F = D(w) <= 1), and expWad (about 1e-18
    ///      relative) in e^{-rT} and 1 - e^{-leg}: about 1 wei per unit of S + K each, bounded
    ///      here by 4. See the vector test for the error measured before the margin.
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
        uint256 c;
        uint256 p;
        (c, p, delta_call, delta_put) = _core(S, K, T, r, sigma);
        uint256 margin = _margin(S, K);
        call_price = c + margin;
        put_price = p + margin;
    }

    /// @notice The lower-bound pricer beside `price`: its call and put are at or below the exact
    ///         prices, for the leg of a spread that is subtracted (a difference of two prices
    ///         rounded up is not rounded up). The core's result less its margin, floored at zero;
    ///         `price` less the lower bound is at most two margins. Inputs and reverts as `price`.
    function priceLower(
        uint256 S,
        uint256 K,
        uint256 T,
        uint256 r,
        uint256 sigma
    ) internal pure returns (uint256 call_lower, uint256 put_lower) {
        (uint256 c, uint256 p,,) = _core(S, K, T, r, sigma);
        uint256 margin = _margin(S, K);
        call_lower = c > margin ? c - margin : 0;
        put_lower = p > margin ? p - margin : 0;
    }

    /// @dev The prices before the margin (each carried up through its steps) and the deltas.
    function _core(
        uint256 S,
        uint256 K,
        uint256 T,
        uint256 r,
        uint256 sigma
    ) private pure returns (uint256 c, uint256 p, uint256 delta_call, uint256 delta_put) {
        if (S == 0) revert ZeroSpot();
        if (K == 0) revert ZeroStrike();
        if (T == 0) revert ZeroTime();
        if (sigma == 0) revert ZeroVol();

        // s^2 = sigma^2 T, exact at 1e54; s at RAY.
        uint256 s = FPML.sqrt(sigma * sigma * T);
        if (s < 1e9) revert ZeroScale();

        // ln(F/K) = ln S - ln K + rT at RAY: ln from lnWad, rT exact at 1e36.
        int256 lfk = (FPML.lnWad(int256(S)) - FPML.lnWad(int256(K))) * 1e9 + int256(r * T / 1e9);

        // |w| and q = sqrt(1 + w^2), RAY.
        uint256 a = FPML.fullMulDiv(uint256(lfk < 0 ? -lfk : lfk), RAY, s);
        uint256 q = _sqrt1p(a);

        // The log legs, RAY: the larger s (q + |w|)/2, the smaller s / (2 (q + |w|)).
        uint256 big = FPML.fullMulDiv(s, q + a, 2 * RAY);
        uint256 small = FPML.fullMulDiv(s, RAY, 2 * (q + a));
        (uint256 cLog, uint256 pLog) = lfk >= 0 ? (big, small) : (small, big);

        // 1 - e^{-leg}, RAY, each rounded up so that the prices are.
        uint256 omC = _oneMinusExpNegRay(cLog);
        uint256 omP = _oneMinusExpNegRay(pLog);

        // Discount e^{-rT}, WAD, rounded up by one wei for the put.
        uint256 disc = uint256(FPML.expWad(-int256(r * T / WAD))) + 1;

        c = FPML.fullMulDivUp(S, omC, RAY);
        p = FPML.fullMulDivUp(FPML.fullMulDivUp(K, disc, WAD), omP, RAY);

        // Deltas: 1 - D(w) by the stable tail when w >= 0, else D(|w|) = 1 - tail.
        uint256 tail = _tail(q, a);
        uint256 survival = lfk >= 0 ? tail : WAD - tail;
        delta_put = FPML.fullMulDiv(RAY - omC, survival, RAY);
        delta_call = WAD - delta_put;
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

    /// @notice 1 - e^{-y} = -expm1(-y) for y >= 0, argument and result at RAY, rounded up.
    function oneMinusExpNegRay(uint256 y) internal pure returns (uint256) {
        return _oneMinusExpNegRay(y);
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

    /// @dev Below the threshold, the alternating series y - y^2/2 + y^3/6 - ..., its positive
    ///      and negative terms summed apart; each term is truncated, so one wei per term is
    ///      added back to round up. Above, e^{-y} from expWad at WAD with a first-order
    ///      correction for the argument's digits below WAD, rounded down, so 1 - e^{-y} is up.
    function _oneMinusExpNegRay(uint256 y) private pure returns (uint256) {
        if (y == 0) return 0;
        if (y < EXPM1_SERIES_BELOW) {
            uint256 term = y;
            uint256 pos = y;
            uint256 neg;
            uint256 n = 2;
            for (; ; ++n) {
                term = term * y / (RAY * n);
                if (term == 0) break;
                if (n % 2 == 0) neg += term; else pos += term;
            }
            return pos - neg + n;
        }
        int256 x = -int256(y / 1e9);
        if (x <= -41446531673892822313) return RAY; // expWad returns 0 below this: e^{-y} < 1e-18
        uint256 e = uint256(FPML.expWad(x)) * 1e9;  // e^{-floor_WAD(y)}, RAY
        uint256 corr = FPML.fullMulDivUp(e, y % 1e9, RAY); // first order in the sub-WAD digits
        corr += 1e9;                                 // expWad's last wei, carried down
        return RAY - (e > corr ? e - corr : 0);      // e^{-y} bounded below by 0
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
