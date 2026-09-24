// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {DaletOption} from "../src/DaletOption.sol";
import {DaletOptionVectors, PriceVector, CdfVector, RevertVector} from "./DaletOptionVectors.gen.sol";

contract DaletVectorWrapper {
    function price(uint256 S, uint256 K, uint256 T, uint256 r, uint256 sigma)
        external pure returns (uint256, uint256, uint256, uint256)
    {
        return DaletOption.price(S, K, T, r, sigma);
    }
}

/// @notice DaletOption against the funding bond reference vectors (PERP vectors.json).
///         Call and put are charged amounts: each must be at or above the ceiling of the exact
///         value (rounded up) and within the rounding margin plus approximation error of it.
///         Deltas are not amounts and carry no direction: each must be within DELTA_TOL of the
///         exact value. Every result is logged as `id output value` for the error report.
contract DaletOptionVectorsTest is Test {

    /// @dev Largest excess over the exact price allowed, in wei: three rounding margins
    ///      (the leg and, for the parity leg, K e^{-rT}) plus PRICE_TOL_REL of the price.
    uint256 internal constant PRICE_TOL_REL = 1e3; // 1e-15, in units of 1e-18

    /// @dev Delta tolerance in wei: the error of ln S - ln K divided by the scale s.
    uint256 internal constant DELTA_TOL = 2_000;

    DaletVectorWrapper internal wrapper;

    function setUp() public {
        wrapper = new DaletVectorWrapper();
    }

    function _tol(PriceVector memory v, uint256 exactCeil) internal pure returns (uint256) {
        uint256 margin = DaletOption.MARGIN_WEI + (v.S + v.K) * DaletOption.MARGIN_PER_UNIT / 1e18 + 1;
        return 3 * margin + exactCeil * PRICE_TOL_REL / 1e18 + 4;
    }

    function _checkUp(string memory id, string memory name, uint256 got, uint256 ceil, uint256 tol)
        internal
    {
        console.log(id, name, got);
        assertGe(got, ceil, string.concat(id, " ", name, ": below the exact value (rounding up)"));
        assertLe(got - ceil, tol, string.concat(id, " ", name, ": excess over the exact value"));
    }

    function _checkNear(string memory id, string memory name, uint256 got, uint256 fl, uint256 ce)
        internal
    {
        console.log(id, name, got);
        uint256 err = got < fl ? fl - got : (got > ce ? got - ce : 0);
        assertLe(err, DELTA_TOL, string.concat(id, " ", name, ": delta error"));
    }

    function test_PriceVectors() public {
        PriceVector[] memory vs = DaletOptionVectors.prices();
        for (uint256 i = 0; i < vs.length; i++) {
            PriceVector memory v = vs[i];
            (uint256 c, uint256 p, uint256 dc, uint256 dp) =
                DaletOption.price(v.S, v.K, v.T, v.r, v.sigma);
            _checkUp(v.id, "call", c, v.fc[1], _tol(v, v.fc[1]));
            _checkUp(v.id, "put", p, v.fc[3], _tol(v, v.fc[3]));
            assertEq(dc + dp, 1e18, string.concat(v.id, ": deltas sum to one"));
            if (v.fc[5] != 0 || v.fc[7] != 0) {
                _checkNear(v.id, "delta_call", dc, v.fc[4], v.fc[5]);
                _checkNear(v.id, "delta_put", dp, v.fc[6], v.fc[7]);
            }
        }
    }

    function test_CdfVectors() public {
        CdfVector[] memory vs = DaletOptionVectors.cdf();
        for (uint256 i = 0; i < vs.length; i++) {
            uint256 got = DaletOption.daletCdf(vs[i].x);
            console.log(vs[i].id, "value", got);
            assertGe(got + 1, vs[i].floor, vs[i].id);
            assertLe(got, vs[i].ceil + 1, vs[i].id);
        }
    }

    function test_RevertVectors() public {
        bytes4[2] memory sel = [DaletOption.ZeroScale.selector, DaletOption.NegativeParityLeg.selector];
        RevertVector[] memory vs = DaletOptionVectors.reverts(sel);
        assertGt(vs.length, 0);
        for (uint256 i = 0; i < vs.length; i++) {
            RevertVector memory v = vs[i];
            vm.expectRevert(v.selector);
            wrapper.price(v.S, v.K, v.T, v.r, v.sigma);
        }
    }

    /// @dev expm1 at RAY against e^y - 1 across the series threshold (values from model.expm1).
    function test_Expm1Threshold() public pure {
        // e^0.5 - 1 = 0.648721270700128146848650787814163571653776100710148011575...
        assertApproxEqAbs(DaletOption.expm1Ray(5e26), 648721270700128146848650788, 1e10);
        // just below: series; e^(0.5 - 1e-27) - 1
        assertApproxEqAbs(DaletOption.expm1Ray(5e26 - 1), 648721270700128146848650786, 40);
        // e^1e-9 - 1 = 1.0000000005000000001666666667e-9
        assertEq(DaletOption.expm1Ray(1e18), 1000000000500000000);
        assertEq(DaletOption.expm1Ray(0), 0);
    }
}
