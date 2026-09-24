// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TMathFusaka} from "../src/TMathFusaka.sol";

// Throwaway diagnostic. Logs TMathFusaka.ln output for every ln vector so we
// can see which input produces a wrong or panicking result. Delete once the
// ln vector failure is resolved.
//
// Run:  forge test --match-contract LnDebug -vv

contract LnDebugTest is Test {
    function test_LnDebug() public pure {
        uint256[21] memory inputs = [
            uint256(10000000000000000),           // 0  0.01
            100000000000000000,                   // 1  0.1
            250000000000000000,                   // 2  0.25
            500000000000000000,                   // 3  0.5
            900000000000000000,                   // 4  0.9
            990000000000000000,                   // 5  0.99
            1000000000100000000,                  // 6  1.0000000001
            1100000000000000000,                  // 7  1.1
            1250000000000000000,                  // 8  1.25
            1499999999900000000,                  // 9  1.4999999999
            1500000000000000000,                  // 10 1.5
            1500000000100000000,                  // 11 1.5000000001
            1750000000000000000,                  // 12 1.75
            2000000000000000000,                  // 13 2
            2718281828459045000,                  // 14 e
            5000000000000000000,                  // 15 5
            10000000000000000000,                 // 16 10
            100000000000000000000,                // 17 100
            1000000000000000000000,               // 18 1000
            1000000000000000000000000,            // 19 1e6
            1000000000000000000000000000000       // 20 1e12
        ];

        for (uint256 i = 0; i < 21; i++) {
            (bool neg, uint256 mag) = TMathFusaka.ln(inputs[i]);
            console.log("idx", i);
            console.log("  input ", inputs[i]);
            console.log("  mag   ", mag);
            console.log("  neg   ", neg);
        }
    }
}
