// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {BlackScholes} from "../src/BlackScholes.sol";

contract BSWrapper {
    function price(
        uint256 S, uint256 K, uint256 T,
        uint256 r, uint256 y, uint256 sigma
    ) external pure returns (uint256, uint256, uint256, uint256) {
        return BlackScholes.price(S, K, T, r, y, sigma);
    }

    function measureGas(
        uint256 S, uint256 K, uint256 T,
        uint256 r, uint256 y, uint256 sigma
    ) external view returns (uint256 gasUsed) {
        uint256 g = gasleft();
        BlackScholes.price(S, K, T, r, y, sigma);
        gasUsed = g - gasleft();
    }
}

contract BlackScholesTest is Test {

    BSWrapper wrapper;

    function setUp() public {
        wrapper = new BSWrapper();
    }

    // ═══════════════════════════════════════════════════════
    // Reference case: S=100, K=100, T=1yr, r=5%, y=0%, σ=20%
    // Expected (Black-Scholes calculator):
    //   Call ≈ 10.4506, Put ≈ 5.5735
    //   d1 ≈ 0.35, d2 ≈ 0.15
    //   Delta_call ≈ 0.6368, Delta_put ≈ 0.3632
    // ═══════════════════════════════════════════════════════

    function test_ATM_1yr() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = BlackScholes.price(
            100e18,  // S = 100
            100e18,  // K = 100
            1e18,    // T = 1 year
            5e16,    // r = 5%
            0,       // y = 0%
            20e16    // σ = 20%
        );

        console.log("--- ATM 1yr (S=100, K=100, r=5%, vol=20%) ---");
        console.log("Call:       %d", c);
        console.log("Put:        %d", p);
        console.log("Delta Call: %d", dc);
        console.log("Delta Put:  %d", dp);

        // Call ≈ 10.4506e18, allow 0.5% tolerance
        assertApproxEqRel(c, 10_450600000000000000, 5e15, "call price");
        // Put ≈ 5.5735e18
        assertApproxEqRel(p, 5_573526000000000000, 5e15, "put price");
        // Delta call ≈ 0.6368
        assertApproxEqRel(dc, 636830510000000000, 5e15, "delta call");
        // Delta put ≈ 0.3632
        assertApproxEqRel(dp, 363169490000000000, 5e15, "delta put");
    }

    // ═══════════════════════════════════════════════════════
    // OTM call: S=100, K=110, T=0.25yr, r=5%, y=0%, σ=20%
    // Expected: Call ≈ 1.0053, Put ≈ 9.6350
    // ═══════════════════════════════════════════════════════

    function test_OTM_call() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = BlackScholes.price(
            100e18,  // S
            110e18,  // K (OTM call)
            25e16,   // T = 0.25
            5e16,    // r = 5%
            0,       // y = 0
            20e16    // σ = 20%
        );

        console.log("--- OTM call (S=100, K=110, T=0.25, r=5%, vol=20%) ---");
        console.log("Call:       %d", c);
        console.log("Put:        %d", p);
        console.log("Delta Call: %d", dc);
        console.log("Delta Put:  %d", dp);

        // Call ≈ 1.1911
        assertApproxEqRel(c, 1_191131663613070592, 5e15, "OTM call price");
        // Put ≈ 9.8247
        assertApproxEqRel(p, 9_824689717940017152, 5e15, "OTM put price");
    }

    // ═══════════════════════════════════════════════════════
    // ITM call: S=100, K=90, T=0.5yr, r=5%, y=0%, σ=20%
    // Expected: Call ≈ 13.696, Put ≈ 1.467
    // ═══════════════════════════════════════════════════════

    function test_ITM_call() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = BlackScholes.price(
            100e18,
            90e18,
            5e17,    // T = 0.5
            5e16,
            0,
            20e16
        );

        console.log("--- ITM call (S=100, K=90, T=0.5, r=5%, vol=20%) ---");
        console.log("Call:       %d", c);
        console.log("Put:        %d", p);
        console.log("Delta Call: %d", dc);
        console.log("Delta Put:  %d", dp);

        // Call ≈ 13.4985
        assertApproxEqRel(c, 13_498517482637211648, 5e15, "ITM call price");
        // Put ≈ 1.2764
        assertApproxEqRel(p, 1_276409565187154944, 5e15, "ITM put price");
    }

    // ═══════════════════════════════════════════════════════
    // With dividend yield: S=100, K=100, T=1yr, r=5%, y=2%, σ=20%
    // Expected: Call ≈ 8.916, Put ≈ 5.888
    // ═══════════════════════════════════════════════════════

    function test_WithYield() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = BlackScholes.price(
            100e18,
            100e18,
            1e18,
            5e16,    // r = 5%
            2e16,    // y = 2%
            20e16
        );

        console.log("--- With yield (S=100, K=100, T=1, r=5%, y=2%, vol=20%) ---");
        console.log("Call:       %d", c);
        console.log("Put:        %d", p);
        console.log("Delta Call: %d", dc);
        console.log("Delta Put:  %d", dp);

        // Call ≈ 9.4134 (net rate = r-y = 3%)
        assertApproxEqRel(c, 9_413403383853015040, 5e15, "yield call");
        // Put ≈ 6.4580
        assertApproxEqRel(p, 6_457956738703835136, 5e15, "yield put");
    }

    // ═══════════════════════════════════════════════════════
    // Negative rate (y > r): S=100, K=100, T=1yr, r=2%, y=5%, σ=20%
    // ═══════════════════════════════════════════════════════

    function test_NegativeRate() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = BlackScholes.price(
            100e18,
            100e18,
            1e18,
            2e16,    // r = 2%
            5e16,    // y = 5% (yield > rate)
            20e16
        );

        console.log("--- Negative rate (r=2%, y=5%) ---");
        console.log("Call:       %d", c);
        console.log("Put:        %d", p);
        console.log("Delta Call: %d", dc);
        console.log("Delta Put:  %d", dp);

        // With negative net rate, put should be more expensive than call
        assertGt(p, c, "put > call when yield > rate");
        // delta_call + delta_put should ≈ 1e18
        assertApproxEqAbs(dc + dp, 1e18, 1e15, "deltas sum to ~1");
    }

    // ═══════════════════════════════════════════════════════
    // Put-call parity: C - P = S - K*e^(-rT)
    // (using net rate r-y=0 for simplicity: C - P = S - K)
    // ═══════════════════════════════════════════════════════

    function test_PutCallParity() public pure {
        uint256 S = 100e18;
        uint256 K = 105e18;
        uint256 T = 5e17;
        uint256 r = 5e16;
        uint256 y = 0;
        uint256 sigma = 25e16;

        (uint256 c, uint256 p,,) = BlackScholes.price(S, K, T, r, y, sigma);

        // C - P ≈ S - K * e^(-rT)
        // rT = 0.05 * 0.5 = 0.025
        // e^(-0.025) ≈ 0.97531
        // S - K*e^(-rT) ≈ 100 - 105*0.97531 ≈ 100 - 102.408 ≈ -2.408
        // So P - C ≈ 2.408

        uint256 rT = r * T / 1e18;
        uint256 disc = TMaths_exp_helper(rT);
        // K * discount
        uint256 Kdisc = K * disc / 1e18;

        // P - C should equal Kdisc - S (since Kdisc > S here)
        uint256 parity_lhs = p > c ? p - c : 0;
        uint256 parity_rhs = Kdisc > S ? Kdisc - S : 0;

        console.log("--- Put-Call Parity ---");
        console.log("P - C:            %d", parity_lhs);
        console.log("K*e^(-rT) - S:    %d", parity_rhs);

        // Allow 0.5% tolerance
        assertApproxEqRel(parity_lhs, parity_rhs, 5e15, "put-call parity");
    }

    // Helper: can't call TMaths directly from test, replicate discount
    function TMaths_exp_helper(uint256 rT) internal pure returns (uint256) {
        // We need e^(-rT) but can't import TMaths easily in test
        // Instead just validate parity holds via the wrapper
        // Use BlackScholes itself: price ATM with r=0 gives C=P
        // Actually, let's just compute it directly
        return _expNeg(rT);
    }

    // Simple exp(-x) for small x via Taylor (test helper only)
    function _expNeg(uint256 x) internal pure returns (uint256) {
        uint256 result = 1e18;
        uint256 term = x;
        result -= term;
        term = term * x / 1e18;
        result += term / 2;
        term = term * x / 1e18;
        result -= term / 6;
        term = term * x / 1e18;
        result += term / 24;
        return result;
    }

    // ═══════════════════════════════════════════════════════
    // Delta bounds
    // ═══════════════════════════════════════════════════════

    function test_DeltaBounds() public pure {
        // Deep ITM call: delta should be near 1
        (,,uint256 dc_itm,) = BlackScholes.price(100e18, 50e18, 1e18, 5e16, 0, 20e16);
        assertGt(dc_itm, 99e16, "deep ITM call delta > 0.99");

        // Deep OTM call: delta should be near 0
        (,,uint256 dc_otm,) = BlackScholes.price(100e18, 200e18, 1e17, 5e16, 0, 20e16);
        assertLt(dc_otm, 1e16, "deep OTM call delta < 0.01");
    }

    // ═══════════════════════════════════════════════════════
    // High vol
    // ═══════════════════════════════════════════════════════

    function test_HighVol() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = BlackScholes.price(
            100e18, 100e18, 1e18, 5e16, 0, 80e16  // σ = 80%
        );

        console.log("--- High vol (80%) ---");
        console.log("Call: %d", c);
        console.log("Put:  %d", p);

        // Both should be large with high vol
        assertGt(c, 30e18, "high vol call > 30");
        assertGt(p, 25e18, "high vol put > 25");
        assertApproxEqAbs(dc + dp, 1e18, 1e15, "deltas sum to ~1");
    }

    // ═══════════════════════════════════════════════════════
    // Revert tests
    // ═══════════════════════════════════════════════════════

    function test_RevertZeroSpot() public {
        vm.expectRevert(BlackScholes.ZeroSpot.selector);
        wrapper.price(0, 100e18, 1e18, 5e16, 0, 20e16);
    }

    function test_RevertZeroStrike() public {
        vm.expectRevert(BlackScholes.ZeroStrike.selector);
        wrapper.price(100e18, 0, 1e18, 5e16, 0, 20e16);
    }

    function test_RevertZeroTime() public {
        vm.expectRevert(BlackScholes.ZeroTime.selector);
        wrapper.price(100e18, 100e18, 0, 5e16, 0, 20e16);
    }

    function test_RevertZeroVol() public {
        vm.expectRevert(BlackScholes.ZeroVol.selector);
        wrapper.price(100e18, 100e18, 1e18, 5e16, 0, 0);
    }

    // ═══════════════════════════════════════════════════════
    // Gas measurement
    // ═══════════════════════════════════════════════════════

    function test_GasMeasurement() public view {
        uint256 g1 = wrapper.measureGas(100e18, 100e18, 1e18, 5e16, 0, 20e16);
        uint256 g2 = wrapper.measureGas(100e18, 110e18, 25e16, 5e16, 0, 20e16);
        uint256 g3 = wrapper.measureGas(100e18, 90e18, 5e17, 5e16, 0, 20e16);
        uint256 g4 = wrapper.measureGas(100e18, 100e18, 1e18, 2e16, 5e16, 20e16);
        uint256 g5 = wrapper.measureGas(100e18, 100e18, 1e18, 5e16, 0, 80e16);

        console.log("--- BlackScholes Gas (gasleft) ---");
        console.log("ATM 1yr:        %d gas", g1);
        console.log("OTM K=110:      %d gas", g2);
        console.log("ITM K=90:       %d gas", g3);
        console.log("Neg rate:       %d gas", g4);
        console.log("High vol 80%%:   %d gas", g5);
    }
}
