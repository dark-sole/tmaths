# VALIDATOR TEAM BRIEFING

**Dalet Option Pricer -  Canton Network Featured Application Integrated into Tokenisys Product Suite**



February 2026 | Dark Sole | ds@tokenisys.com

---

## 1. What We Built

The Dalet Option Pricer is a fully functional European option pricing and risk analytics engine implemented as a Daml smart contract on the Canton Network. It computes option prices (call/put with deltas), CDF evaluations, and Value at Risk / Conditional Value at Risk using the Dalet distribution (Student-t, ν=2), which produces more realistic tail-risk estimates than the standard Normal/Black-Scholes model ( We can add Black-Scholes version).

**Current status:** All code compiled, all tests pass (25+ test cases), DAR artifact builds cleanly, runs on local Sandbox. Sponsorship secured. **The hard technical work is done.** What remains is infrastructure setup and Canton Network onboarding.

The service exposes three on-chain request types, each generating real Canton transactions:

- **RequestPrice** — option pricing (call, put, deltas) for any European option parameters
- **RequestCDF** — Dalet distribution CDF, survival, PDF, density integral
- **RequestRisk** — VaR and CVaR at 95% and 99% confidence levels

Each request is a consuming choice: it archives the service contract, creates an immutable result record (dual-signed by operator and client), and re-creates the service. This produces **3 ledger events per request** (1 archive + 2 creates), generating real transaction volume on the validator node.

---

## 2. How It Generates Canton Coin Rewards

Canton Network's Featured Application Activity Markers program allocates **62% of all CC minting** to featured applications. At the current minting rate of 10 billion CC per year, the app reward pool is approximately **833 million CC per month** (~516M CC cited by Canton documentation, with the difference due to rounding conventions).

**Key mechanism:** Each RequestPrice, RequestCDF, and RequestRisk transaction generates activity weight. Featured apps earn CC proportional to their weight, subject to a **100x cap per weight unit**. Under current low-competition conditions, this 100x cap is the binding constraint — not pool competition. This means our rewards scale linearly with our own transaction volume up to the cap ceiling.

### Monthly Reward Scenarios

Based on Canton Coin Whitepaper parameters and current network conditions (illustrative CC/USD rate: $0.10):

| Scenario | Txns/Month | Weight/Round | Monthly CC | Monthly USD |
|---|---:|---:|---:|---:|
| Minimal (testing) | 1,000 | 0.5 | 219,000 | $21,900 |
| Small app (1%) | 525,600 | 2 | 876,000 | $87,600 |
| **Medium app (5%)** | **2.6M** | **10** | **4,380,000** | **$438,000** |
| Active app (10%) | 5.3M | 20 | 8,760,000 | $876,000 |
| High-volume (25%) | 13.1M | 50 | 21,900,000 | $2,190,000 |

*Note: All scenarios assume featured app status. CC/USD rate of $0.10 used — check canton.thetie.io for current rate. Medium app (5% share) highlighted as realistic near-term target.*

### Competition Sensitivity (Your Weight Held at 10 CC/Round)

This table shows what happens to rewards as more featured apps join the network. Rewards remain cap-limited (constant) until total featured weight exceeds ~1,000 per round:

| Total Featured Weight/Round | Your Share | Monthly CC | Monthly USD | Constraint |
|---:|---:|---:|---:|---|
| 10 | 100% | 4,380,000 | $438,000 | Cap-limited (100x) |
| 50 | 20% | 4,380,000 | $438,000 | Cap-limited (100x) |
| 200 | 5% | 4,380,000 | $438,000 | Cap-limited (100x) |
| 1,000 | 1% | 4,380,000 | $438,000 | Cap-limited (100x) |
| 2,000 | 0.5% | 2,580,000 | $258,000 | **Pool-limited** |
| 5,000 | 0.2% | 1,032,000 | $103,200 | **Pool-limited** |

**Takeaway:** At current low competition (estimated ~50 total featured weight/round), our rewards are entirely determined by our own activity level. The 100x cap protects us from dilution until competition increases roughly 20-fold. This is the window to establish the app and accumulate CC.

---

## 3. Deployment Status and Timeline

**Built today**

- All Daml modules compile and pass tests (`daml test` — 25+ test cases)
- DAR artifact builds cleanly (`daml build`)
- Runs on local Sandbox (`daml start`)
- Sponsorship secured with a Super Validator
- Full deployment guide written (DEPLOYMENT.md) covering LocalNet through MainNet

**What remains:**

| Phase | Duration | Blocker | Outcome |
|---|---|---|---|
| LocalNet (CN Quickstart) | 1–3 days | None | Local testing |
| DevNet whitelisting | 2–7 days | Sponsor submits IP | Real GS infra |
| DevNet live + DAR upload | 1–2 days | Onboarding secret | Liveness rewards begin |
| TestNet approval | 1–2 weeks | GSF Committee | Production staging |
| MainNet + Featured App | 1–2 weeks | GSF Committee | CC rewards active |

**Total timeline: approximately 4–8 weeks to production and CC rewards.**

**Frontend:** No frontend is required for transaction generation. The service operates via the Canton Ledger API (gRPC) or Canton Console. Clients submit pricing/risk requests programmatically. A web frontend can be built later if needed for client-facing access (via the HTTP JSON API on port 7575), but it is not a dependency for launch or reward generation.

---

## 4. Next steps

### Infrastructure Requirements

| Component | Specification |
|---|---|
| Compute | VM or K8s: 4 vCPU, 16 GB RAM (e.g. AWS t3.xlarge, GCP e2-standard-4) |
| Database | PostgreSQL 14+ (managed: AWS RDS, GCP Cloud SQL, Azure DB) |
| Network | Fixed egress IP (required for SV whitelisting), port 443 |
| Auth | OIDC provider: Auth0, Keycloak, or enterprise IdP |
| Container | Docker Compose 2.26+ or Kubernetes with Helm |
| Storage | 50 GB+ SSD (database) + 20 GB (images/logs) |

### Action Items

1. **Provision a VM or K8s cluster with a fixed egress IP** — this IP is submitted to Super Validators for whitelisting and is the first blocker.
2. **Set up an OIDC provider** *(Auth0 is simplest)* — needs Client Credentials Grant (machine-to-machine) and Authorization Code Grant (wallet UI).
3. **Provision PostgreSQL 14+** — managed service recommended (RDS/Cloud SQL). This stores the Private Contract Store.
4. **Confirm sponsor will submit the egress IP for DevNet whitelisting** — separate IPs needed for DevNet, TestNet, and MainNet.
5. **We handle everything else:** DAR upload, package vetting, party registration, service contract deployment, featured app application to GSF Committee.

---

**Bottom line:** The application is built and tested. With infrastructure in place and IP whitelisting submitted, we can be generating real Canton transactions and earning CC rewards within 2-4 weeks. Early-mover advantage under the current 100x cap makes the timing optimal.

---

*Tokenisys February 2026*
