// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {TMathFusaka} from "../src/TMathFusaka.sol";
import {TMathLegacy} from "../src/TMathLegacy.sol";

// Foundry cannot call `internal` library functions directly from a test
// contract; internal functions are inlined into their caller. These harness
// contracts wrap each library function as `external` so the test contracts
// have a concrete call target and so reverts can be caught with try/catch.
//
// IMPORTANT: HFusaka exercises TMathFusaka, which uses the EIP-7939 `clz`
// opcode. Tests against HFusaka require the Foundry profile to compile and
// run for the Osaka (Fusaka) EVM or later. Set in foundry.toml:
//     evm_version = "osaka"
// HLegacy uses an MSB cascade and runs on any EVM version.

contract HFusaka {
    function exp(bool positive, uint256 exponent) external pure returns (uint256) {
        return TMathFusaka.exp(positive, exponent);
    }

    function ln(uint256 antilog) external pure returns (bool negative, uint256 result) {
        return TMathFusaka.ln(antilog);
    }

    function sqrt(uint256 x) external pure returns (uint256) {
        return TMathFusaka.sqrt(x);
    }

    function trig(uint256 x, bool cos) external pure returns (uint256 result, bool sign) {
        return TMathFusaka.trig(x, cos);
    }

    function sin(uint256 x) external pure returns (uint256 result, bool sign) {
        return TMathFusaka.sin(x);
    }

    function cos(uint256 x) external pure returns (uint256 result, bool sign) {
        return TMathFusaka.cos(x);
    }

    function tan(uint256 x) external pure returns (uint256 result, bool sign) {
        return TMathFusaka.tan(x);
    }

    function sin_sq(uint256 x) external pure returns (uint256) {
        return TMathFusaka.sin_sq(x);
    }

    function cos_sq(uint256 x) external pure returns (uint256) {
        return TMathFusaka.cos_sq(x);
    }
}

contract HLegacy {
    function exp(bool positive, uint256 exponent) external pure returns (uint256) {
        return TMathLegacy.exp(positive, exponent);
    }

    function ln(uint256 antilog) external pure returns (bool negative, uint256 result) {
        return TMathLegacy.ln(antilog);
    }

    function sqrt(uint256 x) external pure returns (uint256) {
        return TMathLegacy.sqrt(x);
    }

    function trig(uint256 x, bool cos) external pure returns (uint256 result, bool sign) {
        return TMathLegacy.trig(x, cos);
    }

    function sin(uint256 x) external pure returns (uint256 result, bool sign) {
        return TMathLegacy.sin(x);
    }

    function cos(uint256 x) external pure returns (uint256 result, bool sign) {
        return TMathLegacy.cos(x);
    }

    function tan(uint256 x) external pure returns (uint256 result, bool sign) {
        return TMathLegacy.tan(x);
    }

    function sin_sq(uint256 x) external pure returns (uint256) {
        return TMathLegacy.sin_sq(x);
    }

    function cos_sq(uint256 x) external pure returns (uint256) {
        return TMathLegacy.cos_sq(x);
    }
}
