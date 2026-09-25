// SPDX-License-Identifier: UNLICENSED
// © 2026 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";
import {DaletOption} from "../src/DaletOption.sol";
import {FundingBond} from "../src/FundingBond.sol";
import {
    FundingBondVectors, FBVector, SettleVector, FBRevertVector, GridVector
} from "./FundingBondVectors.gen.sol";

/// @dev Dispatch by the vector's fn code (see FundingBondVectors.gen.sol), external so that a
///      revert can be expected.
contract FundingBondWrapper {
    function call(uint8 fn, uint8 n, int256[8] memory a) external pure returns (int256, int256) {
        uint256[8] memory u;
        for (uint256 i; i < 8; ++i) u[i] = a[i] >= 0 ? uint256(a[i]) : 0;
        if (fn == 0) return (int256(FundingBond.knockInLog(u[0], u[1])), 0);
        if (fn == 1) return (int256(FundingBond.knockInLong(u[0], u[1], u[2])), 0);
        if (fn == 2) return (int256(FundingBond.knockInShort(u[0], u[1], u[2])), 0);
        if (fn == 3) return (int256(FundingBond.gapClaimLong(u[0], u[1], u[2], u[3])), 0);
        if (fn == 4) return (int256(FundingBond.gapClaimShort(u[0], u[1], u[2], u[3])), 0);
        if (fn == 5) return (int256(FundingBond.premium(u[0], u[1], u[2])), 0);
        if (fn == 6 || fn == 7) {
            uint256 m = (uint256(n) - 1) / 2;
            uint256[] memory ks = new uint256[](m);
            uint256[] memory qs = new uint256[](m);
            for (uint256 i; i < m; ++i) {
                ks[i] = u[1 + 2 * i];
                qs[i] = u[2 + 2 * i];
            }
            uint256 s = fn == 6 ? FundingBond.capOf(ks, qs, u[0]) : FundingBond.floorOf(ks, qs, u[0]);
            return (int256(s), 0);
        }
        if (fn == 8) {
            return (int256(FundingBond.itoPaid(u[0], u[1], u[2])),
                    int256(FundingBond.itoReceived(u[0], u[1], u[2])));
        }
        if (fn == 9) return (FundingBond.basisLog(u[0], u[1]), 0);
        if (fn == 10) return (FundingBond.basisLogTicks(a[0], u[1]), 0);
        if (fn == 11) return (FundingBond.toRatio(a[0]), 0);
        revert("fn");
    }
}

/// @notice FundingBond against the funding bond reference vectors (PERP vectors.json): every
///         output on the side of the exact value its direction names, and within the margin
///         chosen for it. Every result is logged as `id output value`; the largest excess of
///         each function over its exact value is logged per unit of the price it is on.
contract FundingBondVectorsTest is Test {

    uint256 internal constant WAD = 1e18;

    FundingBondWrapper internal w;

    uint256[12] internal count;
    uint256[12] internal worst;

    function setUp() public {
        w = new FundingBondWrapper();
    }

    /// @dev DaletOption's margin on S and K, as `_margin`, plus one wei.
    function _m(uint256 S, uint256 K) internal pure returns (uint256) {
        return DaletOption.MARGIN_WEI + FPML.mulDivUp(S + K, DaletOption.MARGIN_PER_UNIT, WAD) + 1;
    }

    /// @dev The margin allowed over the exact value, per function, in wei.
    function _tol(FBVector memory v) internal pure returns (uint256) {
        if (v.fn <= 2) return 16 + uint256(v.hi) / 1e15;
        if (v.fn == 3 || v.fn == 4) {
            uint256 K = uint256(v.a[0]);
            return 2 * (_m(K, K) + _m(K, uint256(v.a[1]))) + 8;
        }
        if (v.fn <= 8) return 1;
        return 4;
    }

    /// @dev The price a result is measured per unit of, for the report.
    function _unit(FBVector memory v) internal pure returns (uint256) {
        if (v.fn == 3 || v.fn == 4) return uint256(v.a[0]);
        if (v.fn == 8) return FPML.mulDiv(uint256(v.a[0]), uint256(v.a[1]), WAD);
        return WAD;
    }

    function _up(FBVector memory v, string memory name, int256 got) internal returns (uint256 ex) {
        console.log(v.id, name, uint256(got));
        assertGe(got, v.hi, string.concat(v.id, " ", name, ": below the exact value (up)"));
        ex = uint256(got - v.hi);
        assertLe(ex, _tol(v), string.concat(v.id, " ", name, ": excess over the exact value"));
    }

    function _down(FBVector memory v, string memory name, int256 got) internal returns (uint256 ex) {
        console.log(v.id, name, uint256(got));
        assertLe(got, v.lo, string.concat(v.id, " ", name, ": above the exact value (down)"));
        ex = uint256(v.lo - got);
        assertLe(ex, _tol(v), string.concat(v.id, " ", name, ": shortfall below the exact value"));
    }

    function _near(FBVector memory v, int256 got) internal returns (uint256 ex) {
        console.logInt(got);
        int256 t = int256(_tol(v));
        assertGe(got, v.lo - t, string.concat(v.id, ": below the exact value"));
        assertLe(got, v.hi + t, string.concat(v.id, ": above the exact value"));
        ex = got < v.lo ? uint256(v.lo - got) : (got > v.hi ? uint256(got - v.hi) : 0);
    }

    function test_Vectors() public {
        FBVector[] memory vs = FundingBondVectors.vectors();
        for (uint256 i; i < vs.length; ++i) {
            FBVector memory v = vs[i];
            (int256 r0, int256 r1) = w.call(v.fn, v.n, v.a);
            uint256 ex;
            if (v.fn <= 5 || v.fn == 7) ex = _up(v, "value", r0);
            else if (v.fn == 6) ex = _down(v, "value", r0);
            else if (v.fn == 8) {
                ex = _up(v, "paid", r0);
                uint256 ex2 = _down(v, "received", r1);
                if (ex2 > ex) ex = ex2;
            } else ex = _near(v, r0);
            ++count[v.fn];
            uint256 per = FPML.mulDivUp(ex, WAD, _unit(v));
            if (per > worst[v.fn]) worst[v.fn] = per;
        }
        string[12] memory names = ["knockInLog", "knockInLong", "knockInShort", "gapClaimLong",
            "gapClaimShort", "premium", "capOf", "floorOf", "itoPaid/itoReceived", "basisLog",
            "basisLogTicks", "toRatio"];
        for (uint256 f; f < 12; ++f) {
            console.log(string.concat("COUNT ", names[f]), count[f], "worst wei per unit", worst[f]);
        }
    }

    function test_Settles() public {
        SettleVector[] memory vs = FundingBondVectors.settles();
        for (uint256 i; i < vs.length; ++i) {
            SettleVector memory v = vs[i];
            int256 f = FundingBond.basisRate(FundingBond.basisLog(v.Ap, v.Ai), v.ratio);
            uint256 total;
            uint256 qr;
            for (uint256 j; j < 4; ++j) {
                assertEq(v.pays[j], f > 0 ? v.isLong[j] : !v.isLong[j], v.id);
                if (!v.pays[j]) {
                    qr += v.q[j];
                    continue;
                }
                uint256 got = FundingBond.basisPay(f, v.q[j], v.Ai);
                console.log(v.id, "pays", got);
                assertGe(got, v.hi[j], string.concat(v.id, ": pays below the exact value (up)"));
                uint256 tol = FPML.mulDivUp(FundingBond.BASIS_RATE_ERR + 4, v.q[j] * v.Ai, 1e36) + 2;
                assertLe(got - v.hi[j], tol, string.concat(v.id, ": pays excess"));
                total += got;
            }
            uint256 received;
            for (uint256 j; j < 4; ++j) {
                if (v.pays[j]) continue;
                // Its own direction, on the exact total: at or below the exact amount.
                uint256 own = FundingBond.basisReceive(v.totalFloor, v.q[j], qr);
                assertLe(own, v.lo[j], string.concat(v.id, ": receives above the exact value (down)"));
                assertLe(v.lo[j] - own, 2, string.concat(v.id, ": receives shortfall"));
                // In the chain, on what was paid: never short of the exact amount.
                uint256 got = FundingBond.basisReceive(total, v.q[j], qr);
                console.log(v.id, "receives", got);
                assertGe(got + 1, v.lo[j], string.concat(v.id, ": receiver shorted"));
                received += got;
            }
            assertGe(total, received, string.concat(v.id, ": negative dust"));
            console.log(v.id, "dust", total - received);
        }
    }

    function test_Reverts() public {
        FBRevertVector[] memory vs = FundingBondVectors.reverts();
        assertGt(vs.length, 0);
        for (uint256 i; i < vs.length; ++i) {
            FBRevertVector memory v = vs[i];
            vm.expectRevert(bytes4(keccak256(bytes(v.err))));
            w.call(v.fn, v.n, v.a);
        }
    }

    /// @dev Stage 3e: the gap claim at or above the model's exact value on the grid, Strikes
    ///      0.02 to 50, floors and caps a tenth to nine tenths away.
    function test_GapClaimGrid() public {
        GridVector[] memory vs = FundingBondVectors.grid();
        uint256 worstPer;
        for (uint256 i; i < vs.length; ++i) {
            GridVector memory v = vs[i];
            uint256 got = v.isLong
                ? FundingBond.gapClaimLong(v.K, v.X, FundingBondVectors.SIGMA, FundingBondVectors.H)
                : FundingBond.gapClaimShort(v.K, v.X, FundingBondVectors.SIGMA, FundingBondVectors.H);
            assertGe(got, v.ceil, "gap claim below the exact value");
            uint256 per = FPML.mulDivUp(got - v.ceil, WAD, v.K);
            if (per > worstPer) worstPer = per;
        }
        console.log("GRID", vs.length, "worst wei per unit of the Strike", worstPer);
    }
}

/// @notice Stage 3e properties by fuzz: knock-in in [0, 1], falling in d and rising in dV; cap
///         and floor on random sorted books with L(S) <= U at the returned price, and one wei
///         further (towards the Strikes) exceeding U.
contract FundingBondPropertiesTest is Test {

    uint256 internal constant WAD = 1e18;

    function testFuzz_KnockInRange(uint256 d, uint256 dV) public pure {
        d = bound(d, 1, 100e18);
        dV = bound(dV, 1, 100e18);
        assertLe(FundingBond.knockInLog(d, dV), WAD);
    }

    function testFuzz_KnockInFallsInD(uint256 d1, uint256 d2, uint256 dV) public pure {
        d1 = bound(d1, 1, 100e18);
        d2 = bound(d2, d1, 100e18);
        dV = bound(dV, 1, 100e18);
        assertGe(FundingBond.knockInLog(d1, dV), FundingBond.knockInLog(d2, dV));
    }

    function testFuzz_KnockInRisesInDV(uint256 d, uint256 v1, uint256 v2) public pure {
        d = bound(d, 1, 100e18);
        v1 = bound(v1, 0, 100e18);
        v2 = bound(v2, v1, 100e18);
        assertLe(FundingBond.knockInLog(d, v1), FundingBond.knockInLog(d, v2));
    }

    function _book(uint256 seed, uint256 n) internal pure returns (uint256[] memory ks, uint256[] memory qs) {
        ks = new uint256[](n);
        qs = new uint256[](n);
        uint256 k = 0.01e18;
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            k += 1 + r % 1000e18;
            ks[i] = k;
            qs[i] = 1e12 + (r >> 128) % 1e24;
        }
    }

    /// @dev The shorts' liability at S, at 1e36: sum over K < S of q (S - K).
    function _lShort(uint256[] memory ks, uint256[] memory qs, uint256 S) internal pure returns (uint256 l) {
        for (uint256 i; i < ks.length; ++i) if (ks[i] < S) l += qs[i] * (S - ks[i]);
    }

    /// @dev The longs' liability at S, at 1e36: sum over K > S of q (K - S).
    function _lLong(uint256[] memory ks, uint256[] memory qs, uint256 S) internal pure returns (uint256 l) {
        for (uint256 i; i < ks.length; ++i) if (ks[i] > S) l += qs[i] * (ks[i] - S);
    }

    function testFuzz_CapBook(uint256 seed, uint256 n, uint256 U) public pure {
        n = bound(n, 1, 6);
        U = bound(U, 1e12, 1e27);
        (uint256[] memory ks, uint256[] memory qs) = _book(seed, n);
        uint256 S = FundingBond.capOf(ks, qs, U);
        assertLe(_lShort(ks, qs, S), U * WAD, "L(S*) <= U");
        assertGt(_lShort(ks, qs, S + 1), U * WAD, "one wei above S*, L > U");
    }

    function testFuzz_FloorBook(uint256 seed, uint256 n, uint256 U) public pure {
        n = bound(n, 1, 6);
        U = bound(U, 1e12, 1e27);
        (uint256[] memory ks, uint256[] memory qs) = _book(seed, n);
        uint256 S = FundingBond.floorOf(ks, qs, U);
        assertLe(_lLong(ks, qs, S), U * WAD, "L(S_*) <= U");
        if (S > 0) assertGt(_lLong(ks, qs, S - 1), U * WAD, "one wei below S_*, L > U");
    }
}
