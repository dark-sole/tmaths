// SPDX-License-Identifier: UNLICENSED
// © 2025-2026 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";
import {DaletOption} from "../src/DaletOption.sol";

/// @notice Stage 0 of PERP brief 2026-09-24c (rewritten), fuzzed on DaletOption: ruling 22'' is
///         free of static arbitrage across strikes. For strikes K1 < K2 < K3 (K2 the midpoint):
///         butterflies >= 0; C falls and P rises with K; 0 <= -dC/dK <= e^{-rT}; the lower bounds
///         C >= max(S - K e^{-rT}, 0), P >= max(K e^{-rT} - S, 0); the upper bounds C <= S,
///         P <= K e^{-rT}; P/K rises with K; the deltas in range and summing to one; parity.
///
///         Each price is rounded up by at most U = 2 margins (`_u`: the margin, and the upward
///         carries measured in the vector test at under 3 wei per unit of S + K). The checks
///         compare rounded prices, so each allows the rounding of the prices it combines, and
///         nothing more: no check is relaxed beyond the rounding.
contract DaletOptionArbitrageTest is Test {

    uint256 internal constant WAD = 1e18;

    /// @dev The eight stage 0 cases, (sigma sqrt(T), r) read with T = 1 year.
    function _case(uint256 i) internal pure returns (uint256 sigma, uint256 r) {
        uint256[8] memory s = [uint256(0.04e18), 0.8e18, 1.5e18, 3.0e18, 0.8e18, 0.3e18, 2.24e18, 0.1e18];
        uint256[8] memory rr = [uint256(0), 0, 0, 0, 0.05e18, 0.2e18, 0.1e18, 0.05e18];
        return (s[i], rr[i]);
    }

    /// @dev The rounding bound of one price on S and K: two margins.
    function _u(uint256 S, uint256 K) internal pure returns (uint256) {
        return 2 * (DaletOption.MARGIN_WEI + FPML.mulDivUp(S + K, DaletOption.MARGIN_PER_UNIT, WAD));
    }

    struct Leg {
        uint256 c;
        uint256 p;
        uint256 dc;
        uint256 dp;
    }

    function _price(uint256 S, uint256 K, uint256 T, uint256 r, uint256 sigma)
        internal pure returns (Leg memory l)
    {
        (l.c, l.p, l.dc, l.dp) = DaletOption.price(S, K, T, r, sigma);
    }

    function _check(uint256 S, uint256 K1, uint256 h, uint256 T, uint256 r, uint256 sigma) internal pure {
        uint256 K2 = K1 + h;
        uint256 K3 = K2 + h;
        Leg memory a = _price(S, K1, T, r, sigma);
        Leg memory b = _price(S, K2, T, r, sigma);
        Leg memory c = _price(S, K3, T, r, sigma);
        uint256 u = _u(S, K3);
        // e^{-rT}, bracketed by one wei either side of expWad
        uint256 d = uint256(FPML.expWad(-int256(r * T / WAD)));
        uint256 dHi = d + 1;
        uint256 dLo = d - 1;

        // butterflies: only the middle price's rounding (counted twice) can make them negative
        assertGe(a.c + c.c + 2 * u, 2 * b.c, "call butterfly");
        assertGe(a.p + c.p + 2 * u, 2 * b.p, "put butterfly");
        // C falls, P rises with K
        assertGe(a.c + u, b.c, "call falls with K");
        assertGe(c.p + u, b.p, "put rises with K");
        // 0 <= -dC/dK <= e^{-rT}: C(K1) - C(K2) <= e^{-rT} h
        assertLe(a.c, b.c + FPML.mulDivUp(dHi, h, WAD) + u, "-dC/dK <= e^-rT");
        // lower bounds: rounded up, so exact comparison
        uint256 kd = FPML.mulDiv(K2, dLo, WAD);
        assertGe(b.c, S > kd ? S - kd : 0, "call lower bound");
        uint256 kdUp = FPML.mulDivUp(K2, dHi, WAD);
        assertGe(b.p + 1, kd > S ? kd - S : 0, "put lower bound");
        // upper bounds
        assertLe(b.c, S + u, "C <= S");
        assertLe(b.p, kdUp + u, "P <= K e^-rT");
        // P/K rises with K: P(K2) K1 >= P(K1) K2, the rounding of P(K2) scaled by K1
        assertGe(FPML.fullMulDiv(b.p + u, K1, WAD), FPML.fullMulDiv(a.p, K2, WAD), "P/K rises with K");
        // deltas: magnitudes in [0, 1] summing to one
        assertEq(b.dc + b.dp, WAD, "deltas sum to one");
        assertLe(b.dc, WAD, "delta_call <= 1");
        // parity: C - P against S - K e^{-rT}, within the two prices' rounding
        int256 res = int256(b.c) - int256(b.p) - (int256(S) - int256(FPML.mulDiv(K2, d, WAD)));
        assertLe(res < 0 ? uint256(-res) : uint256(res), u + K2 / WAD + 1, "parity");
    }

    /// @dev The stage 0 cases at S 1, T 1, strikes 0.02 to 50, spacing 0.1% to 10% of the strike.
    function testFuzz_Stage0Cases(uint256 i, uint256 K, uint256 hBp) public pure {
        (uint256 sigma, uint256 r) = _case(bound(i, 0, 7));
        K = bound(K, 0.02e18, 45e18);
        uint256 h = K * bound(hBp, 10, 1000) / 10_000;
        _check(WAD, K, h, WAD, r, sigma);
    }

    /// @dev Free inputs: S from 0.01 to 1e6, strikes 0.02 S to 50 S, sigma 0.01 to 3, T one hour
    ///      to five years, r 0 to 0.3.
    function testFuzz_FreeInputs(uint256 S, uint256 m, uint256 hBp, uint256 sigma, uint256 T, uint256 r)
        public pure
    {
        S = bound(S, 0.01e18, 1e24);
        uint256 K = FPML.mulDiv(S, bound(m, 0.02e18, 45e18), WAD);
        uint256 h = K * bound(hBp, 10, 1000) / 10_000;
        sigma = bound(sigma, 0.01e18, 3e18);
        T = bound(T, 114155251141552, 5e18);
        r = bound(r, 0, 0.3e18);
        if (sigma * FPML.sqrt(T * WAD) / WAD < 1e9) return; // ZeroScale: not priced
        _check(S, K, h, T, r, sigma);
    }

    /// @dev One check in its own call frame, so that the grid below does not grow memory.
    function checkExt(uint256 S, uint256 K1, uint256 h, uint256 T, uint256 r, uint256 sigma)
        external pure
    {
        _check(S, K1, h, T, r, sigma);
    }

    /// @dev The whole stage 0 grid for case i: strikes 0.02 to 50 at ratio 1.003, each the
    ///      first of three spaced 0.3% apart.
    function _grid(uint256 i) internal view {
        (uint256 sigma, uint256 r) = _case(i);
        uint256 K = 0.02e18;
        uint256 n;
        while (K * 1006 / 1000 <= 50e18) {
            this.checkExt(WAD, K, K * 3 / 1000, WAD, r, sigma);
            K = K * 1003 / 1000;
            ++n;
        }
        assertGt(n, 2600);
    }

    function test_Stage0Grid_s004_r0() public view { _grid(0); }
    function test_Stage0Grid_s08_r0() public view { _grid(1); }
    function test_Stage0Grid_s15_r0() public view { _grid(2); }
    function test_Stage0Grid_s30_r0() public view { _grid(3); }
    function test_Stage0Grid_s08_r005() public view { _grid(4); }
    function test_Stage0Grid_s03_r02() public view { _grid(5); }
    function test_Stage0Grid_s224_r01() public view { _grid(6); }
    function test_Stage0Grid_s01_r005() public view { _grid(7); }
}
