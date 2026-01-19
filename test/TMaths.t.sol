// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TMaths} from "../src/TMaths.sol";

contract TMathsWrapper {
    function exp(bool positive, uint256 exponent) external pure returns (uint256) {
        return TMaths.exp(positive, exponent);
    }

    function ln(uint256 antilog) external pure returns (bool negative, uint256 result) {
        return TMaths.ln(antilog);
    }

    function sqrt(uint256 x) external pure returns (uint256) {
        return TMaths.sqrt(x);
    }
}

contract TMathsTest is Test {
    uint256 constant PRECISION = 1e18;
    TMathsWrapper wrapper;

    // Known values scaled by 1e18
    uint256 constant E = 2718281828459045235;           // e
    uint256 constant E_2 = 7389056098930650227;         // e^2
    uint256 constant E_5 = 148413159102576603421;       // e^5
    uint256 constant E_NEG1 = 367879441171442321;       // e^-1
    
    uint256 constant LN_2 = 693147180559945309;         // ln(2)
    uint256 constant LN_E = 1000000000000000000;        // ln(e) = 1
    uint256 constant LN_10 = 2302585092994045684;       // ln(10)

    uint256 constant SQRT_2 = 1414213562373095048;      // sqrt(2)
    uint256 constant SQRT_10 = 3162277660168379331;     // sqrt(10)

    function setUp() public {
        wrapper = new TMathsWrapper();
    }

    // ═══════════════════════════════════════════════════════════════
    // EXP Tests
    // ═══════════════════════════════════════════════════════════════

    function test_ExpZero() public pure {
        uint256 result = TMaths.exp(true, 0);
        assertEq(result, PRECISION, "e^0 should equal 1");
    }

    function test_ExpOne() public pure {
        uint256 result = TMaths.exp(true, 1e18);
        assertApproxEqRel(result, E, 1e14, "e^1 should be ~2.718");
    }

    function test_ExpTwo() public pure {
        uint256 result = TMaths.exp(true, 2e18);
        assertApproxEqRel(result, E_2, 1e15, "e^2 should be ~7.389");
    }

    function test_ExpFive() public pure {
        uint256 result = TMaths.exp(true, 5e18);
        assertApproxEqRel(result, E_5, 1e15, "e^5 should be ~148.413");
    }

    function test_ExpNegOne() public pure {
        uint256 result = TMaths.exp(false, 1e18);
        assertApproxEqRel(result, E_NEG1, 1e14, "e^-1 should be ~0.368");
    }

    function test_ExpRevertTooLarge() public {
        vm.expectRevert(TMaths.ExponentTooLarge.selector);
        wrapper.exp(true, 62e18);
    }

    // ═══════════════════════════════════════════════════════════════
    // LN Tests
    // ═══════════════════════════════════════════════════════════════

    function test_LnOne() public pure {
        (bool neg, uint256 result) = TMaths.ln(1e18);
        assertEq(neg, false);
        assertEq(result, 0, "ln(1) should equal 0");
    }

    function test_LnTwo() public pure {
        (bool neg, uint256 result) = TMaths.ln(2e18);
        assertEq(neg, false);
        assertApproxEqRel(result, LN_2, 1e15, "ln(2) should be ~0.693");
    }

    function test_LnE() public pure {
        (bool neg, uint256 result) = TMaths.ln(E);
        assertEq(neg, false);
        assertApproxEqRel(result, LN_E, 1e15, "ln(e) should be ~1.0");
    }

    function test_LnTen() public pure {
        (bool neg, uint256 result) = TMaths.ln(10e18);
        assertEq(neg, false);
        assertApproxEqRel(result, LN_10, 1e15, "ln(10) should be ~2.303");
    }

    function test_LnHalf() public pure {
        (bool neg, uint256 result) = TMaths.ln(5e17);
        assertEq(neg, true, "ln(0.5) should be negative");
        assertApproxEqRel(result, LN_2, 1e15, "|ln(0.5)| should be ~0.693");
    }

    function test_LnTenth() public pure {
        (bool neg, uint256 result) = TMaths.ln(1e17);
        assertEq(neg, true, "ln(0.1) should be negative");
        assertApproxEqRel(result, LN_10, 1e15, "|ln(0.1)| should be ~2.303");
    }

    function test_LnRevertZero() public {
        vm.expectRevert(TMaths.ZeroInput.selector);
        wrapper.ln(0);
    }

    // ═══════════════════════════════════════════════════════════════
    // Identity Tests: exp(ln(x)) = x and ln(exp(x)) = x
    // ═══════════════════════════════════════════════════════════════

    function test_Identity_ExpLn() public pure {
        // exp(ln(5)) should equal 5
        (bool neg, uint256 lnResult) = TMaths.ln(5e18);
        assertEq(neg, false);
        uint256 expResult = TMaths.exp(true, lnResult);
        assertApproxEqRel(expResult, 5e18, 1e15, "exp(ln(5)) should be ~5");
    }

    function test_Identity_LnExp() public pure {
        // ln(exp(2)) should equal 2
        uint256 expResult = TMaths.exp(true, 2e18);
        (bool neg, uint256 lnResult) = TMaths.ln(expResult);
        assertEq(neg, false);
        assertApproxEqRel(lnResult, 2e18, 1e15, "ln(exp(2)) should be ~2");
    }

    // ═══════════════════════════════════════════════════════════════
    // Boundary Tests (worst case at ratio = 1.5)
    // ═══════════════════════════════════════════════════════════════

    function test_LnBoundary_1_5() public pure {
        (bool neg, uint256 result) = TMaths.ln(15e17);
        uint256 expected = 405465108108164382;
        assertEq(neg, false);
        assertApproxEqRel(result, expected, 1e15, "ln(1.5) boundary");
    }

    function test_LnBoundary_3() public pure {
        (bool neg, uint256 result) = TMaths.ln(3e18);
        uint256 expected = 1098612288668109691;
        assertEq(neg, false);
        assertApproxEqRel(result, expected, 1e15, "ln(3) boundary");
    }

    // ═══════════════════════════════════════════════════════════════
    // SQRT Tests
    // ═══════════════════════════════════════════════════════════════

    function test_SqrtOne() public pure {
        uint256 result = TMaths.sqrt(1e18);
        assertEq(result, PRECISION, "sqrt(1) should equal 1");
    }

    function test_SqrtFour() public pure {
        uint256 result = TMaths.sqrt(4e18);
        assertApproxEqRel(result, 2e18, 1e15, "sqrt(4) should be 2");
    }

    function test_SqrtTwo() public pure {
        uint256 result = TMaths.sqrt(2e18);
        assertApproxEqRel(result, SQRT_2, 1e15, "sqrt(2) should be ~1.414");
    }

    function test_SqrtTen() public pure {
        uint256 result = TMaths.sqrt(10e18);
        assertApproxEqRel(result, SQRT_10, 1e15, "sqrt(10) should be ~3.162");
    }

    function test_SqrtHundred() public pure {
        uint256 result = TMaths.sqrt(100e18);
        assertApproxEqRel(result, 10e18, 1e15, "sqrt(100) should be 10");
    }

    function test_SqrtHalf() public pure {
        uint256 result = TMaths.sqrt(5e17);
        uint256 expected = 707106781186547524; // sqrt(0.5)
        assertApproxEqRel(result, expected, 1e15, "sqrt(0.5) should be ~0.707");
    }

    function test_SqrtRevertZero() public {
        vm.expectRevert(TMaths.ZeroInput.selector);
        wrapper.sqrt(0);
    }

    function test_Identity_SqrtSquared() public pure {
        uint256 x = 7e18;
        uint256 sqrtX = TMaths.sqrt(x);
        uint256 squared = sqrtX * sqrtX / PRECISION;
        assertApproxEqRel(squared, x, 1e15, "sqrt(7)^2 should be ~7");
    }

    // ═══════════════════════════════════════════════════════════════
    // Gas Benchmarks
    // ═══════════════════════════════════════════════════════════════

    function test_Gas_Exp1() public pure {
        TMaths.exp(true, 1e18);
    }

    function test_Gas_Exp5() public pure {
        TMaths.exp(true, 5e18);
    }

    function test_Gas_ExpNeg1() public pure {
        TMaths.exp(false, 1e18);
    }

    function test_Gas_Ln2() public pure {
        TMaths.ln(2e18);
    }

    function test_Gas_Ln10() public pure {
        TMaths.ln(10e18);
    }

    function test_Gas_LnHalf() public pure {
        TMaths.ln(5e17);
    }

    function test_Gas_Sqrt2() public pure {
        TMaths.sqrt(2e18);
    }

    function test_Gas_Sqrt10() public pure {
        TMaths.sqrt(10e18);
    }

    function test_Gas_Sqrt100() public pure {
        TMaths.sqrt(100e18);
    }

    // ═══════════════════════════════════════════════════════════════
    // Accuracy Report
    // ═══════════════════════════════════════════════════════════════

    function test_AccuracyReport() public pure {
        console.log("\n==================== TMaths ACCURACY REPORT ====================\n");
        
        console.log("EXP FUNCTION:");
        console.log("  e^1  error:", _errorBps(TMaths.exp(true, 1e18), E), "bps");
        console.log("  e^2  error:", _errorBps(TMaths.exp(true, 2e18), E_2), "bps");
        console.log("  e^5  error:", _errorBps(TMaths.exp(true, 5e18), E_5), "bps");
        console.log("  e^-1 error:", _errorBps(TMaths.exp(false, 1e18), E_NEG1), "bps");
        
        console.log("\nLN FUNCTION:");
        (, uint256 ln2) = TMaths.ln(2e18);
        (, uint256 lnE) = TMaths.ln(E);
        (, uint256 ln10) = TMaths.ln(10e18);
        (, uint256 ln1_5) = TMaths.ln(15e17);
        
        console.log("  ln(2)   error:", _errorBps(ln2, LN_2), "bps");
        console.log("  ln(e)   error:", _errorBps(lnE, LN_E), "bps");
        console.log("  ln(10)  error:", _errorBps(ln10, LN_10), "bps");
        console.log("  ln(1.5) error:", _errorBps(ln1_5, 405465108108164382), "bps (worst case)");

        console.log("\nSQRT FUNCTION:");
        console.log("  sqrt(2)   error:", _errorBps(TMaths.sqrt(2e18), SQRT_2), "bps");
        console.log("  sqrt(4)   error:", _errorBps(TMaths.sqrt(4e18), 2e18), "bps");
        console.log("  sqrt(10)  error:", _errorBps(TMaths.sqrt(10e18), SQRT_10), "bps");
        console.log("  sqrt(100) error:", _errorBps(TMaths.sqrt(100e18), 10e18), "bps");
        
        console.log("\n================================================================\n");
    }

    function _errorBps(uint256 actual, uint256 expected) internal pure returns (uint256) {
        if (expected == 0) return actual > 0 ? type(uint256).max : 0;
        if (actual > expected) {
            return (actual - expected) * 10000 / expected;
        } else {
            return (expected - actual) * 10000 / expected;
        }
    }
}
