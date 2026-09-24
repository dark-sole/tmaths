# Dalet Option Pricer — Canton Network Deployment Guide

Technical steps to deploy the Dalet pricing service from local sandbox to Canton MainNet.

---

## Current State

- All Daml modules compile and pass tests via `daml test`
- DAR builds cleanly via `daml build`
- Runs on local Sandbox via `daml start`
- Sponsorship secured

---

## Infrastructure Requirements

### Validator Node (Production — DevNet/TestNet/MainNet)

You need **one environment per network** (DevNet, TestNet, MainNet). Each requires:

| Component | Specification |
|-----------|--------------|
| **Compute** | VM or Kubernetes cluster. Minimum 4 vCPU, 8 GB RAM (16 GB recommended) |
| **Database** | PostgreSQL 14+ (for Private Contract Store). Managed service recommended (AWS RDS, GCP Cloud SQL, Azure Database) |
| **Storage** | 50 GB+ SSD for database, 20 GB+ for container images and logs |
| **Network** | Fixed egress IP address (required for Super Validator whitelisting). Stable inbound/outbound connectivity on port 443 |
| **Container runtime** | Docker Compose 2.26+ (simplest) or Kubernetes cluster with Helm (production recommended) |
| **JDK** | Eclipse Temurin JDK 21 (runs inside Docker containers) |
| **OIDC Provider** | Auth0, Keycloak, or enterprise IdP supporting OAuth 2.0 Client Credentials Grant and Authorization Code Grant |
| **Architecture** | AMD64 or ARM64 supported |

### Cloud Options

| Provider | Recommended Setup |
|----------|-------------------|
| **AWS** | EC2 `t3.xlarge` (4 vCPU, 16 GB) + RDS PostgreSQL + Elastic IP |
| **GCP** | `e2-standard-4` + Cloud SQL PostgreSQL + static external IP |
| **Azure** | `Standard_D4s_v3` + Azure Database for PostgreSQL + public IP |
| **On-prem** | Any Linux server meeting specs above, with static IP and outbound 443 |

### Development Machine (LocalNet / Quickstart)

| Component | Specification |
|-----------|--------------|
| **Docker** | Docker Desktop with 8 GB+ RAM allocated |
| **JDK** | JDK 21+ |
| **Daml SDK** | 2.10+ (for building DAR) |
| **Tools** | `nix`, `direnv` (for CN Quickstart), `jq`, `curl` |
| **OS** | macOS, Linux, or Windows (macOS current — fine) |

---

## Phase 1: LocalNet via CN Quickstart

**Goal:** Run the pricing service in a full Canton environment locally with Canton Coin wallet, OIDC auth, and Global Synchronizer simulation.

**Timeline:** 1–3 days

### Steps

```bash
# 1. Clone the Quickstart
git clone https://github.com/digital-asset/cn-quickstart.git
cd cn-quickstart
direnv allow
cd quickstart

# 2. Install Daml SDK (Quickstart uses its own version)
make install-daml-sdk

# 3. Configure environment
make setup
# When prompted: enable OAuth2, disable Observability, disable TEST MODE

# 4. Build the Quickstart application
make build

# 5. Start all services (Canton node, Super Validator, wallet, etc.)
make capture-logs  # in separate terminal
make start
```

### Integrate the Pricing Service

The Quickstart scaffolds a sample licensing app. Replace or extend it with the pricing service:

1. Copy your Daml source files into the Quickstart's Daml project directory
2. Update the Quickstart's `daml.yaml` to include your modules
3. Rebuild: `make build`
4. The pricing service DAR is now loaded into the local Canton participant

### Verify

```bash
# Open Canton Console
make canton-console

# In the console:
participant.dars.list()
# Should show your package

# Open Daml Shell
make shell
```

### Cleanup

```bash
make stop && make clean-all
```

---

## Phase 2: DevNet

**Goal:** Connect to the real Global Synchronizer infrastructure. Start minting validator liveness rewards.

**Timeline:** 2–7 days (whitelisting), then 1–2 days setup

### Prerequisites from Sponsor

You need from your sponsoring Super Validator:

1. **IP whitelisting** — provide your fixed egress IP; sponsor submits to Super Validators
2. **Onboarding secret** — one-time use, expires 48 hours (on DevNet, can self-generate via API, valid 1 hour)
3. **Sponsor SV URL** — format: `https://sv.sv-1.unknown_cluster.global.canton.network.YOUR_SV_SPONSOR`

### Infrastructure Setup

#### Option A: Docker Compose (simpler, good for DevNet)

```bash
# 1. Provision VM with fixed egress IP
# Verify your IP:
curl -4 ifconfig.me

# 2. Install Docker and Docker Compose 2.26+
docker --version
docker compose version

# 3. Clone Splice deployment artifacts
# (provided by sponsor or from Splice repo)

# 4. Configure .env with:
#    - SPONSOR_SV_URL
#    - ONBOARDING_SECRET
#    - Party hint (format: tokenisys-validator-1)
#    - PostgreSQL connection details
#    - OIDC configuration (Auth0 or your IdP)

# 5. Verify connectivity to Super Validators
# Must succeed from your egress IP:
set -o pipefail
CURL='curl -fsS -m 5 --connect-timeout 5'
for url in $($CURL https://scan.sv-1.unknown_cluster.global.canton.network.sync.global/api/scan/v0/scans | jq -r '.scans[].scans[].publicUrl'); do
  echo -n "$url: "
  $CURL "$url"/api/scan/version | jq -r '.version'
done
# Need 2/3 of SVs reachable

# 6. Start the validator
./start.sh -s "<SPONSOR_SV_URL>" -o "<ONBOARDING_SECRET>"
# Add -a flag if OIDC auth is configured
```

#### Option B: Kubernetes + Helm (production recommended)

```bash
# 1. Provision Kubernetes cluster with:
#    - Fixed egress IP (NAT gateway or static IP on nodes)
#    - Ingress controller (nginx or similar)
#    - PostgreSQL (managed service or StatefulSet)
#    - Cert-manager for TLS

# 2. Install Splice Helm charts
# (from Splice repo or sponsor-provided artifacts)

# 3. Configure values.yaml with:
#    - Sponsor SV URL and onboarding secret
#    - PostgreSQL connection
#    - OIDC provider configuration
#    - Resource limits (CPU, memory)
#    - Party hint

# 4. Deploy
helm install validator ./splice-validator -f values.yaml

# 5. Verify validator is running and connected
kubectl logs -f deployment/validator-app
```

### OIDC Setup (Required)

The validator needs two OAuth flows:

| Flow | Purpose | Used By |
|------|---------|---------|
| **Client Credentials Grant** | Machine-to-machine auth between validator components | Validator app backend → Canton participant |
| **Authorization Code Grant** | User login to wallet UI and Canton Name Service UI | Browser-based access |

**Auth0 quickstart:**
1. Create an Auth0 tenant
2. Create a Machine-to-Machine application (client credentials)
3. Create a Regular Web Application (authorization code)
4. Configure callback URLs: `http://wallet.localhost`, `http://ans.localhost`
5. Set JWT audience to `https://canton.network.global` initially

### Upload and Vet the Pricing Service DAR

Once the validator is running on DevNet:

```bash
# Build the DAR on your dev machine
cd dalet-option
daml build
# Output: .daml/dist/dalet-option-1.0.0.dar

# Copy DAR to the validator
scp .daml/dist/dalet-option-1.0.0.dar user@validator-host:/path/to/

# On the validator, open Canton Console
# (via make canton-console or kubectl exec)

# Upload
participant.dars.upload("/path/to/dalet-option-1.0.0.dar")

# Find the package ID
participant.packages.find("Main")
// Returns package ID, e.g. "abc123def456..."

# Vet the package (topology transaction — recorded on ledger)
participant.topology.vetPackage("abc123def456...")

# Verify
participant.packages.list().filter(_.name.contains("dalet"))
```

### Register Parties

```scala
// In Canton Console:

// Create the operator party
val tokenisys = participant.parties.enable("Tokenisys")

// For testing, create a client party on the same node
val tradingDesk = participant.parties.enable("TradingDesk")

// In production, client parties would be on their own participant nodes
```

### Test on DevNet

```scala
// In Canton Console — create the service
import com.daml.lf.data.Ref.QualifiedName

// Or use Daml Script against the running ledger:
// daml script --dar .daml/dist/dalet-option-1.0.0.dar \
//   --script-name ServiceTest:testService \
//   --ledger-host localhost --ledger-port 6865
```

### Verify Validator Liveness

Once connected, the validator automatically participates in consensus and earns liveness rewards in Canton Coin (CC). Check via:
- Canton Coin Scan Web UI (accessible via SV VPN)
- Wallet UI at `http://wallet.localhost` (if auth configured)

**DevNet resets every 3 months.** Data is not preserved. Use for testing and integration only.

---

## Phase 3: TestNet

**Goal:** Production staging. Validate upgrades before MainNet.

**Timeline:** 1–2 weeks (Tokenomics Committee review)

### Steps

1. **Apply:** Sponsor submits request to GSF Featured Applications and Validators Committee, or apply directly at `https://sync.global/validator-request/`
2. **Wait:** Typical review ~2 weeks
3. **Once approved:** Provide a **separate** egress IP for TestNet (must be distinct from DevNet IP)
4. **Deploy:** Same process as DevNet but pointing to TestNet SV URLs
5. **Request onboarding secret** from sponsor (manual for TestNet, not self-serve)

TestNet uses the same infrastructure as MainNet and does not reset. Upgrades hit TestNet before MainNet.

---

## Phase 4: MainNet

**Goal:** Production. Real CC rewards. Featured app status.

**Timeline:** After TestNet validation

### Steps

1. **Approval:** Same committee as TestNet (often approved simultaneously)
2. **Egress IP:** Third distinct IP for MainNet
3. **Deploy:** Production-hardened configuration:
   - PostgreSQL with automated backups
   - OIDC with production credentials (not self-signed tokens)
   - Monitoring and alerting
   - Regular database backups (critical — Super Validators cannot recover your app data)
4. **Upload and vet DAR** (same process as DevNet)
5. **Register production parties**

### Featured Application Status

To earn featured app CC rewards (62% of total reward pool, shared among featured apps):

1. Sponsor submits featured app request to GSF
2. Committee reviews application utility and transaction generation
3. Once approved, `RequestPrice` / `RequestCDF` / `RequestRisk` transactions generate activity markers
4. CC rewards mint proportional to activity weight vs total network activity

---

## Production Hardening Checklist

### Security

- [ ] OIDC configured with production credentials (not self-signed tokens)
- [ ] Canton Admin API not exposed publicly (no auth by default)
- [ ] Database access restricted to validator containers only
- [ ] TLS on all external endpoints
- [ ] Key backup stored securely — loss of keys = loss of CC

### Reliability

- [ ] PostgreSQL automated daily backups
- [ ] Identity backup stored off-node (Super Validators can recover CC from identity backup)
- [ ] Container restart policies configured
- [ ] Monitoring for validator liveness (< 50 rounds missed for compliance)
- [ ] Alerting on node disconnection

### Operational

- [ ] 24/7 reachable technical contact (required for node operators hosting others)
- [ ] Upgrade procedure tested on DevNet before MainNet
- [ ] Documented runbook for disaster recovery
- [ ] Log retention configured

---

## Client Onboarding

For each new client using the pricing service:

### Same Participant (simplest for testing)

```scala
// Register client party on your participant
val newClient = participant.parties.enable("ClientFirmName")

// Client can access via Ledger API (gRPC port 6865)
// or HTTP JSON API (port 7575)
```

### Separate Participant (production — each client runs their own node)

1. Client deploys their own Canton participant node
2. Client uploads and vets the same `dalet-option-1.0.0.dar`
3. Both participants connect to the same sync domain (Global Synchronizer or private)
4. Operator creates `ServiceProposal` → Client exercises `AcceptService`
5. Sub-transaction privacy ensures each client's pricing activity is invisible to others

---

## Key Reference Links

| Resource | URL |
|----------|-----|
| Splice docs (validator deployment) | `https://docs.sync.global/` |
| CN Quickstart repo | `https://github.com/digital-asset/cn-quickstart` |
| Digital Asset build docs | `https://docs.digitalasset.com/build/` |
| Validator request form | `https://sync.global/validator-request/` |
| Canton Foundation validators | `https://canton.foundation/validators/` |
| Canton Network connect | `https://canton.network/connect` |
| Splice GitHub (open source) | `https://github.com/hyperledger-labs/splice` |
| Daml SDK docs | `https://docs.daml.com/` |

---

## Summary: Timeline to Production

| Phase | Duration | Blocker |
|-------|----------|---------|
| LocalNet (Quickstart) | 1–3 days | None — runs locally |
| DevNet whitelisting | 2–7 days | Sponsor submits IP |
| DevNet live | 1–2 days | Onboarding secret |
| TestNet approval | 1–2 weeks | GSF Committee review |
| MainNet approval | 1–2 weeks | GSF Committee review |
| Featured app status | 1–2 weeks | GSF Committee review |
| **Total** | **~4–8 weeks** | Sponsorship (secured) |

---

*Tokenisys (The Dark Sole Enterprise Ltd) — February 2026*
