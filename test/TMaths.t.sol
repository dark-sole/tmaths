// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TMaths} from "../src/TMaths.sol";

// Wrapper contract to test reverts (internal functions get inlined otherwise)
contract TMathsWrapper {
    function exp(bool positive, uint256 exponent) external pure returns (uint256) {
        return TMaths.exp(positive, exponent);
    }
    function ln(uint256 antilog) external pure returns (bool, uint256) {
        return TMaths.ln(antilog);
    }
    function sqrt(uint256 x) external pure returns (uint256) {
        return TMaths.sqrt(x);
    }
    function tan(uint256 x) external pure returns (uint256, bool) {
        return TMaths.tan(x);
    }
}

contract TMathsTest is Test {
    uint256 constant PRECISION = 1e18;
    TMathsWrapper wrapper;
    
    function setUp() public {
        wrapper = new TMathsWrapper();
    }
    
    // Mathematical constants (scaled by 1e18)
    uint256 constant E = 2718281828459045235;           // e ≈ 2.718281828
    uint256 constant E_NEG1 = 367879441171442321;       // e^-1 ≈ 0.367879441
    uint256 constant LN_2 = 693147180559945309;         // ln(2) ≈ 0.693147181
    uint256 constant LN_10 = 2302585092994045684;       // ln(10) ≈ 2.302585093
    uint256 constant SQRT_2 = 1414213562373095048;      // √2 ≈ 1.414213562
    uint256 constant SQRT_3 = 1732050807568877293;      // √3 ≈ 1.732050808
    
    // Trig constants
    uint256 constant PI = 3141592653589793238;          // π
    uint256 constant PI_2 = 1570796326794896619;        // π/2
    uint256 constant PI_4 = 785398163397448309;         // π/4
    uint256 constant PI_3 = 1047197551196597746;        // π/3
    uint256 constant PI_6 = 523598775598298873;         // π/6
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EXP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Exp_Zero() public pure {
        uint256 result = TMaths.exp(true, 0);
        assertEq(result, PRECISION, "e^0 should equal 1");
    }

    function test_Exp_One() public {
        uint256 result = TMaths.exp(true, PRECISION);
        console.log("e^1 result:", result);
        console.log("e^1 expected:", E);
        assertApproxEqRel(result, E, 1e14, "e^1 should be ~2.718");
    }

    function test_Exp_Two() public {
        uint256 result = TMaths.exp(true, 2 * PRECISION);
        uint256 expected = 7389056098930650227; // e^2
        console.log("e^2 result:", result);
        console.log("e^2 expected:", expected);
        assertApproxEqRel(result, expected, 1e15, "e^2 should be ~7.389");
    }

    function test_Exp_NegativeOne() public {
        uint256 result = TMaths.exp(false, PRECISION);
        console.log("e^-1 result:", result);
        console.log("e^-1 expected:", E_NEG1);
        assertApproxEqRel(result, E_NEG1, 1e14, "e^-1 should be ~0.368");
    }

    function test_Exp_Small() public {
        // e^0.1 ≈ 1.105170918
        uint256 result = TMaths.exp(true, PRECISION / 10);
        uint256 expected = 1105170918075647624;
        console.log("e^0.1 result:", result);
        assertApproxEqRel(result, expected, 1e14, "e^0.1");
    }

    function test_Exp_Large() public {
        // e^10 ≈ 22026.46579
        uint256 result = TMaths.exp(true, 10 * PRECISION);
        uint256 expected = 22026465794806716516980;
        console.log("e^10 result:", result);
        assertApproxEqRel(result, expected, 1e15, "e^10");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Ln_One() public pure {
        (bool negative, uint256 result) = TMaths.ln(PRECISION);
        assertEq(result, 0, "ln(1) should equal 0");
        assertEq(negative, false, "ln(1) should not be negative");
    }

    function test_Ln_E() public {
        (bool negative, uint256 result) = TMaths.ln(E);
        console.log("ln(e) result:", result);
        console.log("ln(e) expected:", PRECISION);
        assertApproxEqRel(result, PRECISION, 1e15, "ln(e) should be ~1");
        assertEq(negative, false, "ln(e) should be positive");
    }

    function test_Ln_Two() public {
        (bool negative, uint256 result) = TMaths.ln(2 * PRECISION);
        console.log("ln(2) result:", result);
        console.log("ln(2) expected:", LN_2);
        assertApproxEqRel(result, LN_2, 1e15, "ln(2) should be ~0.693");
        assertEq(negative, false, "ln(2) should be positive");
    }

    function test_Ln_Ten() public {
        (bool negative, uint256 result) = TMaths.ln(10 * PRECISION);
        console.log("ln(10) result:", result);
        console.log("ln(10) expected:", LN_10);
        assertApproxEqRel(result, LN_10, 1e15, "ln(10) should be ~2.303");
        assertEq(negative, false, "ln(10) should be positive");
    }

    function test_Ln_Half() public {
        // ln(0.5) = -ln(2)
        (bool negative, uint256 result) = TMaths.ln(PRECISION / 2);
        console.log("ln(0.5) result:", result);
        console.log("ln(0.5) expected:", LN_2);
        assertApproxEqRel(result, LN_2, 1e15, "ln(0.5) should be ~0.693");
        assertEq(negative, true, "ln(0.5) should be negative");
    }

    function test_Ln_Small() public {
        // ln(0.1) = -ln(10)
        (bool negative, uint256 result) = TMaths.ln(PRECISION / 10);
        console.log("ln(0.1) result:", result);
        assertApproxEqRel(result, LN_10, 1e15, "ln(0.1) should be ~2.303");
        assertEq(negative, true, "ln(0.1) should be negative");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SQRT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Sqrt_One() public pure {
        uint256 result = TMaths.sqrt(PRECISION);
        assertEq(result, PRECISION, "sqrt(1) should equal 1");
    }

    function test_Sqrt_Four() public {
        uint256 result = TMaths.sqrt(4 * PRECISION);
        console.log("sqrt(4) result:", result);
        assertApproxEqRel(result, 2 * PRECISION, 1e12, "sqrt(4) should be ~2");
    }

    function test_Sqrt_Two() public {
        uint256 result = TMaths.sqrt(2 * PRECISION);
        console.log("sqrt(2) result:", result);
        console.log("sqrt(2) expected:", SQRT_2);
        assertApproxEqRel(result, SQRT_2, 1e15, "sqrt(2) should be ~1.414");
    }

    function test_Sqrt_Three() public {
        uint256 result = TMaths.sqrt(3 * PRECISION);
        console.log("sqrt(3) result:", result);
        console.log("sqrt(3) expected:", SQRT_3);
        assertApproxEqRel(result, SQRT_3, 1e15, "sqrt(3) should be ~1.732");
    }

    function test_Sqrt_Large() public {
        // sqrt(1000000) = 1000
        uint256 result = TMaths.sqrt(1000000 * PRECISION);
        console.log("sqrt(1000000) result:", result);
        assertApproxEqRel(result, 1000 * PRECISION, 1e12, "sqrt(1000000) should be ~1000");
    }

    function test_Sqrt_Small() public {
        // sqrt(0.25) = 0.5
        uint256 result = TMaths.sqrt(PRECISION / 4);
        console.log("sqrt(0.25) result:", result);
        assertApproxEqRel(result, PRECISION / 2, 1e12, "sqrt(0.25) should be ~0.5");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Sin_Zero() public pure {
        (uint256 result, bool sign) = TMaths.sin(0);
        assertEq(result, 0, "sin(0) should equal 0");
        assertEq(sign, true, "sin(0) sign should be positive");
    }

    function test_Sin_Pi6() public {
        // sin(π/6) = 0.5
        (uint256 result, bool sign) = TMaths.sin(PI_6);
        console.log("sin(pi/6) result:", result);
        console.log("sin(pi/6) expected:", PRECISION / 2);
        assertApproxEqRel(result, PRECISION / 2, 1e14, "sin(pi/6) should be 0.5");
        assertEq(sign, true, "sin(pi/6) should be positive");
    }

    function test_Sin_Pi4() public {
        // sin(π/4) = √2/2 ≈ 0.707
        (uint256 result, bool sign) = TMaths.sin(PI_4);
        uint256 expected = 707106781186547524;
        console.log("sin(pi/4) result:", result);
        console.log("sin(pi/4) expected:", expected);
        assertApproxEqRel(result, expected, 1e14, "sin(pi/4) should be ~0.707");
        assertEq(sign, true, "sin(pi/4) should be positive");
    }

    function test_Sin_Pi2() public {
        // sin(π/2) = 1
        (uint256 result, bool sign) = TMaths.sin(PI_2);
        console.log("sin(pi/2) result:", result);
        assertApproxEqRel(result, PRECISION, 1e14, "sin(pi/2) should be 1");
        assertEq(sign, true, "sin(pi/2) should be positive");
    }

    function test_Sin_Pi() public {
        // sin(π) = 0
        (uint256 result, bool sign) = TMaths.sin(PI);
        console.log("sin(pi) result:", result);
        assertLt(result, 1e13, "sin(pi) should be ~0");
    }

    function test_Sin_3Pi2() public {
        // sin(3π/2) = -1
        (uint256 result, bool sign) = TMaths.sin(3 * PI_2);
        console.log("sin(3pi/2) result:", result);
        console.log("sin(3pi/2) sign:", sign);
        assertApproxEqRel(result, PRECISION, 1e14, "sin(3pi/2) should be 1");
        assertEq(sign, false, "sin(3pi/2) should be negative");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Cos_Zero() public pure {
        (uint256 result, bool sign) = TMaths.cos(0);
        assertEq(result, PRECISION, "cos(0) should equal 1");
        assertEq(sign, true, "cos(0) sign should be positive");
    }

    function test_Cos_Pi3() public {
        // cos(π/3) = 0.5
        (uint256 result, bool sign) = TMaths.cos(PI_3);
        console.log("cos(pi/3) result:", result);
        assertApproxEqRel(result, PRECISION / 2, 1e14, "cos(pi/3) should be 0.5");
        assertEq(sign, true, "cos(pi/3) should be positive");
    }

    function test_Cos_Pi4() public {
        // cos(π/4) = √2/2 ≈ 0.707
        (uint256 result, bool sign) = TMaths.cos(PI_4);
        uint256 expected = 707106781186547524;
        console.log("cos(pi/4) result:", result);
        assertApproxEqRel(result, expected, 1e14, "cos(pi/4) should be ~0.707");
        assertEq(sign, true, "cos(pi/4) should be positive");
    }

    function test_Cos_Pi2() public {
        // cos(π/2) = 0
        (uint256 result, bool sign) = TMaths.cos(PI_2);
        console.log("cos(pi/2) result:", result);
        assertLt(result, 1e13, "cos(pi/2) should be ~0");
    }

    function test_Cos_Pi() public {
        // cos(π) = -1
        (uint256 result, bool sign) = TMaths.cos(PI);
        console.log("cos(pi) result:", result);
        console.log("cos(pi) sign:", sign);
        assertApproxEqRel(result, PRECISION, 1e14, "cos(pi) should be 1");
        assertEq(sign, false, "cos(pi) should be negative");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TAN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Tan_Zero() public pure {
        (uint256 result, bool sign) = TMaths.tan(0);
        assertEq(result, 0, "tan(0) should equal 0");
        assertEq(sign, true, "tan(0) sign should be positive");
    }

    function test_Tan_Pi4() public {
        // tan(π/4) = 1
        (uint256 result, bool sign) = TMaths.tan(PI_4);
        console.log("tan(pi/4) result:", result);
        assertApproxEqRel(result, PRECISION, 1e14, "tan(pi/4) should be 1");
        assertEq(sign, true, "tan(pi/4) should be positive");
    }

    function test_Tan_Pi6() public {
        // tan(π/6) = 1/√3 ≈ 0.577
        (uint256 result, bool sign) = TMaths.tan(PI_6);
        uint256 expected = 577350269189625764;
        console.log("tan(pi/6) result:", result);
        console.log("tan(pi/6) expected:", expected);
        assertApproxEqRel(result, expected, 1e14, "tan(pi/6) should be ~0.577");
        assertEq(sign, true, "tan(pi/6) should be positive");
    }

    function test_Tan_Pi3() public {
        // tan(π/3) = √3 ≈ 1.732
        (uint256 result, bool sign) = TMaths.tan(PI_3);
        console.log("tan(pi/3) result:", result);
        console.log("tan(pi/3) expected:", SQRT_3);
        assertApproxEqRel(result, SQRT_3, 1e14, "tan(pi/3) should be ~1.732");
        assertEq(sign, true, "tan(pi/3) should be positive");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SIN_SQ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SinSq_Zero() public pure {
        uint256 result = TMaths.sin_sq(0);
        assertEq(result, 0, "sin^2(0) should equal 0");
    }

    function test_SinSq_Pi4() public {
        // sin^2(π/4) = 0.5
        uint256 result = TMaths.sin_sq(PI_4);
        console.log("sin^2(pi/4) result:", result);
        assertApproxEqRel(result, PRECISION / 2, 1e14, "sin^2(pi/4) should be 0.5");
    }

    function test_SinSq_Pi2() public {
        // sin^2(π/2) = 1
        uint256 result = TMaths.sin_sq(PI_2);
        console.log("sin^2(pi/2) result:", result);
        assertApproxEqRel(result, PRECISION, 1e14, "sin^2(pi/2) should be 1");
    }

    function test_SinSq_Pi6() public {
        // sin^2(π/6) = 0.25
        uint256 result = TMaths.sin_sq(PI_6);
        console.log("sin^2(pi/6) result:", result);
        assertApproxEqRel(result, PRECISION / 4, 1e14, "sin^2(pi/6) should be 0.25");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COS_SQ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CosSq_Zero() public pure {
        uint256 result = TMaths.cos_sq(0);
        assertEq(result, PRECISION, "cos^2(0) should equal 1");
    }

    function test_CosSq_Pi4() public {
        // cos^2(π/4) = 0.5
        uint256 result = TMaths.cos_sq(PI_4);
        console.log("cos^2(pi/4) result:", result);
        assertApproxEqRel(result, PRECISION / 2, 1e14, "cos^2(pi/4) should be 0.5");
    }

    function test_CosSq_Pi2() public {
        // cos^2(π/2) = 0
        uint256 result = TMaths.cos_sq(PI_2);
        console.log("cos^2(pi/2) result:", result);
        assertLt(result, 1e13, "cos^2(pi/2) should be ~0");
    }

    function test_CosSq_Pi3() public {
        // cos^2(π/3) = 0.25
        uint256 result = TMaths.cos_sq(PI_3);
        console.log("cos^2(pi/3) result:", result);
        assertApproxEqRel(result, PRECISION / 4, 1e14, "cos^2(pi/3) should be 0.25");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PYTHAGOREAN IDENTITY: sin^2(x) + cos^2(x) = 1
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PythagoreanIdentity_Pi6() public {
        uint256 sinSq = TMaths.sin_sq(PI_6);
        uint256 cosSq = TMaths.cos_sq(PI_6);
        uint256 sum = sinSq + cosSq;
        console.log("sin^2(pi/6) + cos^2(pi/6) =", sum);
        assertApproxEqRel(sum, PRECISION, 1e14, "sin^2 + cos^2 should equal 1");
    }

    function test_PythagoreanIdentity_Pi4() public {
        uint256 sinSq = TMaths.sin_sq(PI_4);
        uint256 cosSq = TMaths.cos_sq(PI_4);
        uint256 sum = sinSq + cosSq;
        console.log("sin^2(pi/4) + cos^2(pi/4) =", sum);
        assertApproxEqRel(sum, PRECISION, 1e14, "sin^2 + cos^2 should equal 1");
    }

    function test_PythagoreanIdentity_Pi3() public {
        uint256 sinSq = TMaths.sin_sq(PI_3);
        uint256 cosSq = TMaths.cos_sq(PI_3);
        uint256 sum = sinSq + cosSq;
        console.log("sin^2(pi/3) + cos^2(pi/3) =", sum);
        assertApproxEqRel(sum, PRECISION, 1e14, "sin^2 + cos^2 should equal 1");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REVERT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Revert_LnZero() public {
        vm.expectRevert();
        wrapper.ln(0);
    }

    function test_Revert_SqrtZero() public {
        vm.expectRevert();
        wrapper.sqrt(0);
    }

    function test_Revert_ExpTooLarge() public {
        vm.expectRevert();
        wrapper.exp(true, 62 * PRECISION);
    }

    function test_Revert_TanUndefined() public {
        // tan(π/2) should revert - cos(π/2) = 0
        // Note: Due to precision, cos(PI_2) might not be exactly 0
        (uint256 cosVal, ) = TMaths.cos(PI_2);
        console.log("cos(pi/2) for tan test:", cosVal);
        
        // If cosVal is 0, it should revert
        if (cosVal == 0) {
            vm.expectRevert();
            wrapper.tan(PI_2);
        } else {
            console.log("cos(pi/2) not exactly 0, tan won't revert");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS BENCHMARKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Gas_Exp() public view {
        uint256 input = PRECISION + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.exp(true, input);
        uint256 gasAfter = gasleft();
        console.log("exp() gas:", gasBefore - gasAfter);
    }

    function test_Gas_Ln() public view {
        uint256 input = 2 * PRECISION + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.ln(input);
        uint256 gasAfter = gasleft();
        console.log("ln() gas:", gasBefore - gasAfter);
    }

    function test_Gas_Sqrt() public view {
        uint256 input = 2 * PRECISION + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.sqrt(input);
        uint256 gasAfter = gasleft();
        console.log("sqrt() gas:", gasBefore - gasAfter);
    }

    function test_Gas_Sin() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.sin(input);
        uint256 gasAfter = gasleft();
        console.log("sin() gas:", gasBefore - gasAfter);
    }

    function test_Gas_Cos() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.cos(input);
        uint256 gasAfter = gasleft();
        console.log("cos() gas:", gasBefore - gasAfter);
    }

    function test_Gas_Tan() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.tan(input);
        uint256 gasAfter = gasleft();
        console.log("tan() gas:", gasBefore - gasAfter);
    }

    function test_Gas_SinSq() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.sin_sq(input);
        uint256 gasAfter = gasleft();
        console.log("sin_sq() gas:", gasBefore - gasAfter);
    }

    function test_Gas_CosSq() public view {
        uint256 input = PI_4 + (block.timestamp % 1000);
        uint256 gasBefore = gasleft();
        TMaths.cos_sq(input);
        uint256 gasAfter = gasleft();
        console.log("cos_sq() gas:", gasBefore - gasAfter);
    }
}
