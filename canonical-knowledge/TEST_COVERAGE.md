# TEST_COVERAGE — tokenisys-libs-prod / Solidity math libraries

Scope: `tokenisys-libs-prod/solidity`. Foundry suite covering the chain-split
fixed-point libraries `TMathFusaka` (EIP-7939 `clz`, for Fusaka-active chains)
and `TMathLegacy` (8-step MSB cascade, for Base / OP Stack), and their four
consumer contracts.

Status as of 2026-05-18 v1: **124 tests, 124 passing, 0 failing.**

This is a living document. Edited in place as the suite changes; not dated or
versioned.

## Suite layout

The library suite is three-tier plus a gas tier. The tiers are deliberately
different in kind, because they catch different classes of fault.

### Tier 1 — Vectors (`test/TMathVectors.t.sol`, 10 tests, 0 fuzz)

The correctness oracle. Concrete input/output pairs generated offline by
`script/gen_vectors.py` against mpmath at high precision, baked into
`test/TMathVectors.gen.sol`. Each of `exp`, `ln`, `sqrt`, `sin`, `cos` is
checked for both libraries against the mpmath reference.

This tier is the only one that proves a function is *correct* in absolute
terms. It is what caught the `ln` x1000 divisor bug — the equivalence tier
could not, because both libraries shared the bug identically.

Trig vector tests use `TRIG_ZERO_FLOOR = 1e9`: at true zero-crossings the
mpmath generator emits tiny nonzero integers, so magnitude and sign assertions
are skipped below the floor (the result there is essentially zero and the
relative error is meaningless). The two `ln` guards keep the strict `== 0`.

### Tier 2 — Properties (`test/TMathProperties.t.sol`, 17 tests, 11 fuzz)

Mathematical invariants that must hold for all inputs, fuzzed. Covers:
monotonicity (`exp`, `ln`, `sqrt`), round-trips (`exp(ln(x))`, `ln(exp(x))`),
identities (`exp(-x) = 1/exp(x)`, `sqrt(x)^2 = x`, `sin^2 + cos^2 = 1`),
sign correctness (`ln` above/below 1), boundedness (trig in [-1,1]), boundary
values (`exp(0)=1`, `ln(1)=0`, `sqrt(1)=1`), and domain reverts (`exp` above
domain, `ln`/`sqrt` on zero).

The reciprocal-identity fuzz is bounded `[1e15, 30e18]`, not the full `EXP_MAX`
domain: beyond ~x=30 the WAD-scaled `exp(-x)` has too few significant digits
for the 1e-3 identity to hold. This is a representation limit of WAD, not an
`exp` defect — the monotonicity fuzz and the revert test still exercise the
full `EXP_MAX` domain.

### Tier 3 — Equivalence (`test/TMathEquivalence.t.sol`, 12 tests, 9 fuzz)

Asserts `TMathFusaka` and `TMathLegacy` produce identical output for every
input. The two libraries differ only in the `clz` / MSB-cascade implementation
detail; their public results must match exactly. Covers all of `exp` (both
signs), `ln`, `sqrt`, `sin`, `cos`, `tan`, `sin_sq`, `cos_sq`, plus revert
parity for `exp`, `ln`, `sqrt`.

`testFuzz_Equiv_Tan` asserts revert-parity at poles: where `cos(x) = 0`, both
libraries must revert `Undefined()`; elsewhere both must return equal values.
The try/catch makes the pole an asserted equivalence rather than a blind spot.

Important limitation: this tier proves the two libraries *agree*, not that
either is *correct*. A bug present identically in both passes equivalence. Tier
1 is the correctness check; tier 3 is the parity check. They are complementary.

### Tier 4 — Gas (`test/TMathGas.t.sol`, 11 tests, 0 fuzz)

Gas measurement for `exp`, `exp` negative, `ln`, `ln` small, `sqrt`, `sqrt`
large, `sin`, `cos`, `tan`, `sin_sq`, `cos_sq`. Regression visibility, not a
pass/fail correctness gate.

### Harness and generator

- `test/TMathHarness.sol` — wraps the `internal` library functions as
  `external` so tests (and the equivalence try/catch) can call them.
- `test/TMathVectors.gen.sol` — generated vector data, do not hand-edit.
- `script/gen_vectors.py` — regenerates the vector file from mpmath.

## Consumer coverage

The four consumer contracts have their own suites (counts from the 2026-05-18
v1 `forge test` run; these `.t.sol` files live in the repo `test/` directory):

- `NormalCDF.t.sol` — 29 tests. Concrete Phi values, symmetry, monotonicity,
  clamping, gas.
- `BlackScholes.t.sol` — 13 tests. ATM / ITM / OTM pricing, put-call parity,
  delta bounds, yield, negative rate, zero-input reverts, gas.
- `DaletCDF.t.sol` — 15 tests. Known values, symmetry, monotonicity, heavy-tail,
  clamp boundaries, gas.
- `DaletOption.t.sol` — 15 tests. ATM / ITM / OTM, put-call relationship,
  strike monotonicity, Dalet-vs-BlackScholes comparison, zero-input reverts,
  gas.

The consumers exercise `exp`, `ln`, `sqrt` only. `sin`, `cos`, `tan`, `sin_sq`,
`cos_sq` have no consumer among the shipped contracts — their only coverage is
the library tiers above.

## Coverage by function

| Function   | Vectors | Properties | Equivalence | Gas | Consumer use |
|------------|---------|------------|-------------|-----|--------------|
| `exp`      | yes     | yes        | yes         | yes | yes          |
| `ln`       | yes     | yes        | yes         | yes | yes          |
| `sqrt`     | yes     | yes        | yes         | yes | yes          |
| `sin`      | yes     | yes (id.)  | yes         | yes | no           |
| `cos`      | yes     | yes (id.)  | yes         | yes | no           |
| `tan`      | no      | no         | yes         | yes | no           |
| `sin_sq`   | no      | no         | yes         | yes | no           |
| `cos_sq`   | no      | no         | yes         | yes | no           |

## Known coverage gaps

These are gaps in the *tests*, recorded honestly — not defects in the code.

1. **`tan` has no vector tier.** `tan` is covered only by the equivalence tier
   and gas. There is no mpmath vector check of `tan` magnitude against a known
   reference. Equivalence proves Fusaka and Legacy agree on `tan`, and since
   `tan` is derived as `sin/cos` from already-vector-checked `sin` and `cos`
   its correctness is indirect — but it is not directly oracle-checked. If
   `tan` ever gains a consumer, add a `tan` vector tier first.

2. **`sin_sq` / `cos_sq` have no vector or property tier.** Same situation:
   equivalence and gas only. Their correctness rests on the identities they
   are built from, not on direct mpmath vectors.

3. **trig vectors stop at 4*PI.** The vector inputs reach `4*PI` (the input
   that surfaced the octant-wraparound bug). Inputs far above `4*PI` are not
   vector-checked, though the mod-8 octant reduction is now structurally
   correct for all `x` and the property tier fuzzes trig boundedness across
   the full range.

4. **No fuzz on the consumer contracts.** `NormalCDF`, `BlackScholes`,
   `DaletCDF`, `DaletOption` are concrete-test only. Their property invariants
   (monotonicity, parity) are checked at fixed points, not fuzzed.

## Regression notes

- The `ln` x1000 bug, the trig octant wraparound, and the `tan` pole division
  were all caught or exposed by this suite during the 2026-05-18 v1 campaign.
  See `STATE_2026-05-18_v1.md` for the full bug list.
- forge caches test artifacts by contract name. After editing a test file
  whose contract name is unchanged, run `forge clean` before `forge test` or
  the stale artifact is silently reused.
- `foundry.toml` requires `via_ir = true` and `optimizer = true` (otherwise
  stack-too-deep at `BlackScholes.sol`); `evm_version = "osaka"`, `solc 0.8.31`.
