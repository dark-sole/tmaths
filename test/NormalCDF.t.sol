// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {NormalCDF} from "../src/NormalCDF.sol";

// Wrapper for gas measurement with runtime values
contract NormalCDFWrapper {
    function normalCdf(bool negative, uint256 x) external pure returns (uint256) {
        return NormalCDF.normalCdf(negative, x);
    }

    function measureGas(bool negative, uint256 x) external view returns (uint256 gasUsed, uint256 result) {
        uint256 g = gasleft();
        result = NormalCDF.normalCdf(negative, x);
        gasUsed = g - gasleft();
    }
}

contract NormalCDFTest is Test {
    uint256 constant PRECISION = 1e18;
    NormalCDFWrapper wrapper;

    // ─── Known values of Φ(x) scaled by 1e18 ───
    uint256 constant PHI_0     = 500000000000000000;   // Φ(0)    = 0.5
    uint256 constant PHI_0_1   = 539827837277028992;   // Φ(0.1)
    uint256 constant PHI_0_5   = 691462461274013056;   // Φ(0.5)
    uint256 constant PHI_1     = 841344746068542976;   // Φ(1)
    uint256 constant PHI_1_5   = 933192798731141888;   // Φ(1.5)
    uint256 constant PHI_2     = 977249868051820800;   // Φ(2)
    uint256 constant PHI_2_5   = 993790334674223872;   // Φ(2.5)
    uint256 constant PHI_3     = 998650101968369920;   // Φ(3)
    uint256 constant PHI_NEG1  = 158655253931457088;   // Φ(-1)
    uint256 constant PHI_NEG2  =  22750131948179208;   // Φ(-2)

    function setUp() public {
        wrapper = new NormalCDFWrapper();
    }

    // ═══════════════════════════════════════════════════════
    // Basic correctness
    // ═══════════════════════════════════════════════════════

    function test_PhiZero() public pure {
        uint256 result = NormalCDF.normalCdf(false, 0);
        assertEq(result, PHI_0, "Phi(0) should be exactly 0.5");
    }

    function test_PhiPointOne() public pure {
        uint256 result = NormalCDF.normalCdf(false, 1e17);
        assertApproxEqRel(result, PHI_0_1, 5e12, "Phi(0.1) ~0.5398");
    }

    function test_PhiHalf() public pure {
        uint256 result = NormalCDF.normalCdf(false, 5e17);
        assertApproxEqRel(result, PHI_0_5, 5e12, "Phi(0.5) ~0.6915");
    }

    function test_PhiOne() public pure {
        uint256 result = NormalCDF.normalCdf(false, 1e18);
        assertApproxEqRel(result, PHI_1, 5e12, "Phi(1) ~0.8413");
    }

    function test_PhiOnePointFive() public pure {
        uint256 result = NormalCDF.normalCdf(false, 15e17);
        assertApproxEqRel(result, PHI_1_5, 5e12, "Phi(1.5) ~0.9332");
    }

    function test_PhiTwo() public pure {
        uint256 result = NormalCDF.normalCdf(false, 2e18);
        assertApproxEqRel(result, PHI_2, 5e12, "Phi(2) ~0.9772");
    }

    function test_PhiTwoPointFive() public pure {
        uint256 result = NormalCDF.normalCdf(false, 25e17);
        assertApproxEqRel(result, PHI_2_5, 5e12, "Phi(2.5) ~0.9938");
    }

    function test_PhiThree() public pure {
        uint256 result = NormalCDF.normalCdf(false, 3e18);
        assertApproxEqRel(result, PHI_3, 5e12, "Phi(3) ~0.9987");
    }

    // ═══════════════════════════════════════════════════════
    // Negative inputs
    // ═══════════════════════════════════════════════════════

    function test_PhiNegOne() public pure {
        uint256 result = NormalCDF.normalCdf(true, 1e18);
        // Wider tolerance for tail: 5-term exp truncation amplifies on small values
        assertApproxEqRel(result, PHI_NEG1, 15e12, "Phi(-1) ~0.1587");
    }

    function test_PhiNegTwo() public pure {
        uint256 result = NormalCDF.normalCdf(true, 2e18);
        // Wider tolerance for deep tail (small values amplify relative error)
        assertApproxEqRel(result, PHI_NEG2, 50e12, "Phi(-2) ~0.0228");
    }

    // ═══════════════════════════════════════════════════════
    // Symmetry: Φ(x) + Φ(-x) = 1
    // ═══════════════════════════════════════════════════════

    function test_SymmetryHalf() public pure {
        uint256 pos = NormalCDF.normalCdf(false, 5e17);
        uint256 neg = NormalCDF.normalCdf(true, 5e17);
        assertEq(pos + neg, PRECISION, "Phi(0.5) + Phi(-0.5) = 1");
    }

    function test_SymmetryOne() public pure {
        uint256 pos = NormalCDF.normalCdf(false, 1e18);
        uint256 neg = NormalCDF.normalCdf(true, 1e18);
        assertEq(pos + neg, PRECISION, "Phi(1) + Phi(-1) = 1");
    }

    function test_SymmetryTwo() public pure {
        uint256 pos = NormalCDF.normalCdf(false, 2e18);
        uint256 neg = NormalCDF.normalCdf(true, 2e18);
        assertEq(pos + neg, PRECISION, "Phi(2) + Phi(-2) = 1");
    }

    function test_SymmetryThree() public pure {
        uint256 pos = NormalCDF.normalCdf(false, 3e18);
        uint256 neg = NormalCDF.normalCdf(true, 3e18);
        assertEq(pos + neg, PRECISION, "Phi(3) + Phi(-3) = 1");
    }

    // ═══════════════════════════════════════════════════════
    // Edge cases
    // ═══════════════════════════════════════════════════════

    function test_VerySmallPositive() public pure {
        uint256 result = NormalCDF.normalCdf(false, 1e15); // 0.001
        assertGt(result, PHI_0, "Phi(0.001) > 0.5");
        assertLt(result, 501000000000000000, "Phi(0.001) < 0.501");
    }

    function test_LargePositive() public pure {
        uint256 result = NormalCDF.normalCdf(false, 5e18);
        assertGt(result, 999000000000000000, "Phi(5) > 0.999");
    }

    function test_ClampedToOne() public pure {
        uint256 result = NormalCDF.normalCdf(false, 9e18);
        assertEq(result, PRECISION, "Phi(9) = 1.0");
    }

    function test_ClampedToZero() public pure {
        uint256 result = NormalCDF.normalCdf(true, 9e18);
        assertEq(result, 0, "Phi(-9) = 0");
    }

    // ═══════════════════════════════════════════════════════
    // Monotonicity
    // ═══════════════════════════════════════════════════════

    function test_Monotonicity() public pure {
        uint256 prev = 0;
        for (uint256 i = 0; i <= 40; i++) {
            uint256 xi = i * 1e17; // 0.0 to 4.0 in steps of 0.1
            uint256 result = NormalCDF.normalCdf(false, xi);
            assertGe(result, prev, "CDF must be non-decreasing");
            prev = result;
        }
    }

    // ═══════════════════════════════════════════════════════
    // Accuracy report
    // ═══════════════════════════════════════════════════════

    function test_AccuracyReport() public pure {
        uint256[8] memory inputs   = [uint256(1e17), 5e17, 1e18, 15e17, 2e18, 25e17, 3e18, 5e18];
        uint256[8] memory expected = [PHI_0_1, PHI_0_5, PHI_1, PHI_1_5, PHI_2, PHI_2_5, PHI_3,
                                      999999713348428160];
        string[8] memory labels    = ["0.1", "0.5", "1.0", "1.5", "2.0", "2.5", "3.0", "5.0"];

        console.log("--- Normal CDF Accuracy Report ---");
        for (uint256 i = 0; i < 8; i++) {
            uint256 result = NormalCDF.normalCdf(false, inputs[i]);
            uint256 diff = result > expected[i]
                ? result - expected[i]
                : expected[i] - result;
            uint256 ppm = diff * 1e6 / expected[i];
            console.log("Phi(%s): result=%d  error=%d ppm", labels[i], result, ppm);
        }
    }

    // ═══════════════════════════════════════════════════════
    // Gas benchmarks (via wrapper)
    // ═══════════════════════════════════════════════════════

    function test_GasPhiZero() public view {
        wrapper.normalCdf(false, 0);
    }

    function test_GasPhiOne() public view {
        wrapper.normalCdf(false, 1e18);
    }

    function test_GasPhiTwo() public view {
        wrapper.normalCdf(false, 2e18);
    }

    function test_GasPhiThree() public view {
        wrapper.normalCdf(false, 3e18);
    }

    function test_GasPhiNegOne() public view {
        wrapper.normalCdf(true, 1e18);
    }

    function test_GasPhiSmall() public view {
        wrapper.normalCdf(false, 1e15);
    }

    function test_GasPhiLarge() public view {
        wrapper.normalCdf(false, 5e18);
    }

    function test_GasPhiClamped() public view {
        wrapper.normalCdf(false, 9e18);
    }

    // ═══════════════════════════════════════════════════════
    // Precise gas measurement (gasleft)
    // ═══════════════════════════════════════════════════════

    function test_GasMeasurement() public view {
        (uint256 g0,)   = wrapper.measureGas(false, 0);
        (uint256 g05,)  = wrapper.measureGas(false, 5e17);
        (uint256 g1,)   = wrapper.measureGas(false, 1e18);
        (uint256 g2,)   = wrapper.measureGas(false, 2e18);
        (uint256 g3,)   = wrapper.measureGas(false, 3e18);
        (uint256 g5,)   = wrapper.measureGas(false, 5e18);
        (uint256 gn1,)  = wrapper.measureGas(true, 1e18);
        (uint256 gs,)   = wrapper.measureGas(false, 1e15);
        (uint256 gc,)   = wrapper.measureGas(false, 9e18);

        console.log("--- NormalCDF Gas (gasleft) ---");
        console.log("Phi(0):     %d gas", g0);
        console.log("Phi(0.5):   %d gas", g05);
        console.log("Phi(1):     %d gas", g1);
        console.log("Phi(2):     %d gas", g2);
        console.log("Phi(3):     %d gas", g3);
        console.log("Phi(5):     %d gas", g5);
        console.log("Phi(-1):    %d gas", gn1);
        console.log("Phi(0.001): %d gas", gs);
        console.log("Phi(9):     %d gas (clamped)", gc);
    }
}
