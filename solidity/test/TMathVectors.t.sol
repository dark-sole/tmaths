// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {HFusaka, HLegacy} from "./TMathHarness.sol";
import {TMathVectorData} from "./TMathVectors.gen.sol";

// Tier 1: Vector tests.
//
// Asserts each library output against a reference value computed offline by
// mpmath at 50-digit precision (see gen_vectors.py). This tier quantifies the
// real numerical error of the implementation and catches accuracy regressions.
//
// Tolerance bands (relative error, WAD-scaled):
//   exp:  1e-5  (measured worst case ~3.8e-6)
//   ln:   1e-4  (measured worst case ~7.5e-5 at the m=1.5 branch boundary)
//   sqrt: 1e-8  (measured worst case ~1e-9)
//   sin:  1e-5  (octant-reduced Taylor)
//   cos:  1e-5
//
// Both libraries are tested. They are expected to produce identical output;
// the equivalence tier proves that directly, this tier proves both are
// independently within tolerance of the true value.

contract TMathVectorsTest is Test, TMathVectorData {
    HFusaka internal fusaka;
    HLegacy internal legacy;

    uint256 internal constant WAD = 1e18;

    uint256 internal constant TOL_EXP = 1e13;   // 1e-5
    uint256 internal constant TOL_LN = 1e14;    // 1e-4
    uint256 internal constant TOL_SQRT = 1e10;  // 1e-8
    uint256 internal constant TOL_TRIG = 1e13;  // 1e-5 relative
    // sin/cos references below this absolute value are treated as zero
    // crossings: a relative-error check against a near-zero reference is
    // meaningless (mpmath emits e.g. 142 for a true value of ~1.4e-16).
    // 1e9 sits far above the largest genuine crossing residual (~479) and
    // far below the smallest non-crossing magnitude (~1e17).
    uint256 internal constant TRIG_ZERO_FLOOR = 1e9;

    function setUp() public {
        fusaka = new HFusaka();
        legacy = new HLegacy();
        _loadAllVectors();
    }

    // Relative error, WAD-scaled: |got - expected| * 1e18 / expected.
    // For expected == 0 the caller must handle the absolute case separately.
    function _relError(uint256 got, uint256 expected) internal pure returns (uint256) {
        uint256 diff = got > expected ? got - expected : expected - got;
        return (diff * WAD) / expected;
    }

    // ---- exp ----

    function test_Vectors_Exp_Fusaka() public view {
        for (uint256 i = 0; i < expVec.length; i++) {
            uint256 input = expVec[i][0];
            uint256 expected = expVec[i][1];
            uint256 got = fusaka.exp(true, input);
            uint256 rel = _relError(got, expected);
            assertLt(rel, TOL_EXP, "exp(Fusaka) outside tolerance");
        }
    }

    function test_Vectors_Exp_Legacy() public view {
        for (uint256 i = 0; i < expVec.length; i++) {
            uint256 input = expVec[i][0];
            uint256 expected = expVec[i][1];
            uint256 got = legacy.exp(true, input);
            uint256 rel = _relError(got, expected);
            assertLt(rel, TOL_EXP, "exp(Legacy) outside tolerance");
        }
    }

    // ---- ln ----

    function test_Vectors_Ln_Fusaka() public view {
        for (uint256 i = 0; i < lnVec.length; i++) {
            uint256 input = lnVec[i][0];
            uint256 expectedMag = lnVec[i][1];
            bool expectedNeg = lnVec[i][2] == 1;
            (bool gotNeg, uint256 gotMag) = fusaka.ln(input);

            if (expectedMag == 0) {
                assertEq(gotMag, 0, "ln(Fusaka) should be zero at x=1");
                continue;
            }
            assertEq(gotNeg, expectedNeg, "ln(Fusaka) sign mismatch");
            uint256 rel = _relError(gotMag, expectedMag);
            assertLt(rel, TOL_LN, "ln(Fusaka) outside tolerance");
        }
    }

    function test_Vectors_Ln_Legacy() public view {
        for (uint256 i = 0; i < lnVec.length; i++) {
            uint256 input = lnVec[i][0];
            uint256 expectedMag = lnVec[i][1];
            bool expectedNeg = lnVec[i][2] == 1;
            (bool gotNeg, uint256 gotMag) = legacy.ln(input);

            if (expectedMag == 0) {
                assertEq(gotMag, 0, "ln(Legacy) should be zero at x=1");
                continue;
            }
            assertEq(gotNeg, expectedNeg, "ln(Legacy) sign mismatch");
            uint256 rel = _relError(gotMag, expectedMag);
            assertLt(rel, TOL_LN, "ln(Legacy) outside tolerance");
        }
    }

    // ---- sqrt ----

    function test_Vectors_Sqrt_Fusaka() public view {
        for (uint256 i = 0; i < sqrtVec.length; i++) {
            uint256 input = sqrtVec[i][0];
            uint256 expected = sqrtVec[i][1];
            uint256 got = fusaka.sqrt(input);
            uint256 rel = _relError(got, expected);
            assertLt(rel, TOL_SQRT, "sqrt(Fusaka) outside tolerance");
        }
    }

    function test_Vectors_Sqrt_Legacy() public view {
        for (uint256 i = 0; i < sqrtVec.length; i++) {
            uint256 input = sqrtVec[i][0];
            uint256 expected = sqrtVec[i][1];
            uint256 got = legacy.sqrt(input);
            uint256 rel = _relError(got, expected);
            assertLt(rel, TOL_SQRT, "sqrt(Legacy) outside tolerance");
        }
    }

    // ---- sin ----

    function test_Vectors_Sin_Fusaka() public view {
        for (uint256 i = 0; i < sinVec.length; i++) {
            uint256 input = sinVec[i][0];
            uint256 expectedMag = sinVec[i][1];
            bool expectedNeg = sinVec[i][2] == 1;
            (uint256 gotMag, bool gotSign) = fusaka.sin(input);

            // gotSign is true for positive. expectedNeg is true for negative.
            // Near a zero crossing, magnitude is tiny and the sign is
            // numerically ambiguous; only assert sign when the magnitude is
            // comfortably above the noise floor.
            if (expectedMag > TOL_TRIG) {
                assertEq(gotSign, !expectedNeg, "sin(Fusaka) sign mismatch");
            }
            if (expectedMag < TRIG_ZERO_FLOOR) {
                assertLt(gotMag, TOL_TRIG, "sin(Fusaka) should be near zero");
                continue;
            }
            uint256 rel = _relError(gotMag, expectedMag);
            assertLt(rel, TOL_TRIG, "sin(Fusaka) outside tolerance");
        }
    }

    function test_Vectors_Sin_Legacy() public view {
        for (uint256 i = 0; i < sinVec.length; i++) {
            uint256 input = sinVec[i][0];
            uint256 expectedMag = sinVec[i][1];
            bool expectedNeg = sinVec[i][2] == 1;
            (uint256 gotMag, bool gotSign) = legacy.sin(input);

            if (expectedMag > TOL_TRIG) {
                assertEq(gotSign, !expectedNeg, "sin(Legacy) sign mismatch");
            }
            if (expectedMag < TRIG_ZERO_FLOOR) {
                assertLt(gotMag, TOL_TRIG, "sin(Legacy) should be near zero");
                continue;
            }
            uint256 rel = _relError(gotMag, expectedMag);
            assertLt(rel, TOL_TRIG, "sin(Legacy) outside tolerance");
        }
    }

    // ---- cos ----

    function test_Vectors_Cos_Fusaka() public view {
        for (uint256 i = 0; i < cosVec.length; i++) {
            uint256 input = cosVec[i][0];
            uint256 expectedMag = cosVec[i][1];
            bool expectedNeg = cosVec[i][2] == 1;
            (uint256 gotMag, bool gotSign) = fusaka.cos(input);

            if (expectedMag > TOL_TRIG) {
                assertEq(gotSign, !expectedNeg, "cos(Fusaka) sign mismatch");
            }
            if (expectedMag < TRIG_ZERO_FLOOR) {
                assertLt(gotMag, TOL_TRIG, "cos(Fusaka) should be near zero");
                continue;
            }
            uint256 rel = _relError(gotMag, expectedMag);
            assertLt(rel, TOL_TRIG, "cos(Fusaka) outside tolerance");
        }
    }

    function test_Vectors_Cos_Legacy() public view {
        for (uint256 i = 0; i < cosVec.length; i++) {
            uint256 input = cosVec[i][0];
            uint256 expectedMag = cosVec[i][1];
            bool expectedNeg = cosVec[i][2] == 1;
            (uint256 gotMag, bool gotSign) = legacy.cos(input);

            if (expectedMag > TOL_TRIG) {
                assertEq(gotSign, !expectedNeg, "cos(Legacy) sign mismatch");
            }
            if (expectedMag < TRIG_ZERO_FLOOR) {
                assertLt(gotMag, TOL_TRIG, "cos(Legacy) should be near zero");
                continue;
            }
            uint256 rel = _relError(gotMag, expectedMag);
            assertLt(rel, TOL_TRIG, "cos(Legacy) outside tolerance");
        }
    }
}
