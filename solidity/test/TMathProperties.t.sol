// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {HFusaka, HLegacy} from "./TMathHarness.sol";

// Tier 2: Property tests.
//
// Fuzzes in-domain inputs and asserts algebraic invariants that hold
// regardless of numerical precision: fixed points, monotonicity, roundtrip
// identities, and domain-edge revert behaviour. These tests are
// self-checking and need no mpmath reference.
//
// Inputs are constrained with vm.assume / bound so the fuzzer stays inside
// each function's defined domain:
//   exp:  exponent in [0, 61e18]
//   ln:   antilog > 0
//   sqrt: x > 0
//
// Both libraries are exercised. Where an invariant is identical for both,
// the test runs against HFusaka; HLegacy parity is covered by the
// equivalence tier.

contract TMathPropertiesTest is Test {
    HFusaka internal fusaka;
    HLegacy internal legacy;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant EXP_MAX = 61e18;

    // Roundtrip tolerance: exp and ln each carry error, so the composition
    // carries roughly their sum. 1e-3 (WAD 1e15) is comfortably above the
    // measured ~3e-5 worst case while still catching a real regression.
    uint256 internal constant TOL_ROUNDTRIP = 1e15;

    function setUp() public {
        fusaka = new HFusaka();
        legacy = new HLegacy();
    }

    function _relError(uint256 got, uint256 expected) internal pure returns (uint256) {
        if (expected == 0) return got;
        uint256 diff = got > expected ? got - expected : expected - got;
        return (diff * WAD) / expected;
    }

    // ---- exp: fixed point and monotonicity ----

    function test_Prop_Exp_ZeroIsOne() public view {
        assertEq(fusaka.exp(true, 0), WAD, "exp(0) must be 1e18");
        assertEq(legacy.exp(true, 0), WAD, "exp(0) must be 1e18");
    }

    function testFuzz_Prop_Exp_Monotonic(uint256 a, uint256 b) public view {
        a = bound(a, 0, EXP_MAX);
        b = bound(b, 0, EXP_MAX);
        vm.assume(a < b);
        // exp is strictly increasing: a < b implies exp(a) <= exp(b).
        // Allow equality because integer truncation can flatten tiny gaps.
        assertLe(fusaka.exp(true, a), fusaka.exp(true, b), "exp not monotonic");
    }

    function testFuzz_Prop_Exp_ReciprocalIdentity(uint256 x) public view {
        // exp(-x) is WAD-scaled: for x beyond ~36 it decays to a 2-3 digit
        // integer with too few significant figures for the reciprocal
        // identity to hold at 1e-3. Cap at 30 (exp(-30) WAD ~ 93576, still
        // 5 digits) so the identity is tested only where WAD can represent
        // both directions. This is a representation limit, not an exp bug.
        x = bound(x, 1e15, 30e18);
        // exp(-x) = 1 / exp(x): the positive=false path must equal the
        // reciprocal of the positive path.
        uint256 pos = fusaka.exp(true, x);
        uint256 neg = fusaka.exp(false, x);
        // pos * neg should be approximately 1e36 (1.0 in WAD-squared).
        uint256 product = (pos * neg);
        // product / 1e18 should be near 1e18.
        uint256 normalised = product / WAD;
        uint256 rel = _relError(normalised, WAD);
        assertLt(rel, TOL_ROUNDTRIP, "exp(-x) != 1/exp(x)");
    }

    function test_Prop_Exp_RevertsAboveDomain() public {
        vm.expectRevert();
        fusaka.exp(true, EXP_MAX + 1);
        vm.expectRevert();
        legacy.exp(true, EXP_MAX + 1);
    }

    // ---- ln: fixed point, sign, monotonicity ----

    function test_Prop_Ln_OneIsZero() public view {
        (bool negF, uint256 magF) = fusaka.ln(WAD);
        assertEq(magF, 0, "ln(1) must be 0 (Fusaka)");
        assertFalse(negF, "ln(1) not negative");
        (bool negL, uint256 magL) = legacy.ln(WAD);
        assertEq(magL, 0, "ln(1) must be 0 (Legacy)");
        assertFalse(negL, "ln(1) not negative");
    }

    function testFuzz_Prop_Ln_SignBelowOne(uint256 x) public view {
        x = bound(x, 1, WAD - 1);
        // ln(x) < 0 for 0 < x < 1.
        (bool neg, uint256 mag) = fusaka.ln(x);
        if (mag > 0) {
            assertTrue(neg, "ln(x<1) should be negative");
        }
    }

    function testFuzz_Prop_Ln_SignAboveOne(uint256 x) public view {
        x = bound(x, WAD + 1, type(uint128).max);
        // ln(x) > 0 for x > 1.
        (bool neg, uint256 mag) = fusaka.ln(x);
        if (mag > 0) {
            assertFalse(neg, "ln(x>1) should be positive");
        }
    }

    function testFuzz_Prop_Ln_Monotonic(uint256 a, uint256 b) public view {
        a = bound(a, WAD, type(uint128).max);
        b = bound(b, WAD, type(uint128).max);
        vm.assume(a < b);
        // For a, b >= 1, ln is non-negative and increasing.
        (, uint256 la) = fusaka.ln(a);
        (, uint256 lb) = fusaka.ln(b);
        assertLe(la, lb, "ln not monotonic above 1");
    }

    function test_Prop_Ln_RevertsOnZero() public {
        vm.expectRevert();
        fusaka.ln(0);
        vm.expectRevert();
        legacy.ln(0);
    }

    // ---- exp / ln roundtrip ----

    function testFuzz_Prop_Roundtrip_ExpLn(uint256 x) public view {
        // x in [1.0, e^30] so that ln(x) is in [0, 30] and exp can take it.
        x = bound(x, WAD, 1e31);
        (bool neg, uint256 lnMag) = fusaka.ln(x);
        // exp(ln(x)) should recover x. ln(x) >= 0 here, so positive = !neg.
        uint256 recovered = fusaka.exp(!neg, lnMag);
        uint256 rel = _relError(recovered, x);
        assertLt(rel, TOL_ROUNDTRIP, "exp(ln(x)) != x");
    }

    function testFuzz_Prop_Roundtrip_LnExp(uint256 x) public view {
        // x in [0.001, 30] (WAD-scaled), so exp(x) is representable and
        // ln of the result is defined.
        x = bound(x, 1e15, 30 * WAD);
        uint256 e = fusaka.exp(true, x);
        (bool neg, uint256 lnMag) = fusaka.ln(e);
        assertFalse(neg, "ln(exp(x)) should be positive for x>0");
        uint256 rel = _relError(lnMag, x);
        assertLt(rel, TOL_ROUNDTRIP, "ln(exp(x)) != x");
    }

    // ---- sqrt: fixed point, monotonicity, square identity ----

    function test_Prop_Sqrt_OneIsOne() public view {
        assertEq(fusaka.sqrt(WAD), WAD, "sqrt(1) must be 1e18");
        assertEq(legacy.sqrt(WAD), WAD, "sqrt(1) must be 1e18");
    }

    function testFuzz_Prop_Sqrt_Monotonic(uint256 a, uint256 b) public view {
        a = bound(a, 1, type(uint128).max);
        b = bound(b, 1, type(uint128).max);
        vm.assume(a < b);
        assertLe(fusaka.sqrt(a), fusaka.sqrt(b), "sqrt not monotonic");
    }

    function testFuzz_Prop_Sqrt_SquareIdentity(uint256 x) public view {
        // sqrt(x)^2 should be approximately x. Work in a range where
        // sqrt(x)^2 does not overflow: x up to ~1e30 keeps sqrt under 1e24.
        x = bound(x, 1e12, 1e30);
        uint256 s = fusaka.sqrt(x);
        // (s * s) / 1e18 reconstructs x in WAD scale.
        uint256 reconstructed = (s * s) / WAD;
        uint256 rel = _relError(reconstructed, x);
        // sqrt is the most accurate function; 1e-6 is generous.
        assertLt(rel, 1e12, "sqrt(x)^2 != x");
    }

    function test_Prop_Sqrt_RevertsOnZero() public {
        vm.expectRevert();
        fusaka.sqrt(0);
        vm.expectRevert();
        legacy.sqrt(0);
    }

    // ---- trig: Pythagorean identity and bounds ----

    function testFuzz_Prop_Trig_PythagoreanIdentity(uint256 x) public view {
        // sin^2 + cos^2 = 1 for any angle. Use the sin_sq / cos_sq helpers.
        x = bound(x, 0, 100 * WAD);
        uint256 s2 = fusaka.sin_sq(x);
        uint256 c2 = fusaka.cos_sq(x);
        uint256 sum = s2 + c2;
        uint256 rel = _relError(sum, WAD);
        // Two squared trig values, each carrying ~5ppm: allow 1e-4.
        assertLt(rel, 1e14, "sin^2 + cos^2 != 1");
    }

    function testFuzz_Prop_Trig_Bounded(uint256 x) public view {
        // |sin(x)| <= 1 and |cos(x)| <= 1.
        x = bound(x, 0, 100 * WAD);
        (uint256 sinMag,) = fusaka.sin(x);
        (uint256 cosMag,) = fusaka.cos(x);
        // Allow a tiny overshoot from truncation noise.
        assertLe(sinMag, WAD + 1e12, "sin magnitude exceeds 1");
        assertLe(cosMag, WAD + 1e12, "cos magnitude exceeds 1");
    }
}
