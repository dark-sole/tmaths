// SPDX-License-Identifier: UNLICENSED
// © 2026 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";
import {DaletOption} from "./DaletOption.sol";

/// @title FundingBond - the funding bond's charges for EVM venues
/// @notice Knock-in, the spreads on the available capital, the premium, the Itô transfer and the
///         basis, on DaletOption (ruling 22'').
/// @dev The standard is PERP/reference/fundingbond/model.py and its vectors.json; the authority
///      is PERP/paper/FundingBond.tex with the Frozen rulings 18 to 30 in PERP HANDOFF.md.
///
///      WAD (1e18) throughout. Every output lies on the side of the exact value that its
///      vector's direction names (tested against the vectors):
///        up    knock-in, gap claim, premium, the floor, every amount a payer is charged
///        down  the cap, every amount received
///        none  rates (the basis in logs, its ratio, f)
///
///      Knock-in (ruling 18): the bound min(1, 2 D(-y)), y = d/sqrt(dV), in the stable form
///      1/(q (q + y)), q = sqrt(1 + y^2). Rounded up: d is taken down past lnWad's error, sqrt(dV)
///      up, q and q (q + y) down, and the quotient up.
///
///      Gap claim (rulings 19 and 29): the leg at the Strike by `DaletOption.price` (up) less the
///      leg at the floor or cap by `DaletOption.priceLower` (at or below exact), so the claim is
///      up by construction. A Strike at or beyond the floor or cap has no cover: the claim is 0.
///
///      Cap and floor (ruling 19): the caller supplies one entry per Strike with its aggregate
///      delivered size, Strikes strictly ascending, and bounds the length. There is no loop over
///      positions here (PreDiX 15.30).
///
///      Itô transfer (rulings 20 and 30) and basis (rulings 24, 26, 27 and 28): each amount paid
///      is rounded up and each amount received down; the dust is the venue's (for PERP, the
///      underwriters' vault's). The basis is computed per position; the venue keeps the book.
library FundingBond {

    error KnockedIn();
    error ZeroSpot();
    error ZeroDistance();
    error ZeroCap();
    error EmptyBook();
    error LengthMismatch();
    error NotAscending();
    error ZeroSize();
    error ZeroStrike();
    error ZeroCapital();
    error ZeroAverage();
    error ZeroInterval();
    error ZeroReceivers();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    /// @dev lnWad's error, in wei, allowed for when a log distance is taken down.
    uint256 internal constant LN_ERR = 2;

    /// @dev The error of a basis rate f, in wei, carried up into every amount paid: the log
    ///      (two lnWad), the ratio's expm1, and the truncation of the division by sqrt(2).
    uint256 internal constant BASIS_RATE_ERR = 4;

    /// @dev ln(1.0001) at 1e36, rounded down.
    uint256 internal constant LN_TICK_E36 = 99995000333308335333166680951131;

    /// @dev 1/sqrt(2) at RAY, rounded down.
    uint256 internal constant INV_SQRT2_RAY = 707106781186547524400844362;

    // -----------------------------------------------------------------------------------------
    // Knock-in (ruling 18)
    // -----------------------------------------------------------------------------------------

    /// @notice The knock-in bound at log distance d > 0 from the Strike while variance dV
    ///         accrues, rounded up; 0 when dV = 0. A venue on ticks passes
    ///         d = (tick distance) x ln(1.0001). Reverts ZeroDistance when d = 0 (knocked in).
    function knockInLog(uint256 d, uint256 dV) internal pure returns (uint256) {
        if (d == 0) revert ZeroDistance();
        if (dV == 0) return 0;
        return _knockIn(d, dV);
    }

    /// @notice A long recorded at S0 with Strike K: knockInLog at d = ln(S0/K), rounded up.
    ///         Reverts KnockedIn when S0 <= K.
    function knockInLong(uint256 S0, uint256 K, uint256 dV) internal pure returns (uint256) {
        if (K == 0) revert ZeroStrike();
        if (S0 <= K) revert KnockedIn();
        if (dV == 0) return 0;
        return _knockInRatio(FPML.fullMulDiv(S0, WAD, K), dV);
    }

    /// @notice A short recorded at S0 with Strike K_S, by reflection: d = ln(K_S/S0), rounded
    ///         up. Reverts KnockedIn when S0 >= K_S.
    function knockInShort(uint256 S0, uint256 K_S, uint256 dV) internal pure returns (uint256) {
        if (S0 == 0) revert ZeroSpot();
        if (S0 >= K_S) revert KnockedIn();
        if (dV == 0) return 0;
        return _knockInRatio(FPML.fullMulDiv(K_S, WAD, S0), dV);
    }

    /// @dev The ratio (rounded down) to d, taken down past lnWad's error; a distance lost to
    ///      that error prices at the bound's ceiling, 1.
    function _knockInRatio(uint256 ratio, uint256 dV) private pure returns (uint256) {
        int256 l = FPML.lnWad(int256(ratio)) - int256(LN_ERR);
        if (l <= 0) return WAD;
        return _knockIn(uint256(l), dV);
    }

    /// @dev 1/(q (q + y)), y = d/sqrt(dV), rounded up; d and dV WAD, both positive.
    function _knockIn(uint256 d, uint256 dV) private pure returns (uint256) {
        // sqrt(dV) at RAY, rounded up, so that y is down.
        uint256 x = dV * 1e36;
        uint256 sq = FPML.sqrt(x);
        if (sq * sq < x) ++sq;
        uint256 y = FPML.fullMulDiv(d * 1e9, RAY, sq);
        // q = sqrt(1 + y^2), down; q (q + y), down; the quotient up.
        uint256 q = y >= 1e38 ? y : FPML.sqrt(RAY * RAY + y * y);
        uint256 t = FPML.fullMulDiv(q, q + y, RAY);
        uint256 k = FPML.fullMulDivUp(WAD, RAY, t);
        return k > WAD ? WAD : k;
    }

    // -----------------------------------------------------------------------------------------
    // Spreads on the available capital (rulings 19 and 29)
    // -----------------------------------------------------------------------------------------

    /// @notice A long's gap claim per unit of delivered size: the put at the Strike K less the
    ///         put at the floor, each from the Strike over h at r = 0, rounded up. Floor 0 prices
    ///         the Strike leg alone; a floor at or above K has no cover and the claim is 0.
    function gapClaimLong(uint256 K, uint256 floor_, uint256 sigma, uint256 h)
        internal pure returns (uint256)
    {
        if (floor_ >= K) return 0;
        (, uint256 leg,,) = DaletOption.price(K, K, h, 0, sigma);
        if (floor_ == 0) return leg;
        (, uint256 lower) = DaletOption.priceLower(K, floor_, h, 0, sigma);
        return leg > lower ? leg - lower : 0;
    }

    /// @notice A short's gap claim: the call at the Strike K_S less the call at the cap, rounded
    ///         up. A cap at or below K_S has no cover and the claim is 0; reverts ZeroCap on a
    ///         cap of 0.
    function gapClaimShort(uint256 K_S, uint256 cap_, uint256 sigma, uint256 h)
        internal pure returns (uint256)
    {
        if (cap_ == 0) revert ZeroCap();
        if (cap_ <= K_S) return 0;
        (uint256 leg,,,) = DaletOption.price(K_S, K_S, h, 0, sigma);
        (uint256 lower,) = DaletOption.priceLower(K_S, cap_, h, 0, sigma);
        return leg > lower ? leg - lower : 0;
    }

    /// @notice The premium for one interval: size x knock-in x gap claim, rounded up once.
    function premium(uint256 size, uint256 knockIn, uint256 gapClaim)
        internal pure returns (uint256)
    {
        return FPML.fullMulDivUp(size, knockIn * gapClaim, 1e36);
    }

    /// @notice The cap S*: the price at which the liability of knocked-in shorts,
    ///         sum over K_j < S of q_j (S - K_j), reaches the capital U. Rounded down.
    function capOf(uint256[] memory strikes, uint256[] memory sizes, uint256 U)
        internal pure returns (uint256)
    {
        _checkBook(strikes, sizes, U);
        uint256 n = strikes.length;
        uint256 u = U * WAD;
        uint256 Q;
        uint256 QK;
        for (uint256 i; i < n; ++i) {
            Q += sizes[i];
            QK += sizes[i] * strikes[i];
            if (i + 1 == n || u + QK <= strikes[i + 1] * Q) return (u + QK) / Q;
        }
        return 0; // unreachable
    }

    /// @notice The floor S_*: the price at which the liability of knocked-in longs,
    ///         sum over K_j > S of q_j (K_j - S), reaches U; 0 when U covers the whole book.
    ///         Rounded up (towards the Strike).
    function floorOf(uint256[] memory strikes, uint256[] memory sizes, uint256 U)
        internal pure returns (uint256)
    {
        _checkBook(strikes, sizes, U);
        uint256 u = U * WAD;
        uint256 Q;
        uint256 QK;
        for (uint256 i = strikes.length; i > 0; --i) {
            Q += sizes[i - 1];
            QK += sizes[i - 1] * strikes[i - 1];
            // Zero only once every Strike is counted: U can cover the top Strikes alone.
            if (i == 1) return QK <= u ? 0 : FPML.divUp(QK - u, Q);
            if (QK > u && QK - u >= strikes[i - 2] * Q) return FPML.divUp(QK - u, Q);
        }
        return 0; // unreachable
    }

    function _checkBook(uint256[] memory strikes, uint256[] memory sizes, uint256 U) private pure {
        uint256 n = strikes.length;
        if (n == 0) revert EmptyBook();
        if (sizes.length != n) revert LengthMismatch();
        if (U == 0) revert ZeroCapital();
        for (uint256 i; i < n; ++i) {
            if (strikes[i] == 0) revert ZeroStrike();
            if (sizes[i] == 0) revert ZeroSize();
            if (i > 0 && strikes[i] <= strikes[i - 1]) revert NotAscending();
        }
    }

    // -----------------------------------------------------------------------------------------
    // The Itô transfer (rulings 20 and 30)
    // -----------------------------------------------------------------------------------------

    /// @notice What a long pays for one period: 1/2 dV x q x A_index, rounded up.
    function itoPaid(uint256 q, uint256 A_index, uint256 dV) internal pure returns (uint256) {
        return FPML.fullMulDivUp(q * A_index, dV, 2e36);
    }

    /// @notice What a short receives for one period: 1/2 dV x q x A_index, rounded down.
    function itoReceived(uint256 q, uint256 A_index, uint256 dV) internal pure returns (uint256) {
        return FPML.fullMulDiv(q * A_index, dV, 2e36);
    }

    // -----------------------------------------------------------------------------------------
    // The basis (rulings 21, 24, 26, 27 and 28), per position
    // -----------------------------------------------------------------------------------------

    /// @notice r_log = ln(A_perp/A_index), signed WAD.
    function basisLog(uint256 A_perp, uint256 A_index) internal pure returns (int256) {
        if (A_perp == 0 || A_index == 0) revert ZeroAverage();
        return FPML.lnWad(int256(A_perp)) - FPML.lnWad(int256(A_index));
    }

    /// @notice r_log from PERP's tick running totals: (dS_perp - dS_pool)/dt x ln(1.0001),
    ///         dTickTime = dS_perp - dS_pool (tick x seconds, an integer), dt in seconds.
    function basisLogTicks(int256 dTickTime, uint256 dt) internal pure returns (int256) {
        if (dt == 0) revert ZeroInterval();
        uint256 m = FPML.fullMulDiv(FPML.abs(dTickTime), LN_TICK_E36, dt * WAD);
        return dTickTime < 0 ? -int256(m) : int256(m);
    }

    /// @notice The conversion r = e^{r_log} - 1, signed WAD.
    function toRatio(int256 rLog) internal pure returns (int256) {
        if (rLog >= 0) return int256(DaletOption.expm1Ray(uint256(rLog) * 1e9) / 1e9);
        return -int256(DaletOption.oneMinusExpNegRay(uint256(-rLog) * 1e9) / 1e9);
    }

    /// @notice f: the chosen form over sqrt(2), signed WAD; ratio true converts r_log first.
    function basisRate(int256 rLog, bool ratio) internal pure returns (int256) {
        int256 x = ratio ? toRatio(rLog) : rLog;
        uint256 m = FPML.fullMulDiv(FPML.abs(x), INV_SQRT2_RAY, RAY);
        return x < 0 ? -int256(m) : int256(m);
    }

    /// @notice What one payer pays: |f| x q x A_index, rounded up, with the rate's own error.
    function basisPay(int256 f, uint256 q, uint256 A_index) internal pure returns (uint256) {
        if (f == 0) return 0;
        return FPML.fullMulDivUp(FPML.abs(f) + BASIS_RATE_ERR, q * A_index, 1e36);
    }

    /// @notice What one receiver receives: total x q / qReceivers, rounded down. The sum paid
    ///         less the sum received is the dust (rulings 27 and 28), never negative.
    function basisReceive(uint256 total, uint256 q, uint256 qReceivers)
        internal pure returns (uint256)
    {
        if (qReceivers == 0) revert ZeroReceivers();
        return FPML.fullMulDiv(total, q, qReceivers);
    }
}
