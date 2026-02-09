// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {DaletOption} from "../src/DaletOption.sol";
import {BlackScholes} from "../src/BlackScholes.sol";

contract DaletWrapper {
    function price(
        uint256 S, uint256 K, uint256 T,
        uint256 r, uint256 sigma
    ) external pure returns (uint256, uint256, uint256, uint256) {
        return DaletOption.price(S, K, T, r, sigma);
    }

    function measureGas(
        uint256 S, uint256 K, uint256 T,
        uint256 r, uint256 sigma
    ) external view returns (uint256 gasUsed) {
        uint256 g = gasleft();
        DaletOption.price(S, K, T, r, sigma);
        gasUsed = g - gasleft();
    }
}

contract DaletOptionTest is Test {

    DaletWrapper wrapper;

    function setUp() public {
        wrapper = new DaletWrapper();
    }

    // ═══════════════════════════════════════════════════════
    // ATM: S=100, K=100, T=1yr, r=5%, sigma=20%
    // ═══════════════════════════════════════════════════════

    function test_ATM_1yr() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = DaletOption.price(
            100e18, 100e18, 1e18, 5e16, 20e16
        );

        console.log("--- Dalet ATM 1yr (S=100, K=100, r=5%, vol=20%) ---");
        console.log("Call:       ", c);
        console.log("Put:        ", p);
        console.log("Delta Call: ", dc);
        console.log("Delta Put:  ", dp);

        // Sanity: call > 0, put > 0
        assertGt(c, 0, "call > 0");
        assertGt(p, 0, "put > 0");
        // ATM call > put (positive rates, no dividend)
        assertGt(c, p, "ATM call > put with positive rates");
        // Deltas: call delta > 0.5 for ATM with positive drift
        assertGt(dc, 0.5e18, "delta call > 0.5");
        assertLt(dp, 0.5e18, "delta put < 0.5");
        // Delta call + delta put = 1
        assertEq(dc + dp, 1e18, "delta call + delta put = 1");
    }

    // ═══════════════════════════════════════════════════════
    // OTM call: S=100, K=110
    // ═══════════════════════════════════════════════════════

    function test_OTM_call() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = DaletOption.price(
            100e18, 110e18, 25e16, 5e16, 20e16
        );

        console.log("--- Dalet OTM Call (S=100, K=110, T=0.25, vol=20%) ---");
        console.log("Call:       ", c);
        console.log("Put:        ", p);
        console.log("Delta Call: ", dc);
        console.log("Delta Put:  ", dp);

        // OTM call < ITM put
        assertLt(c, p, "OTM call < put");
        // Call delta < 0.5
        assertLt(dc, 0.5e18, "OTM call delta < 0.5");
    }

    // ═══════════════════════════════════════════════════════
    // ITM call: S=100, K=90
    // ═══════════════════════════════════════════════════════

    function test_ITM_call() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = DaletOption.price(
            100e18, 90e18, 25e16, 5e16, 20e16
        );

        console.log("--- Dalet ITM Call (S=100, K=90, T=0.25, vol=20%) ---");
        console.log("Call:       ", c);
        console.log("Put:        ", p);
        console.log("Delta Call: ", dc);
        console.log("Delta Put:  ", dp);

        // ITM call > intrinsic (S - K = 10)
        assertGt(c, 10e18, "ITM call > intrinsic");
        // Call delta > 0.5
        assertGt(dc, 0.5e18, "ITM call delta > 0.5");
    }

    // ═══════════════════════════════════════════════════════
    // OTM: Dalet should price HIGHER than Black-Scholes
    // (heavier tails => more probability of reaching strike)
    // ═══════════════════════════════════════════════════════

    function test_OTM_FatterTails() public pure {
        // Moderately OTM call: K = 110, 1yr tenor (more time = more tail effect)
        (uint256 c_dalet,,,) = DaletOption.price(
            100e18, 110e18, 1e18, 5e16, 20e16
        );
        (uint256 c_bs,,,) = BlackScholes.price(
            100e18, 110e18, 1e18, 5e16, 0, 20e16
        );

        console.log("--- OTM fat-tail comparison (K=110, T=1yr) ---");
        console.log("Dalet call: ", c_dalet);
        console.log("BS call:    ", c_bs);

        // Dalet's heavier tails should give a higher OTM price
        assertGt(c_dalet, 0, "Dalet OTM call > 0");
        assertGt(c_dalet, c_bs, "Dalet OTM > BS OTM (fat tails)");
    }

    // ═══════════════════════════════════════════════════════
    // Zero rate
    // ═══════════════════════════════════════════════════════

    function test_ZeroRate() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = DaletOption.price(
            100e18, 100e18, 1e18, 0, 20e16
        );

        console.log("--- Dalet Zero Rate (S=K=100, r=0, vol=20%) ---");
        console.log("Call:       ", c);
        console.log("Put:        ", p);
        console.log("Delta Call: ", dc);
        console.log("Delta Put:  ", dp);

        assertGt(c, 0, "call > 0");
        assertGt(p, 0, "put > 0");
    }

    // ═══════════════════════════════════════════════════════
    // High vol: 80%
    // ═══════════════════════════════════════════════════════

    function test_HighVol() public pure {
        (uint256 c, uint256 p, uint256 dc, uint256 dp) = DaletOption.price(
            100e18, 100e18, 1e18, 5e16, 80e16
        );

        console.log("--- Dalet High Vol (ATM, vol=80%) ---");
        console.log("Call:       ", c);
        console.log("Put:        ", p);
        console.log("Delta Call: ", dc);
        console.log("Delta Put:  ", dp);

        // High vol => high option values
        assertGt(c, 20e18, "high vol call > 20");
    }

    // ═══════════════════════════════════════════════════════
    // Put-call relationship check
    // Log-space parity: C_log - P_log = (m+μ)·e^{-rT}
    // After exp conversion to price space, this is approximate.
    // We test that C > P for ATM with positive rates (basic sanity).
    // ═══════════════════════════════════════════════════════

    function test_PutCallRelationship() public pure {
        (uint256 c, uint256 p,,) = DaletOption.price(
            100e18, 100e18, 1e18, 5e16, 20e16
        );

        console.log("Call:       ", c);
        console.log("Put:        ", p);
        console.log("C - P:      ", c - p);

        // With positive rates and S=K, call > put
        assertGt(c, p, "ATM call > put with positive rates");
        // C - P should be positive and less than S
        assertLt(c - p, 100e18, "C - P < S");
    }

    // ═══════════════════════════════════════════════════════
    // Monotonicity in strike
    // ═══════════════════════════════════════════════════════

    function test_CallDecreasingInStrike() public pure {
        uint256 prev_c = type(uint256).max;
        uint256[5] memory strikes = [uint256(90e18), 95e18, 100e18, 105e18, 110e18];

        for (uint256 i = 0; i < 5; i++) {
            (uint256 c,,,) = DaletOption.price(
                100e18, strikes[i], 1e18, 5e16, 20e16
            );
            assertLt(c, prev_c, "call should decrease as strike increases");
            prev_c = c;
        }
    }

    function test_PutIncreasingInStrike() public pure {
        uint256 prev_p = 0;
        uint256[5] memory strikes = [uint256(90e18), 95e18, 100e18, 105e18, 110e18];

        for (uint256 i = 0; i < 5; i++) {
            (,uint256 p,,) = DaletOption.price(
                100e18, strikes[i], 1e18, 5e16, 20e16
            );
            assertGt(p, prev_p, "put should increase as strike increases");
            prev_p = p;
        }
    }

    // ═══════════════════════════════════════════════════════
    // Revert tests
    // ═══════════════════════════════════════════════════════

    function test_RevertZeroSpot() public {
        vm.expectRevert(DaletOption.ZeroSpot.selector);
        wrapper.price(0, 100e18, 1e18, 5e16, 20e16);
    }

    function test_RevertZeroStrike() public {
        vm.expectRevert(DaletOption.ZeroStrike.selector);
        wrapper.price(100e18, 0, 1e18, 5e16, 20e16);
    }

    function test_RevertZeroTime() public {
        vm.expectRevert(DaletOption.ZeroTime.selector);
        wrapper.price(100e18, 100e18, 0, 5e16, 20e16);
    }

    function test_RevertZeroVol() public {
        vm.expectRevert(DaletOption.ZeroVol.selector);
        wrapper.price(100e18, 100e18, 1e18, 5e16, 0);
    }

    // ═══════════════════════════════════════════════════════
    // Gas benchmarks
    // ═══════════════════════════════════════════════════════

    function test_GasBenchmarks() public view {
        uint256 g;

        g = wrapper.measureGas(100e18, 100e18, 1e18, 5e16, 20e16);
        console.log("Dalet ATM 1yr:     ", g, "gas");

        g = wrapper.measureGas(100e18, 110e18, 25e16, 5e16, 20e16);
        console.log("Dalet OTM K=110:   ", g, "gas");

        g = wrapper.measureGas(100e18, 90e18, 25e16, 5e16, 20e16);
        console.log("Dalet ITM K=90:    ", g, "gas");

        g = wrapper.measureGas(100e18, 100e18, 1e18, 0, 20e16);
        console.log("Dalet zero rate:   ", g, "gas");

        g = wrapper.measureGas(100e18, 100e18, 1e18, 5e16, 80e16);
        console.log("Dalet high vol:    ", g, "gas");
    }

    // ═══════════════════════════════════════════════════════
    // Full comparison table: Dalet vs Black-Scholes
    // ═══════════════════════════════════════════════════════

    function test_ComparisonTable() public pure {
        console.log("=== Dalet vs Black-Scholes Comparison ===");
        console.log("");

        // ATM
        {
            (uint256 cd, uint256 pd,,) = DaletOption.price(100e18, 100e18, 1e18, 5e16, 20e16);
            (uint256 cb, uint256 pb,,) = BlackScholes.price(100e18, 100e18, 1e18, 5e16, 0, 20e16);
            console.log("ATM (K=100, T=1yr)");
            console.log("  Dalet call:", cd, " BS call:", cb);
            console.log("  Dalet put: ", pd, " BS put: ", pb);
        }
        // OTM
        {
            (uint256 cd, uint256 pd,,) = DaletOption.price(100e18, 120e18, 25e16, 5e16, 20e16);
            (uint256 cb, uint256 pb,,) = BlackScholes.price(100e18, 120e18, 25e16, 5e16, 0, 20e16);
            console.log("OTM (K=120, T=0.25yr)");
            console.log("  Dalet call:", cd, " BS call:", cb);
            console.log("  Dalet put: ", pd, " BS put: ", pb);
        }
        // Deep OTM
        {
            (uint256 cd, uint256 pd,,) = DaletOption.price(100e18, 150e18, 25e16, 5e16, 20e16);
            (uint256 cb, uint256 pb,,) = BlackScholes.price(100e18, 150e18, 25e16, 5e16, 0, 20e16);
            console.log("Deep OTM (K=150, T=0.25yr)");
            console.log("  Dalet call:", cd, " BS call:", cb);
            console.log("  Dalet put: ", pd, " BS put: ", pb);
        }
        // ITM
        {
            (uint256 cd, uint256 pd,,) = DaletOption.price(100e18, 80e18, 1e18, 5e16, 20e16);
            (uint256 cb, uint256 pb,,) = BlackScholes.price(100e18, 80e18, 1e18, 5e16, 0, 20e16);
            console.log("ITM (K=80, T=1yr)");
            console.log("  Dalet call:", cd, " BS call:", cb);
            console.log("  Dalet put: ", pd, " BS put: ", pb);
        }
    }
}
