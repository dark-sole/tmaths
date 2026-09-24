// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TMathFusaka} from "../src/TMathFusaka.sol";
import {TMathLegacy} from "../src/TMathLegacy.sol";

// Gas benchmarks for TMathFusaka and TMathLegacy.
//
// This file replaces the test_Gas_* functions from the pre-refactor
// TMaths.t.sol. All correctness coverage from that file is now in the
// three-tier suite (TMathVectors / TMathProperties / TMathEquivalence);
// only the gas benchmarks are kept, and they are extended to cover both
// libraries so the clz-versus-cascade cost is visible.
//
// Measurement style: functions are called DIRECTLY on the library, not
// through a harness contract. Library internal functions are inlined into
// the caller, so a direct call measures the algorithm's own gas with no
// CALL dispatch overhead. This is the right figure for comparing the
// implementations and matches how the original file measured.
//
// Inputs are perturbed by block.timestamp so the optimiser cannot fold the
// call to a compile-time constant. Run with:  forge test --match-contract
// TMathGas -vv   to see the logged numbers.
//
// Requires evm_version = "osaka" (or later) for the TMathFusaka half.

contract TMathGasTest is Test {
    uint256 internal constant PRECISION = 1e18;

    uint256 internal constant PI_4 = 785398163397448309;

    // Each benchmark logs Fusaka and Legacy side by side plus the delta.
    function _report(string memory name, uint256 gFusaka, uint256 gLegacy)
        internal
        pure
    {
        console.log(name);
        console.log("  Fusaka (clz)    :", gFusaka);
        console.log("  Legacy (cascade):", gLegacy);
        if (gLegacy >= gFusaka) {
            console.log("  cascade overhead:", gLegacy - gFusaka);
        } else {
            console.log("  Fusaka heavier by:", gFusaka - gLegacy);
        }
    }

    // ---- exp ----
    // exp does not use clz; Fusaka and Legacy exp are identical code.
    // Benchmarked once per library anyway as a refactor regression guard.

    function test_Gas_Exp() public view {
        uint256 input = PRECISION + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.exp(true, input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.exp(true, input);
        uint256 gLegacy = g1 - gasleft();

        _report("exp(true, ~1e18)", gFusaka, gLegacy);
    }

    function test_Gas_Exp_Negative() public view {
        uint256 input = PRECISION + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.exp(false, input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.exp(false, input);
        uint256 gLegacy = g1 - gasleft();

        _report("exp(false, ~1e18)", gFusaka, gLegacy);
    }

    // ---- ln ----
    // ln uses clz in Fusaka, the MSB cascade in Legacy. This is where the
    // cascade overhead shows up.

    function test_Gas_Ln() public view {
        uint256 input = 2 * PRECISION + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.ln(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.ln(input);
        uint256 gLegacy = g1 - gasleft();

        _report("ln(~2e18)", gFusaka, gLegacy);
    }

    function test_Gas_Ln_Small() public view {
        // antilog < 1e18 exercises the reciprocal path.
        uint256 input = (PRECISION / 2) + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.ln(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.ln(input);
        uint256 gLegacy = g1 - gasleft();

        _report("ln(~0.5e18)", gFusaka, gLegacy);
    }

    // ---- sqrt ----
    // sqrt uses clz in Fusaka, the MSB cascade in Legacy.

    function test_Gas_Sqrt() public view {
        uint256 input = 2 * PRECISION + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.sqrt(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.sqrt(input);
        uint256 gLegacy = g1 - gasleft();

        _report("sqrt(~2e18)", gFusaka, gLegacy);
    }

    function test_Gas_Sqrt_Large() public view {
        uint256 input = 1000000 * PRECISION + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.sqrt(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.sqrt(input);
        uint256 gLegacy = g1 - gasleft();

        _report("sqrt(~1e6 * 1e18)", gFusaka, gLegacy);
    }

    // ---- trig ----
    // trig does not use clz; Fusaka and Legacy trig are identical code.

    function test_Gas_Sin() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.sin(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.sin(input);
        uint256 gLegacy = g1 - gasleft();

        _report("sin(~pi/4)", gFusaka, gLegacy);
    }

    function test_Gas_Cos() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.cos(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.cos(input);
        uint256 gLegacy = g1 - gasleft();

        _report("cos(~pi/4)", gFusaka, gLegacy);
    }

    function test_Gas_Tan() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.tan(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.tan(input);
        uint256 gLegacy = g1 - gasleft();

        _report("tan(~pi/4)", gFusaka, gLegacy);
    }

    function test_Gas_SinSq() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.sin_sq(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.sin_sq(input);
        uint256 gLegacy = g1 - gasleft();

        _report("sin_sq(~pi/4)", gFusaka, gLegacy);
    }

    function test_Gas_CosSq() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);

        uint256 g0 = gasleft();
        TMathFusaka.cos_sq(input);
        uint256 gFusaka = g0 - gasleft();

        uint256 g1 = gasleft();
        TMathLegacy.cos_sq(input);
        uint256 gLegacy = g1 - gasleft();

        _report("cos_sq(~pi/4)", gFusaka, gLegacy);
    }
}
