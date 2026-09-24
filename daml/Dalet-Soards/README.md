# Dalet Option Pricer on Canton Network

## Project Summary

This project implements a European option pricing engine as a Daml smart contract deployed on the Canton Network. It ports Tokenisys's proprietary Dalet distribution option pricer from Solidity (EVM) to Daml, creating a functioning on-chain quantitative computation service that generates real transactions on a Canton validator node.

The Dalet distribution (Student-t, ν=2) produces heavier tails than the Normal distribution used in Black-Scholes, giving more realistic prices for deep out-of-the-money options — a known limitation of classical option pricing models that underestimate tail risk.

---

## What We Built

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PricingService.daml                   │
│         Canton Smart Contract (on-chain service)        │
│                                                         │
│  ServiceProposal ──AcceptService──▶ PricingService      │
│                                       │                 │
│                          RequestPrice─┼──▶ PricingResult │
│                          RequestCDF───┼──▶ CDFResult     │
│                                       │                 │
│                          (re-creates PricingService      │
│                           for next request)              │
└───────────┬─────────────────────┬───────────────────────┘
            │                     │
    ┌───────▼───────┐     ┌──────▼──────┐
    │ DaletOption   │     │  DaletCDF   │
    │ (pricer)      │     │  (CDF/PDF/  │
    │               │     │   quantile) │
    └───────┬───────┘     └──────┬──────┘
            │                    │
            └────────┬───────────┘
                     │
              ┌──────▼──────┐
              │   TMaths    │
              │ (exp/ln/√)  │
              └─────────────┘
```

### File Inventory

| File | Purpose | Lines |
|------|---------|-------|
| `TMaths.daml` | Core math: exp, ln, sqrt via 2^k decomposition + Taylor/Newton-Raphson | ~330 |
| `DaletCDF.daml` | Dalet distribution: CDF, survival, PDF, density integral, quantile | ~90 |
| `DaletOption.daml` | European option pricer: OTM-first log-space + price-space parity | ~190 |
| `PricingService.daml` | Canton smart contract: service proposal, pricing requests, CDF requests | ~160 |
| `Test.daml` | TMaths precision test suite (25 cases, all pass) | ~150 |
| `ManualTest.daml` | TMaths precision measurement dump | ~50 |
| `DaletTest.daml` | Dalet CDF + option pricing tests with value output | ~140 |
| `ServiceTest.daml` | Full service lifecycle test generating 7 transactions | ~100 |

### Key Design Decisions

**OTM-first pricing with price-space parity.** The log-space formula is most accurate for out-of-the-money options (small values). The in-the-money side is derived via put-call parity in price-space, which avoids the `exp(x) - 1` cancellation that degrades precision for larger values. This eliminates parity error entirely (measured: **0.0**).

**Consuming choices for transaction generation.** Each `RequestPrice` or `RequestCDF` call archives the service contract and creates a fresh one alongside the result contract. This produces 3 ledger events per request (1 archive + 2 creates), generating real transaction volume on the validator node.

**Separated DaletCDF module.** The Dalet distribution functions are independent of option pricing and reusable for Value at Risk (VaR), Conditional VaR, Expected Shortfall, and any tail-probability computation.

**Closed-form quantile function.** The Dalet quantile `x = u / √(1 - u²)` where `u = 2p - 1` is exact — no iterative solver required. This makes VaR computation a single function call.

---

## The User Product

### What It Does

A client party connects to a Tokenisys-operated pricing service on the Canton Network. Through the standard Canton offer/accept pattern, the client gains access to on-chain option pricing and risk analytics.

**Option Pricing.** The client submits spot price, strike, time to expiry, risk-free rate, and volatility. The contract computes and stores call price, put price, call delta, and put delta — all as immutable, auditable records signed by both parties.

**Risk Analytics.** The client submits a value to the Dalet CDF and receives the cumulative probability, survival probability, probability density, and density integral — building blocks for VaR and tail-risk analysis.

### Sample Pricing Results

| Scenario | Call | Put | Δ Call | Δ Put |
|----------|------|-----|--------|-------|
| ATM: S=100 K=100 T=3m σ=20% | 5.47 | 4.22 | 0.537 | 0.463 |
| ITM call: S=100 K=90 | 13.01 | 1.89 | 0.874 | 0.126 |
| OTM call: S=100 K=110 | 2.26 | 10.89 | 0.170 | 0.830 |
| Deep OTM: S=100 K=150 | 0.61 | 48.75 | 0.015 | 0.985 |
| High vol: σ=50% | 12.14 | 10.89 | 0.463 | 0.537 |
| 1-year expiry | 11.68 | 6.80 | 0.574 | 0.426 |

**Put-call parity error: 0.0** (exact, by construction).

### Sample CDF Results

| Input | CDF | Survival | Notes |
|-------|-----|----------|-------|
| x = 0 | 0.5000 | 0.5000 | Symmetric centre |
| x = 1 | 0.8536 | 0.1464 | |
| x = 2 | 0.9472 | 0.0528 | |
| x = -1 | 0.1464 | 0.8536 | Perfect symmetry: CDF(1) + CDF(-1) = 1.0 |

**Quantile roundtrip: CDF(Q(0.95)) = 0.95 exactly. CDF(Q(0.01)) = 0.01 exactly.**

---

## How This Benefits the Validator Node

### Transaction Generation

Every pricing request generates a Canton transaction with real ledger events:

| Action | Events | Transaction Type |
|--------|--------|-----------------|
| ServiceProposal creation | 1 create | Setup |
| AcceptService | 1 archive + 1 create | Setup |
| RequestPrice | 1 archive + 2 creates | Pricing |
| RequestCDF | 1 archive + 2 creates | Analytics |

A single test run of 5 requests produces **7 committed transactions** with **17 ledger events**. At production scale, a pricing service handling 100 requests per hour generates 300+ events per hour — all validated by the node.

### Featured Application Potential

Canton Network's Featured Application Activity Markers program rewards applications that generate transaction volume. Each `RequestPrice` and `RequestCDF` constitutes measurable on-chain activity. Under the current Canton Coin minting model:

- Featured apps receive CC rewards proportional to their activity weight
- The 100x minting multiplier per weight unit applies under current low-competition conditions
- Early-stage featured apps maximise earnings based on their own activity levels, not pool competition

A pricing service with institutional clients generating steady transaction flow directly translates to CC rewards for the validator node operator.

### Auditable Computation

Every pricing result is an immutable, dual-signed contract on the Canton ledger:

- **Both operator and client are signatories** — neither can unilaterally fabricate results
- **All inputs and outputs are stored** — spot, strike, T, r, σ, call, put, deltas
- **Results are queryable** — via Canton's Ledger API, PQS (PostgreSQL), or JSON API
- **History is preserved** — compliant with financial record-keeping requirements

This creates a verifiable audit trail of computational results — a requirement for institutional risk management and regulatory compliance.

### Sub-Transaction Privacy

Canton's architecture ensures that pricing requests between one operator-client pair are invisible to other participants on the network. A trading desk's option pricing activity (which reveals positioning and risk appetite) remains confidential — a critical requirement that public blockchains cannot satisfy.

---

## Precision Analysis: The Fortress Argument

### What Daml Can Do

The Daml `Decimal` type provides 10 fractional digits (38 total digits). Our TMaths implementations achieve:

| Function | Best Case | Worst Case | Notes |
|----------|-----------|------------|-------|
| exp(x) | ~0 error (small x) | 0.0014% (x=0.5) | 6-term Taylor series |
| ln(x) | exact (ln(2)) | 0.00007% (ln(10)) | 7-term Taylor, near-ATM essentially exact |
| sqrt(x) | exact (all tested) | 0 bps | Newton-Raphson, 4 iterations |

### Where Precision Degrades

The option pricer chains 5+ operations: `ln → sqrt → division → multiplication → exp`. Each step truncates at 10 digits. The compounding effect is measurable:

- **ln(exp(1)) = 1.0000253517** — 0.0025% error from a simple roundtrip
- **Deep OTM pricing** — the `exp(x) - 1` step loses leading digits when x is small. At `C_log_norm ≈ 0.001`, exp(0.001) ≈ 1.0010005000, and subtracting 1.0 leaves 0.0010005000 with only 7 significant digits remaining
- **Chained operations in the pricer** — each intermediate truncation propagates forward

### What Fortress Would Provide

Fortress's FortVM executes Fortran-compiled WASM with IEEE 754 double precision (15–17 significant digits) or quad precision (33–36 significant digits), with pinned BLAS/LAPACK/FFT kernels for deterministic cross-validator reproducibility.

| Capability | Canton (Daml Decimal) | Fortress (FortVM double) | Fortress (FortVM quad) |
|------------|----------------------|-------------------------|----------------------|
| Significant digits | 10 | 15–17 | 33–36 |
| exp(0.5) error | 0.0014% | < 0.0000001% | essentially exact |
| ln(exp(1)) roundtrip | 0.0025% error | < 1e-14 | < 1e-30 |
| Option pricing chain | 5+ truncations compound | negligible compounding | no measurable error |
| Linear algebra | not available | full BLAS/LAPACK | full BLAS/LAPACK |
| Portfolio optimisation | not feasible | standard capability | standard capability |

The Daml implementation we built is a functioning pricer — it produces correct results to within Canton's precision limits. But institutional finance requires:

- **Portfolio-level risk** (matrix operations on hundreds of positions)
- **Greeks surfaces** (repricing across strike/expiry grids with consistent precision)
- **Regulatory capital** (Basel III/IV models with specific precision requirements)
- **Multi-asset correlation** (Cholesky decomposition, eigenvalue analysis)

These are beyond what any smart contract language's built-in arithmetic can deliver. Fortress addresses this by providing a deterministic, bit-identical computation layer that complements Canton's strengths in privacy, composability, and multi-party workflows.

---

## Project Structure

```
dalet-option/
├── daml.yaml                  SDK 2.10.0, dependencies
├── daml/
│   ├── TMaths.daml            Core math (exp, ln, sqrt)
│   ├── DaletCDF.daml          Dalet distribution (CDF, PDF, quantile)
│   ├── DaletOption.daml       Option pricer (OTM-first + parity)
│   ├── PricingService.daml    Canton smart contract
│   ├── Test.daml              TMaths tests (all pass)
│   ├── ManualTest.daml        Precision measurement
│   ├── DaletTest.daml         CDF + option tests
│   └── ServiceTest.daml       Service lifecycle test
```

### Build and Test

```bash
# Install prerequisites
# JDK 11+, Daml SDK 2.10+, VS Code with Daml Studio extension

# Run all tests
daml test

# Build deployable artifact
daml build
# Output: .daml/dist/dalet-option-1.0.0.dar

# Run locally with sandbox
daml start
```

### Deploy to Canton Participant Node

```scala
// Upload DAR
participant.dars.upload("/path/to/dalet-option-1.0.0.dar")

// Vet package
participant.packages.find("dalet-option")
participant.topology.vetPackage("PACKAGE_ID")

// Connect to sync domain
participant.domains.connect("global", "https://global.canton.network:443")
```

---

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Smart contract language | Daml 2.10 (Haskell-derived, functional) |
| Blockchain runtime | Canton Network (sub-transaction privacy) |
| Contract model | UTXO-based (Active Contract Set) |
| Consensus | Proof-of-Stakeholder via sync domains |
| Development IDE | VS Code + Daml Studio extension |
| Build system | Daml SDK (`daml build` → DAR artifact) |
| Testing | Daml Script (`daml test`) |
| Original implementation | Solidity 0.8.31 (EVM, 1e18 fixed-point) |

---

*Built by Tokenisys (The Dark Sole Enterprise Ltd) — February 2026*
