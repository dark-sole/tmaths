# TMath test suite

Three-tier Foundry test suite for `TMathFusaka` and `TMathLegacy`.

## Files

| File | Purpose |
|---|---|
| `TMathHarness.sol` | Wraps the `internal` library functions as `external` so Foundry can call them and catch reverts. Two harnesses: `HFusaka`, `HLegacy`. |
| `TMathVectors.gen.sol` | Auto-generated reference vectors (90 of them) computed by mpmath at 50-digit precision. Do not edit by hand. |
| `TMathVectors.t.sol` | Tier 1. Asserts each output against its mpmath reference, within a relative-error band. |
| `TMathProperties.t.sol` | Tier 2. Fuzzes in-domain inputs and checks algebraic invariants (fixed points, monotonicity, roundtrips, revert behaviour). |
| `TMathEquivalence.t.sol` | Tier 3. Fuzzes wide and asserts `TMathFusaka` and `TMathLegacy` produce identical output. |
| `gen_vectors.py` | The mpmath generator. Re-run only when the input sets change. |

## Required: EVM version

`TMathFusaka` uses the EIP-7939 `clz` opcode (Fusaka hardfork). Foundry must
compile and run for the Osaka EVM or later, or every `HFusaka` test will fail
with an invalid-opcode revert.

In `foundry.toml`:

```toml
[profile.default]
evm_version = "osaka"
```

`TMathLegacy` uses an MSB cascade and runs on any EVM version. If you only
want to test Legacy on an older toolchain, run the Legacy-specific tests in
isolation (see below).

## Layout assumed

The tests import the libraries from `../src/`:

```
src/TMathFusaka.sol
src/TMathLegacy.sol
test/TMathHarness.sol
test/TMathVectors.gen.sol
test/TMathVectors.t.sol
test/TMathProperties.t.sol
test/TMathEquivalence.t.sol
script/gen_vectors.py
```

Adjust the import paths if your project uses a different structure.

## Running

```sh
# Whole suite
forge test

# One tier
forge test --match-contract TMathVectorsTest
forge test --match-contract TMathPropertiesTest
forge test --match-contract TMathEquivalenceTest

# Only Legacy vectors (runs on any EVM version)
forge test --match-test Legacy

# More fuzz runs for the equivalence tier (recommended before a release)
forge test --match-contract TMathEquivalenceTest --fuzz-runs 100000
```

## Tolerance bands

| Function | Band (relative error) | Measured worst case |
|---|---|---|
| exp | 1e-5 | ~3.8e-6 |
| ln | 1e-4 | ~7.5e-5 (at the m=1.5 branch boundary) |
| sqrt | 1e-8 | ~1e-9 |
| sin, cos | 1e-5 | octant-reduced Taylor |

The bands sit just above the measured worst case: a real accuracy
regression trips them, normal integer-truncation noise does not.

## Regenerating vectors

```sh
cd script
python3 gen_vectors.py    # writes TMathVectors.gen.sol
```

Requires `mpmath` (`pip install mpmath`). The generator computes at 50-digit
precision and truncates toward zero to match EVM integer arithmetic.
