// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TMathFusaka} from "../src/TMathFusaka.sol";

// Throwaway diagnostic. Logs TMathFusaka.sin and .cos sign and magnitude for
// every vector input, against the mpmath expected sign, to locate the
// sin/cos sign-mismatch vector-test failure.
// Delete once the trig vector failure is resolved.
//
// Run:  forge test --match-contract TrigDebug -vv

contract TrigDebugTest is Test {
    function test_TrigDebug() public pure {
        // sin vectors: input, expectedMag, expectedNeg (1 = negative)
        uint256[3][17] memory sinVec = [
            [uint256(100000000000000), 99999999833333, 0],
            [uint256(100000000000000000), 99833416646828152, 0],
            [uint256(785398163397448300), 707106781186547517, 0],
            [uint256(1000000000000000000), 841470984807896506, 0],
            [uint256(1200000000000000000), 932039085967226349, 0],
            [uint256(1570796326794896600), 999999999999999999, 0],
            [uint256(2000000000000000000), 909297426825681695, 0],
            [uint256(2500000000000000000), 598472144103956494, 0],
            [uint256(3141592653589793000), 238, 0],
            [uint256(4000000000000000000), 756802495307928251, 1],
            [uint256(4500000000000000000), 977530117665097055, 1],
            [uint256(4712388980384690000), 999999999999999999, 1],
            [uint256(5500000000000000000), 705540325570391906, 1],
            [uint256(6283185307179586000), 476, 1],
            [uint256(7000000000000000000), 656986598718789090, 0],
            [uint256(10000000000000000000), 544021110889369813, 1],
            [uint256(12566370614359172000), 953, 1]
        ];
        // cos vectors: input, expectedMag, expectedNeg
        uint256[3][17] memory cosVec = [
            [uint256(100000000000000), 999999995000000004, 0],
            [uint256(100000000000000000), 995004165278025766, 0],
            [uint256(785398163397448300), 707106781186547531, 0],
            [uint256(1000000000000000000), 540302305868139717, 0],
            [uint256(1200000000000000000), 362357754476673577, 0],
            [uint256(1570796326794896600), 19, 0],
            [uint256(2000000000000000000), 416146836547142386, 1],
            [uint256(2500000000000000000), 801143615546933714, 1],
            [uint256(3141592653589793000), 999999999999999999, 1],
            [uint256(4000000000000000000), 653643620863611914, 1],
            [uint256(4500000000000000000), 210795799430779705, 1],
            [uint256(4712388980384690000), 142, 0],
            [uint256(5500000000000000000), 708669774291260000, 0],
            [uint256(6283185307179586000), 999999999999999999, 0],
            [uint256(7000000000000000000), 753902254343304638, 0],
            [uint256(10000000000000000000), 839071529076452452, 1],
            [uint256(12566370614359172000), 999999999999999999, 0]
        ];

        console.log("=== SIN: got vs expected ===");
        for (uint256 i = 0; i < 17; i++) {
            (uint256 m, bool s) = TMathFusaka.sin(sinVec[i][0]);
            console.log("sin idx", i);
            console.log("  input        ", sinVec[i][0]);
            console.log("  got mag      ", m);
            console.log("  got sign pos ", s);
            console.log("  exp neg flag ", sinVec[i][2]);
        }
        console.log("=== COS: got vs expected ===");
        for (uint256 i = 0; i < 17; i++) {
            (uint256 m, bool s) = TMathFusaka.cos(cosVec[i][0]);
            console.log("cos idx", i);
            console.log("  input        ", cosVec[i][0]);
            console.log("  got mag      ", m);
            console.log("  got sign pos ", s);
            console.log("  exp neg flag ", cosVec[i][2]);
        }
    }
}
