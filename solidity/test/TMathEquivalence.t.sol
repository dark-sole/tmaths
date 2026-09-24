// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {HFusaka, HLegacy} from "./TMathHarness.sol";

// Tier 3: Equivalence tests.
//
// TMathFusaka and TMathLegacy differ only in how they compute floor(log2):
// Fusaka uses the EIP-7939 `clz` opcode, Legacy uses an MSB cascade. Every
// other line is identical. These tests assert the two libraries produce
// byte-identical output across the full input range, which proves the
// cascade is a faithful substitute for `clz`.
//
// Fuzzing is deliberately wide. For exp the input is bounded to the defined
// domain; for ln and sqrt the full non-zero uint256 range is used because
// both libraries must agree everywhere, including on inputs no consumer
// would ever pass. Domain-edge revert parity is checked explicitly.
//
// Requires evm_version = "osaka" (or later) in foundry.toml so that HFusaka,
// which contains the `clz` opcode, both compiles and executes.

contract TMathEquivalenceTest is Test {
    HFusaka internal fusaka;
    HLegacy internal legacy;

    uint256 internal constant EXP_MAX = 61e18;

    function setUp() public {
        fusaka = new HFusaka();
        legacy = new HLegacy();
    }

    // ---- exp ----

    function testFuzz_Equiv_Exp_Positive(uint256 exponent) public view {
        exponent = bound(exponent, 0, EXP_MAX);
        assertEq(
            fusaka.exp(true, exponent),
            legacy.exp(true, exponent),
            "exp(true) diverged between Fusaka and Legacy"
        );
    }

    function testFuzz_Equiv_Exp_Negative(uint256 exponent) public view {
        exponent = bound(exponent, 1e9, EXP_MAX);
        assertEq(
            fusaka.exp(false, exponent),
            legacy.exp(false, exponent),
            "exp(false) diverged between Fusaka and Legacy"
        );
    }

    function test_Equiv_Exp_RevertParity() public {
        // Both must revert on the same out-of-domain input.
        bool fRevert;
        bool lRevert;
        try fusaka.exp(true, EXP_MAX + 1) {
            fRevert = false;
        } catch {
            fRevert = true;
        }
        try legacy.exp(true, EXP_MAX + 1) {
            lRevert = false;
        } catch {
            lRevert = true;
        }
        assertTrue(fRevert && lRevert, "exp revert parity broken");
    }

    // ---- ln ----

    function testFuzz_Equiv_Ln(uint256 antilog) public view {
        // Full range except zero (zero reverts in both, covered separately).
        vm.assume(antilog != 0);
        (bool fNeg, uint256 fMag) = fusaka.ln(antilog);
        (bool lNeg, uint256 lMag) = legacy.ln(antilog);
        assertEq(fMag, lMag, "ln magnitude diverged");
        assertEq(fNeg, lNeg, "ln sign diverged");
    }

    function test_Equiv_Ln_RevertParity() public {
        bool fRevert;
        bool lRevert;
        try fusaka.ln(0) {
            fRevert = false;
        } catch {
            fRevert = true;
        }
        try legacy.ln(0) {
            lRevert = false;
        } catch {
            lRevert = true;
        }
        assertTrue(fRevert && lRevert, "ln revert parity broken");
    }

    // ---- sqrt ----

    function testFuzz_Equiv_Sqrt(uint256 x) public view {
        // Full range except zero.
        vm.assume(x != 0);
        assertEq(
            fusaka.sqrt(x),
            legacy.sqrt(x),
            "sqrt diverged between Fusaka and Legacy"
        );
    }

    function test_Equiv_Sqrt_RevertParity() public {
        bool fRevert;
        bool lRevert;
        try fusaka.sqrt(0) {
            fRevert = false;
        } catch {
            fRevert = true;
        }
        try legacy.sqrt(0) {
            lRevert = false;
        } catch {
            lRevert = true;
        }
        assertTrue(fRevert && lRevert, "sqrt revert parity broken");
    }

    // ---- trig ----
    //
    // trig does not use floor(log2) and therefore has no clz/cascade
    // difference. These tests are a regression guard: they confirm the
    // refactor did not accidentally perturb the trig code path in one file
    // but not the other.

    function testFuzz_Equiv_Sin(uint256 x) public view {
        x = bound(x, 0, 1000 * 1e18);
        (uint256 fMag, bool fSign) = fusaka.sin(x);
        (uint256 lMag, bool lSign) = legacy.sin(x);
        assertEq(fMag, lMag, "sin magnitude diverged");
        assertEq(fSign, lSign, "sin sign diverged");
    }

    function testFuzz_Equiv_Cos(uint256 x) public view {
        x = bound(x, 0, 1000 * 1e18);
        (uint256 fMag, bool fSign) = fusaka.cos(x);
        (uint256 lMag, bool lSign) = legacy.cos(x);
        assertEq(fMag, lMag, "cos magnitude diverged");
        assertEq(fSign, lSign, "cos sign diverged");
    }

    function testFuzz_Equiv_Tan(uint256 x) public view {
        x = bound(x, 0, 1000 * 1e18);
        // tan reverts Undefined() at poles (cos(x) == 0). Assert the two
        // libraries agree: either both revert, or both return equal values.
        try fusaka.tan(x) returns (uint256 fMag, bool fSign) {
            // Fusaka succeeded: Legacy must succeed with identical output.
            (uint256 lMag, bool lSign) = legacy.tan(x);
            assertEq(fMag, lMag, "tan magnitude diverged");
            assertEq(fSign, lSign, "tan sign diverged");
        } catch {
            // Fusaka reverted at a pole: Legacy must revert too.
            try legacy.tan(x) returns (uint256, bool) {
                revert("tan revert diverged: Fusaka reverted, Legacy did not");
            } catch {
                // both reverted - equivalence holds
            }
        }
    }

    function testFuzz_Equiv_SinSq(uint256 x) public view {
        x = bound(x, 0, 1000 * 1e18);
        assertEq(fusaka.sin_sq(x), legacy.sin_sq(x), "sin_sq diverged");
    }

    function testFuzz_Equiv_CosSq(uint256 x) public view {
        x = bound(x, 0, 1000 * 1e18);
        assertEq(fusaka.cos_sq(x), legacy.cos_sq(x), "cos_sq diverged");
    }
}
