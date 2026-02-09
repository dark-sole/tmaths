// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {DaletCDF} from "../src/DaletCDF.sol";

contract DaletCDFTest is Test {
    uint256 constant P = 1e18;

    // ═══════════════════════════════════════════════════════
    // Basic shape tests
    // ═══════════════════════════════════════════════════════

    function test_Zero() public pure {
        uint256 cdf = DaletCDF.daletCdfFast(false, 0);
        assertEq(cdf, 0.5e18, "Dalet(0) = 0.5");
    }

    function test_PositiveAboveHalf() public pure {
        uint256 cdf = DaletCDF.daletCdfFast(false, 1e18);
        assertGt(cdf, 0.5e18, "Dalet(1) > 0.5");
        console.log("Dalet(1):", cdf);
    }

    function test_NegativeBelowHalf() public pure {
        uint256 cdf = DaletCDF.daletCdfFast(true, 1e18);
        assertLt(cdf, 0.5e18, "Dalet(-1) < 0.5");
        console.log("Dalet(-1):", cdf);
    }

    function test_Symmetry() public pure {
        // Φ(x) + Φ(-x) = 1
        uint256 pos = DaletCDF.daletCdfFast(false, 1e18);
        uint256 neg = DaletCDF.daletCdfFast(true, 1e18);
        assertEq(pos + neg, 1e18, "Dalet(1) + Dalet(-1) = 1");
    }

    function test_SymmetryMultiple() public pure {
        uint256[5] memory xs = [uint256(0.1e18), 0.5e18, 1e18, 2e18, 5e18];
        for (uint256 i = 0; i < 5; i++) {
            uint256 pos = DaletCDF.daletCdfFast(false, xs[i]);
            uint256 neg = DaletCDF.daletCdfFast(true, xs[i]);
            assertEq(pos + neg, 1e18, "symmetry violated");
        }
    }

    // ═══════════════════════════════════════════════════════
    // Monotonicity
    // ═══════════════════════════════════════════════════════

    function test_Monotonic() public pure {
        uint256 prev = DaletCDF.daletCdfFast(false, 0);
        uint256[7] memory xs = [uint256(0.1e18), 0.5e18, 1e18, 2e18, 3e18, 5e18, 8e18];
        for (uint256 i = 0; i < 7; i++) {
            uint256 cdf = DaletCDF.daletCdfFast(false, xs[i]);
            assertGt(cdf, prev, "CDF must be monotonically increasing");
            prev = cdf;
        }
    }

    // ═══════════════════════════════════════════════════════
    // Boundary cases
    // ═══════════════════════════════════════════════════════

    function test_LargePositive() public pure {
        uint256 cdf = DaletCDF.daletCdfFast(false, 340e18);
        assertEq(cdf, 1e18, "Dalet(340) = 1");
    }

    function test_LargeNegative() public pure {
        uint256 cdf = DaletCDF.daletCdfFast(true, 340e18);
        assertEq(cdf, 0, "Dalet(-340) = 0");
    }

    function test_JustBelowClamp() public pure {
        uint256 cdf = DaletCDF.daletCdfFast(false, 8e18);
        assertGt(cdf, 0.99e18, "Dalet(8) > 0.99");
        assertLt(cdf, 1e18, "Dalet(8) < 1");
        console.log("Dalet(8):", cdf);
    }

    function test_HeavyTailStillComputes() public pure {
        // At x=100, tail should be small but nonzero
        uint256 cdf = DaletCDF.daletCdfFast(true, 100e18);
        assertGt(cdf, 0, "Dalet(-100) > 0");
        console.log("Dalet(-100):", cdf);
    }

    // ═══════════════════════════════════════════════════════
    // Known values: Φ_D(x) = (1 + x/√(1+x²)) / 2
    // ═══════════════════════════════════════════════════════

    function test_KnownValues() public pure {
        // x=1: sin(arctan(1)) = 1/√2 ~ 0.7071
        // CDF = (1 + 0.7071)/2 ~ 0.8536
        uint256 cdf1 = DaletCDF.daletCdfFast(false, 1e18);
        assertApproxEqRel(cdf1, 853553390593273762, 1e14, "Dalet(1) ~ 0.8536");
        console.log("Dalet(1):", cdf1);

        // x=2: 2/√5 ~ 0.8944
        // CDF = (1 + 0.8944)/2 ~ 0.9472
        uint256 cdf2 = DaletCDF.daletCdfFast(false, 2e18);
        assertApproxEqRel(cdf2, 947213595499957939, 1e14, "Dalet(2) ~ 0.9472");
        console.log("Dalet(2):", cdf2);

        // x=0.5: 0.5/√1.25 ~ 0.4472
        // CDF = (1 + 0.4472)/2 ~ 0.7236
        uint256 cdf05 = DaletCDF.daletCdfFast(false, 0.5e18);
        assertApproxEqRel(cdf05, 723606797749978969, 1e14, "Dalet(0.5) ~ 0.7236");
        console.log("Dalet(0.5):", cdf05);
    }

    // ═══════════════════════════════════════════════════════
    // Equivalence: daletCdf == daletCdfFast (within ±1 wei)
    // ═══════════════════════════════════════════════════════

    function test_EquivalencePositive() public pure {
        uint256[8] memory xs = [
            uint256(0.01e18), 0.1e18, 0.5e18, 1e18, 2e18, 3e18, 5e18, 8e18
        ];
        for (uint256 i = 0; i < 8; i++) {
            uint256 geo = DaletCDF.daletCdf(false, xs[i]);
            uint256 fast = DaletCDF.daletCdfFast(false, xs[i]);
            // Two-sqrt route has more rounding; allow 0.01% relative tolerance
            assertApproxEqRel(geo, fast, 1e14, "geometric vs fast mismatch (positive)");
        }
    }

    function test_EquivalenceNegative() public pure {
        uint256[8] memory xs = [
            uint256(0.01e18), 0.1e18, 0.5e18, 1e18, 2e18, 3e18, 5e18, 8e18
        ];
        for (uint256 i = 0; i < 8; i++) {
            uint256 geo = DaletCDF.daletCdf(true, xs[i]);
            uint256 fast = DaletCDF.daletCdfFast(true, xs[i]);
            assertApproxEqRel(geo, fast, 1e14, "geometric vs fast mismatch (negative)");
        }
    }

    // ═══════════════════════════════════════════════════════
    // Comparison with Normal CDF (Dalet has heavier tails)
    // ═══════════════════════════════════════════════════════

    function test_PrintDistribution() public pure {
        console.log("--- Dalet CDF values ---");
        uint256[10] memory xs = [
            uint256(0.1e18), 0.25e18, 0.5e18, 1e18, 1.5e18,
            2e18, 3e18, 4e18, 5e18, 8e18
        ];
        for (uint256 i = 0; i < 10; i++) {
            uint256 pos = DaletCDF.daletCdfFast(false, xs[i]);
            uint256 neg = DaletCDF.daletCdfFast(true, xs[i]);
            console.log("x =", xs[i]);
            console.log("  CDF(+x):", pos);
            console.log("  CDF(-x):", neg);
        }
    }

    // ═══════════════════════════════════════════════════════
    // Gas benchmarks
    // ═══════════════════════════════════════════════════════

    function test_GasBenchmark() public view {
        uint256 g0; uint256 g1; uint256 g2;

        // daletCdf (geometric, 2 sqrt)
        g0 = gasleft();
        DaletCDF.daletCdf(false, 1e18);
        g1 = gasleft();
        console.log("daletCdf(1)    gas:", g0 - g1);

        // daletCdfFast (simplified, 1 sqrt)
        g0 = gasleft();
        DaletCDF.daletCdfFast(false, 1e18);
        g1 = gasleft();
        console.log("daletCdfFast(1) gas:", g0 - g1);

        // daletCdfFast at various x
        g0 = gasleft();
        DaletCDF.daletCdfFast(false, 0.1e18);
        g1 = gasleft();
        console.log("daletCdfFast(0.1) gas:", g0 - g1);

        g0 = gasleft();
        DaletCDF.daletCdfFast(false, 5e18);
        g1 = gasleft();
        console.log("daletCdfFast(5) gas:", g0 - g1);

        g0 = gasleft();
        DaletCDF.daletCdfFast(true, 2e18);
        g1 = gasleft();
        console.log("daletCdfFast(-2) gas:", g0 - g1);
    }
}
