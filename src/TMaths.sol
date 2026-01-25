// SPDX-License-Identifier: UNLICENSED
// © 2025 Tokenisys. All rights reserved.
pragma solidity ^0.8.31;

/// @title TMaths - Gas-efficient mathematical functions in assembly
/// @notice All values scaled by 1e18 (PRECISION)
/// @dev Uses 2^k decomposition + Taylor/Newton-Raphson for optimal gas and accuracy
library TMaths {
    error ZeroInput();
    error ExponentTooLarge();

    // ═══════════════════════════════════════════════════════════════════════════
    // EXPONENTIAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculates e^x using 2^k decomposition + Taylor series
    /// @dev ~200-400 gas, < 0.01% error
    /// @param positive If false, returns e^(-x)
    /// @param exponent The x value, scaled by 1e18
    /// @return result The result, scaled by 1e18
    function exp(
        bool positive,
        uint256 exponent
    ) internal pure returns (uint256 result) {
        assembly {
            // if exponent > 61e18, revert ExponentTooLarge()
            if gt(exponent, 61000000000000000000) {
                mstore(0, 0x4de6e596)
                revert(28, 4)
            }

            // if exponent == 0, return PRECISION
            switch iszero(exponent)
            case 1 {
                result := 1000000000000000000
            }
            default {
                // k = floor(exponent / ln(2))
                // k = (exponent * INV_LN2) / 1e36
                let k := div(
                    mul(exponent, 1442695040888963407),
                    1000000000000000000000000000000000000
                )

                // r = exponent - k * LN2
                let r := sub(exponent, mul(k, 693147180559945309))

                // Taylor series for e^r (unrolled, 6 terms)
                switch iszero(r)
                case 1 {
                    result := 1000000000000000000
                }
                default {
                    // Start with 1 + r
                    result := add(1000000000000000000, r)
                    
                    // term = r² / 2
                    let term := div(mul(r, r), 1000000000000000000)
                    result := add(result, div(term, 2))
                    
                    // term = r³ / 6
                    term := div(mul(term, r), 1000000000000000000)
                    result := add(result, div(term, 6))
                    
                    // term = r⁴ / 24
                    term := div(mul(term, r), 1000000000000000000)
                    result := add(result, div(term, 24))
                    
                    // term = r⁵ / 120
                    term := div(mul(term, r), 1000000000000000000)
                    result := add(result, div(term, 120))
                }

                // Multiply by 2^k
                if gt(k, 0) {
                    result := shl(k, result)
                }

                // Handle negative exponent: result = 1e36 / result
                if iszero(positive) {
                    result := div(1000000000000000000000000000000000000, result)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NATURAL LOGARITHM
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculates ln(x) using 2^k decomposition + Taylor series
    /// @dev ~300-500 gas, < 0.1% error (worst case 8 bps at x=1.5)
    /// @param antilog The x value, scaled by 1e18 (so 2.0 = 2e18)
    /// @return negative True if result is negative (when antilog < 1e18)
    /// @return result The absolute value of the result, scaled by 1e18
    function ln(
        uint256 antilog
    ) internal pure returns (bool negative, uint256 result) {
        assembly {
            // if antilog == 0, revert ZeroInput()
            if iszero(antilog) {
                mstore(0, 0xaf458c07)
                revert(28, 4)
            }

            let precision := 1000000000000000000

            // if antilog == 1e18, return (false, 0) - ln(1) = 0
            switch eq(antilog, precision)
            case 1 {
                negative := 0
                result := 0
            }
            default {
                // Check if antilog < 1e18 (value < 1, result will be negative)
                negative := lt(antilog, precision)

                // If negative, compute reciprocal: 1/x = 1e36 / antilog
                let input := antilog
                if negative {
                    input := div(mul(precision, precision), antilog)
                }

                // Constants
                let ln2 := 693147180559945309

                // log_2 = floor(log2(input))
                let log_2 := sub(255, clz(input))

                // k = log2 of the ACTUAL value = log_2 - 59
                let k := sub(log_2, 59)

                // m = input >> k (remainder after extracting 2^k)
                // m should be in [1e18, 2e18)
                let m := shr(k, input)

                // Edge case: if m >= 2e18, shift once more
                if iszero(lt(m, 2000000000000000000)) {
                    k := add(k, 1)
                    m := shr(k, input)
                }

                // Edge case: if m < 1e18, we shifted too much
                if lt(m, precision) {
                    k := sub(k, 1)
                    m := shr(k, input)
                }

                // If m > 1.5e18, work from 2 downward for better precision
                // ln(m) = ln(2 * (1 - (2-m)/2)) = ln(2) + ln(1 - (2-m)/2)
                let addTaylor := 1
                let x := sub(m, precision)  // x = m - 1e18
                
                if gt(m, 1500000000000000000) {
                    k := add(k, 1)
                    // y = (2e18 - m) / 2 for ln(1 - y) where y is small
                    x := div(sub(2000000000000000000, m), 2)
                    addTaylor := 0
                }

                // Taylor series
                let taylor := 0
                
                switch addTaylor
                case 1 {
                    // ln(1+x) = x - x²/2 + x³/3 - x⁴/4 + x⁵/5 - x⁶/6 + x⁷/7
                    taylor := x

                    let term := div(mul(x, x), precision)
                    taylor := sub(taylor, div(term, 2))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 3))

                    term := div(mul(term, x), precision)
                    taylor := sub(taylor, div(term, 4))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 5))

                    term := div(mul(term, x), precision)
                    taylor := sub(taylor, div(term, 6))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 7))
                }
                default {
                    // ln(1-x) = -x - x²/2 - x³/3 - x⁴/4 - ... (all terms same sign)
                    taylor := x

                    let term := div(mul(x, x), precision)
                    taylor := add(taylor, div(term, 2))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 3))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 4))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 5))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 6))

                    term := div(mul(term, x), precision)
                    taylor := add(taylor, div(term, 7))
                }

                // result = k * ln(2) +/- taylor
                switch addTaylor
                case 1 {
                    result := add(mul(k, ln2), taylor)
                }
                default {
                    result := sub(mul(k, ln2), taylor)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SQUARE ROOT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculates sqrt(x) using 2^k decomposition + Newton-Raphson
    /// @dev ~200-400 gas, 0 bps error
    /// @param x The value to take sqrt of, scaled by 1e18 (so 4e18 = 4.0)
    /// @return result sqrt(x) scaled by 1e18 (so sqrt(4) = 2e18)
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        assembly {
            // if x == 0, revert ZeroInput()
            if iszero(x) {
                mstore(0, 0xaf458c07)
                revert(28, 4)
            }

            let precision := 1000000000000000000

            // if x == 1e18, return 1e18 (sqrt(1) = 1)
            switch eq(x, precision)
            case 1 {
                result := precision
            }
            default {
                let e9 := 1000000000

                // log2 = floor(log2(x))
                let log2_ := sub(255, clz(x))

                // Round to even: if odd, add 1 (go above), else use as is (below)
                let odd := and(log2_, 1)
                let k := add(log2_, odd)
                
                // pow2 = 2^k
                let pow2 := shl(k, 1)

                // ratio in [1, 2) with 1e18 precision
                // if odd (went above): ratio = pow2 * 1e18 / x
                // if even (went below): ratio = x * 1e18 / pow2
                let ratio := 0
                switch odd
                case 1 {
                    ratio := div(mul(pow2, precision), x)
                }
                default {
                    ratio := div(mul(x, precision), pow2)
                }

                // Newton-Raphson for sqrt(ratio) where ratio in [1e18, 2e18)
                // Formula: y_new = (y + ratio/y) / 2
                // Initial guess: 1.5e18 (midpoint of [1, 2])
                let y := 1500000000000000000

                // 4 iterations is enough for full precision
                y := div(add(y, div(mul(ratio, precision), y)), 2)
                y := div(add(y, div(mul(ratio, precision), y)), 2)
                y := div(add(y, div(mul(ratio, precision), y)), 2)
                y := div(add(y, div(mul(ratio, precision), y)), 2)

                // y is now sqrt(ratio) in 1e18 scale
                // half_k = k / 2
                let half_k := shr(1, k)
                let pow2_half := shl(half_k, 1)

                // Recompose:
                // if odd (above): sqrt(x) = 2^(k/2) * 1e18 * 1e9 / sqrt(ratio)
                // if even (below): sqrt(x) = 2^(k/2) * sqrt(ratio) / 1e9
                switch odd
                case 1 {
                    result := div(mul(pow2_half, mul(precision, e9)), y)
                }
                default {
                    result := div(mul(pow2_half, y), e9)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRIGONOMETRY
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculates sin(x) or cos(x) using octant reduction + Taylor series
    /// @dev ~440-690 gas, 5 ppm accuracy
    /// @param x The angle in radians, scaled by 1e18
    /// @param cos If true returns cosine, if false returns sine
    /// @return result The result scaled by 1e18
    /// @return sign True if positive, false if negative
    function trig(uint256 x, bool cos) internal pure returns (uint256 result, bool sign) {
        assembly {
            let precision := 1000000000000000000
            let PI_4 := 785398163397448309
            let PI_2 := 1570796326794896619

            // Default sign to positive
            sign := 1

            // Early exit for x == 0
            switch iszero(x)
            case 1 {
                result := mul(cos, precision)
            }
            default {
                // ═══════════════════════════════════════════════════════════
                // FAST PATH: x < PI/2 (first two octants, always positive)
                // ═══════════════════════════════════════════════════════════
                switch lt(x, PI_2)
                case 1 {
                    // Check if x < PI/4 (first octant)
                    switch lt(x, PI_4)
                    case 1 {
                        // Octant 1: sin uses sin Taylor on x, cos uses cos Taylor on x
                        switch cos
                        case 1 {
                            // cos Taylor: 1 - x²/2 + x⁴/24 - x⁶/720
                            let x2 := div(mul(x, x), precision)
                            result := sub(precision, div(x2, 2))
                            let term := div(mul(x2, x2), precision)
                            result := add(result, div(term, 24))
                            term := div(mul(term, x2), precision)
                            result := sub(result, div(term, 720))
                        }
                        default {
                            // sin Taylor: x - x³/6 + x⁵/120 - x⁷/5040
                            result := x
                            let x2 := div(mul(x, x), precision)
                            let term := div(mul(x2, x), precision)
                            result := sub(result, div(term, 6))
                            term := div(mul(div(mul(term, x), precision), x), precision)
                            result := add(result, div(term, 120))
                            term := div(mul(div(mul(term, x), precision), x), precision)
                            result := sub(result, div(term, 5040))
                        }
                    }
                    default {
                        // Octant 2: x in [PI/4, PI/2)
                        // sin uses cos Taylor on (PI/2 - x), cos uses sin Taylor on (PI/2 - x)
                        let theta := sub(PI_2, x)
                        
                        switch cos
                        case 1 {
                            // cos(x) = sin(PI/2 - x) → sin Taylor
                            result := theta
                            let t2 := div(mul(theta, theta), precision)
                            let term := div(mul(t2, theta), precision)
                            result := sub(result, div(term, 6))
                            term := div(mul(div(mul(term, theta), precision), theta), precision)
                            result := add(result, div(term, 120))
                            term := div(mul(div(mul(term, theta), precision), theta), precision)
                            result := sub(result, div(term, 5040))
                        }
                        default {
                            // sin(x) = cos(PI/2 - x) → cos Taylor
                            let t2 := div(mul(theta, theta), precision)
                            result := sub(precision, div(t2, 2))
                            let term := div(mul(t2, t2), precision)
                            result := add(result, div(term, 24))
                            term := div(mul(term, t2), precision)
                            result := sub(result, div(term, 720))
                        }
                    }
                }
                default {
                    // ═══════════════════════════════════════════════════════════
                    // FULL PATH: x >= PI/2 (need octant reduction and sign logic)
                    // ═══════════════════════════════════════════════════════════
                    
                    // p_x = x * (4/π) - position in octant units
                    let p_x := div(mul(x, 1273239544735162686), precision)

                    // Get octant index (1-8)
                    let r_x := add(div(p_x, precision), 1)

                    // Get theta (position within octant, 0 to 1e18)
                    let theta := sub(p_x, mul(sub(r_x, 1), precision))

                    // Convert theta to radians (multiply by π/4)
                    theta := div(mul(theta, PI_4), precision)

                    // Determine sign using bit patterns
                    let mask := shl(sub(r_x, 1), 1)
                    let signing := 195  // cos: 11000011
                    if iszero(cos) { signing := 15 }  // sin: 00001111
                    if iszero(and(mask, signing)) { sign := 0 }

                    // Reduce r_x to 1-4 range
                    if gt(r_x, 4) { r_x := sub(r_x, 4) }

                    // Determine Taylor series: cos uses 1001 (9), sin uses 0110 (6)
                    let layout := 9
                    if iszero(cos) { layout := 6 }
                    let taylor := and(shl(sub(r_x, 1), 1), layout)

                    // Boundary case: theta ≈ 0
                    switch iszero(theta)
                    case 1 {
                        result := mul(iszero(iszero(taylor)), precision)
                    }
                    default {
                        // Invert theta for even octants
                        if iszero(and(r_x, 1)) {
                            theta := sub(PI_4, theta)
                        }

                        switch iszero(taylor)
                        case 1 {
                            // Taylor sin: x - x³/6 + x⁵/120 - x⁷/5040
                            result := theta
                            let theta2 := div(mul(theta, theta), precision)
                            let term := div(mul(theta2, theta), precision)
                            result := sub(result, div(term, 6))
                            term := div(mul(div(mul(term, theta), precision), theta), precision)
                            result := add(result, div(term, 120))
                            term := div(mul(div(mul(term, theta), precision), theta), precision)
                            result := sub(result, div(term, 5040))
                        }
                        default {
                            // Taylor cos: 1 - x²/2 + x⁴/24 - x⁶/720
                            let theta2 := div(mul(theta, theta), precision)
                            result := sub(precision, div(theta2, 2))
                            let term := div(mul(theta2, theta2), precision)
                            result := add(result, div(term, 24))
                            term := div(mul(term, theta2), precision)
                            result := sub(result, div(term, 720))
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONVENIENCE WRAPPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculates sin(x)
    /// @param x The angle in radians, scaled by 1e18
    /// @return result The result scaled by 1e18
    /// @return sign True if positive, false if negative
    function sin(uint256 x) internal pure returns (uint256 result, bool sign) {
        return trig(x, false);
    }

    /// @notice Calculates cos(x)
    /// @param x The angle in radians, scaled by 1e18
    /// @return result The result scaled by 1e18
    /// @return sign True if positive, false if negative
    function cos(uint256 x) internal pure returns (uint256 result, bool sign) {
        return trig(x, true);
    }

    /// @notice Calculates tan(x) = sin(x) / cos(x)
    /// @param x The angle in radians, scaled by 1e18
    /// @return result The result scaled by 1e18
    /// @return sign True if positive, false if negative
    function tan(uint256 x) internal pure returns (uint256 result, bool sign) {
        (uint256 sinVal, bool sinSign) = trig(x, false);
        (uint256 cosVal, bool cosSign) = trig(x, true);
        
        // tan = sin / cos
        result = (sinVal * 1e18) / cosVal;
        // Sign: positive if both same sign, negative if different
        sign = (sinSign == cosSign);
    }

    /// @notice Calculates sin²(x) using identity: sin²(x) = (1 - cos(2x)) / 2
    /// @dev More efficient than sin(x)² - single trig call
    /// @param x The angle in radians, scaled by 1e18
    /// @return result The result scaled by 1e18 (always positive)
    function sin_sq(uint256 x) internal pure returns (uint256 result) {
        // cos(2x)
        (uint256 cos2x, bool sign) = trig(2 * x, true);
        
        // sin²(x) = (1 - cos(2x)) / 2
        if (sign) {
            // cos2x positive: (1e18 - cos2x) / 2
            result = (1e18 - cos2x) / 2;
        } else {
            // cos2x negative: (1e18 + cos2x) / 2
            result = (1e18 + cos2x) / 2;
        }
    }

    /// @notice Calculates cos²(x) using identity: cos²(x) = (1 + cos(2x)) / 2
    /// @dev More efficient than cos(x)² - single trig call
    /// @param x The angle in radians, scaled by 1e18
    /// @return result The result scaled by 1e18 (always positive)
    function cos_sq(uint256 x) internal pure returns (uint256 result) {
        // cos(2x)
        (uint256 cos2x, bool sign) = trig(2 * x, true);
        
        // cos²(x) = (1 + cos(2x)) / 2
        if (sign) {
            // cos2x positive: (1e18 + cos2x) / 2
            result = (1e18 + cos2x) / 2;
        } else {
            // cos2x negative: (1e18 - cos2x) / 2
            result = (1e18 - cos2x) / 2;
        }
    }
}
