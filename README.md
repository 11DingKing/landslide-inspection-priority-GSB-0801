# Landslide Inspection Priority Service

An explainable prioritisation service for geological-hazard (landslide)
inspection after sustained heavy rainfall. Frontline teams need to decide, from
a large pool of hazard points, **which ones to inspect first today** — and the
ranking has to be defensible, reproducible, and resistant to two failure modes:

1. **A closed road does not make the risk go away.** Road inaccessibility must
   affect *scheduling only*, never the risk score or level.
2. **A new scoring strategy must not silently rewrite yesterday's judgement.**
   Scoring is versioned and every historical evidence snapshot can be replayed
   against the exact policy version that produced its original score.

Built with **Ruby 3.4**, **Rails 8 (API mode)** and **PostgreSQL**.

---

## Domain model

| Model | Purpose | Key guarantees |
|-------|---------|----------------|
| `HazardPoint` | A monitored hazard location. | Locked category vocabulary (`cut_slope_housing`, `road_slope`, `registered_hazard`). |
| `EvidenceSnapshot` | An **immutable** record of the facts at one instant (`captured_at`). | Cannot be updated or destroyed; a SHA-256 `content_digest` fingerprints the frozen facts. |
| `ScoringPolicy` | A **versioned**, declarative rule set (`definition` JSONB). | At most one *published* policy per `effective_at` instant (DB partial-unique index). |
| `PriorityScore` | The materialised, explainable result of scoring one snapshot with one policy. | DB check constraints enforce component ranges **and** `total = sum(components)`. |

### Locked scoring contract

Component names and ranges are **fixed** and enforced in the database:

| Component | Range | Driven by |
|-----------|-------|-----------|
| `rainfall` | 0–40 | 24h rainfall (mm) |
| `history`  | 0–25 | historical event count |
| `recency`  | 0–20 | days since last inspection (max when never inspected) |
| `exposure` | 0–15 | hazard category |
| **`total`** | **0–100** | **exact integer sum of the four** |

`risk_level` ∈ `low | moderate | high | extreme` is derived from `total` only.
`scheduling_status` ∈ `schedulable | blocked` is the **only** thing a closed
road changes.

### Where scoring lives (and doesn't)

All scoring rules live in **one place**: the plain-Ruby `Scoring::Engine`
(`app/scoring/scoring/engine.rb`), a pure function of *(frozen facts, policy
definition)*. Controllers and ActiveRecord callbacks contain **no scoring
logic** — callbacks enforce immutability only; controllers translate domain
errors to HTTP. This is what makes historical replay and policy versioning safe.

---

## Design decisions for the hard cases

| Requirement | How it is met |
|-------------|---------------|
| **Reject overlapping policies / pick one deterministic version** | A partial-unique index on `effective_at WHERE status='published'` makes the database reject a second concurrent publish at the same instant (→ HTTP `409`). Selection rule: the published policy with the greatest `effective_at ≤ captured_at` — a single, deterministic winner. |
| **Concurrent compute of the same snapshot** | `PriorityScore` has a unique index on `(evidence_snapshot_id, scoring_policy_id)`; the materializer `upsert`s onto it, so racing workers converge to one identical row. |
| **Replay old snapshots** | Snapshots are immutable; the materializer accepts an explicit `policy:` so any historical version can be re-run to reproduce the original numbers byte-for-byte. |
| **Explanation sum == total, strictly** | Integer components + a DB check constraint `total = rainfall+history+recency+exposure`; the presenter re-asserts the sum at serialization time. |
| **Blocked road can't zero out risk** | The engine derives risk from the intrinsic total and sets `scheduling_status = "blocked"` independently; scores and risk are untouched. |
| **Sort ≥ 10k points; stable pagination under continuous equal-score writes** | Keyset (cursor) pagination ordered by `(total_score DESC, hazard_point_id ASC)` on an immutable id, backed by a matching composite index. New equal-scored rows never reshuffle already-returned pages. |

---

## Prerequisites (native, no Docker)

- Ruby **3.4.x** (`ruby -v`)
- PostgreSQL **14+** running locally and reachable over `localhost:5432`
- A PostgreSQL superuser role named `postgres` (Homebrew default)

The database connection reads `PGUSER` (default `postgres`), `PGPASSWORD`
(default empty), `PGHOST` (default `localhost`) and `PGPORT` (default `5432`).
Override any of them via environment variables — no need to edit
`config/database.yml`.

```bash
# macOS / Homebrew example
brew services start postgresql@17
```

## Install

```bash
bundle install
```

If the `pg` gem fails to build its native extension:

```bash
gem install pg -- --with-pg-config=$(brew --prefix)/bin/pg_config
bundle install
```

## Database setup

```bash
bin/rails db:create      # create dev + test databases
bin/rails db:migrate     # apply migrations
bin/rails db:seed        # load the 3 scenario points + baseline policy
```

The seed prints the resulting queue, e.g.:

```
Seeded 3 hazard points, policy 2026.08.01-baseline.
  HZ-CUTSLOPE-001      total= 93 risk=extreme  scheduling=schedulable
  HZ-ROADSLOPE-002     total= 50 risk=moderate scheduling=blocked
  HZ-REGISTERED-003    total= 33 risk=low      scheduling=schedulable
```

Note `HZ-ROADSLOPE-002`: the road is closed, so it is `blocked` for scheduling,
yet its risk stays `moderate` (total 50) — **not** zeroed.

## Run the tests

```bash
bin/rails test
```

The suite covers every invariant called out above: the exact sum, the locked
component ranges, immutability, deterministic policy selection, overlap
rejection (including a concurrent-publish race), idempotent concurrent compute,
historical replay, a ≥10k-point ordering pass, and stable pagination under
continuous equal-score writes.

## Start the server

```bash
bin/rails server        # http://localhost:3000
```

Health check: `GET /up`.

---

## API

Base path: `/api/v1`. Full contract in [`docs/openapi.yaml`](docs/openapi.yaml).

| Method & path | Purpose |
|---------------|---------|
| `GET/POST /hazard_points` | List / create hazard points |
| `GET /hazard_points/:id` | Show a hazard point |
| `GET/POST /hazard_points/:id/evidence_snapshots` | List / capture snapshots (create only — immutable) |
| `GET /evidence_snapshots/:id` | Show a snapshot |
| `POST /evidence_snapshots/:id/priority` | **Compute** a score (optionally `?scoring_policy_id=` to replay a version) |
| `GET/POST /scoring_policies` | List / create (draft) policies |
| `POST /scoring_policies/:id/publish` | **Publish** (409 on overlapping `effective_at`) |
| `GET /scoring_policies/:id/queue` | **Queue**: stable, keyset-paginated ranking (`?limit=&cursor=&scheduling_status=`) |
| `GET /priority_scores/:id/explanation` | **Explain**: per-component breakdown + policy version |

### Example: compute and explain

```bash
# Compute a priority score for snapshot 2 (uses the authoritative policy)
curl -X POST http://localhost:3000/api/v1/evidence_snapshots/2/priority
```

```jsonc
{
  "hazard_point": { "code": "HZ-ROADSLOPE-002", "category": "road_slope" },
  "scoring_policy": { "version": "2026.08.01-baseline" },
  "components": [
    { "name": "rainfall", "score": 22, "max": 40 },
    { "name": "history",  "score": 0,  "max": 25 },
    { "name": "recency",  "score": 18, "max": 20 },
    { "name": "exposure", "score": 10, "max": 15 }
  ],
  "total_score": 50,
  "components_sum": 50,          // strictly equal to total_score
  "risk_level": "moderate",
  "scheduling_status": "blocked", // road closed -> scheduling only
  "road_blocked": true
}
```

### Example: paginated queue

```bash
curl "http://localhost:3000/api/v1/scoring_policies/1/queue?limit=100"
# -> { "items": [...ordered by total desc, hazard_point_id asc...],
#      "next_cursor": "50:2" }   # pass back as ?cursor=50:2
```

---

## Project layout

```
app/
  controllers/api/v1/     # thin HTTP layer, no scoring logic
  models/                 # AR models; callbacks enforce immutability only
  scoring/scoring/        # PORO domain: engine, materializer, queue, presenter
db/migrate/               # schema + all invariant check constraints
docs/openapi.yaml         # API contract
test/                     # engine, model, service and integration tests
```
