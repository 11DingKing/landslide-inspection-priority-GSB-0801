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
| `EvidenceSnapshot` | An **immutable** record of the facts at one instant (`captured_at`). | Cannot be updated or destroyed; a SHA-256 `content_digest` fingerprints the frozen facts. An optional `business_key` makes capture idempotent. |
| `ScoringPolicy` | A **versioned**, declarative rule set (`definition` JSONB) valid over a half-open interval `[effective_from, effective_until)`. | Published intervals may never overlap (DB GiST exclusion constraint). A policy can be *bounded* rather than retired. |
| `PriorityScore` | The materialised, explainable result of scoring one snapshot with one policy. | DB check constraints enforce component ranges **and** `total = sum(components)`. At most one `current` score per hazard point (partial-unique index). |
| `QueueSnapshot` / `QueueSnapshotItem` | A **named, immutable** frozen copy of one policy's `current` ranking, captured at build time. | A traversal pinned to a snapshot reads only its frozen items, so concurrent recomputes never cause missed or duplicated rows. |

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
| **Reject overlapping policies / pick one deterministic version** | Policies carry a half-open interval `[effective_from, effective_until)`. A GiST **exclusion constraint** on `tsrange(...)` `WHERE status='published'` makes the database reject any publish/bound whose interval overlaps an existing published one (→ HTTP `409`). Selection rule: the published policy whose interval contains `captured_at` — a single, deterministic winner. |
| **Adjust a policy's coverage without breaking replay** | `bound!` sets `effective_until` on a still-**published** policy instead of retiring it. Snapshots captured before the boundary keep resolving to it, so their scores stay reproducible; a successor takes over from the boundary onward. |
| **Old snapshot binds v1, new snapshot binds v2** | Each snapshot resolves to the policy whose interval contains its immutable `captured_at`. With v1 `[…, boundary)` and v2 `[boundary, …)`, a pre-boundary snapshot binds v1 and a boundary/after snapshot binds v2 — automatically. |
| **Business-key idempotency / conflict** | `EvidenceSnapshot.capture!` compares the `content_digest` of the frozen payload against any existing row for the `business_key`: identical payload returns the same snapshot (idempotent), divergent payload raises a `409` conflict. A unique index + savepoint insert keeps this correct under concurrency. |
| **Exactly one `current` score per point; concurrent compute leaves one** | The materializer takes a per-hazard-point row lock, then flips the `current` flag; a partial-unique index (`WHERE current`) guarantees a single current row. `current` follows the **latest** snapshot, so replaying an older snapshot never steals it. |
| **Concurrent compute of the same snapshot** | `PriorityScore` has a unique index on `(evidence_snapshot_id, scoring_policy_id)`; the materializer `upsert`s onto it, so racing workers converge to one identical row. |
| **Replay old snapshots** | Snapshots are immutable; the materializer accepts an explicit `policy:` so any historical version can be re-run to reproduce the original numbers byte-for-byte. |
| **Explanation sum == total, strictly** | Integer components + a DB check constraint `total = rainfall+history+recency+exposure`; the presenter re-asserts the sum at serialization time. |
| **Blocked road can't zero out risk** | The engine derives risk from the intrinsic total and sets `scheduling_status = "blocked"` independently; scores and risk are untouched. |
| **Sort ≥ 10k points; stable pagination under continuous equal-score writes** | Keyset (cursor) pagination ordered by `(total_score DESC, hazard_point_id ASC)` on an immutable id, backed by a matching composite index. New equal-scored rows never reshuffle already-returned pages. |
| **Stable queue-read traversal across recomputes** | A named `QueueSnapshot` freezes a policy's `current` ranking into immutable items. Paginating it walks only the frozen items with the same keyset cursor, so mid-traversal recomputes that move `current` scores cause no missed or duplicated rows. A **new** snapshot re-reads live state to observe updates, and each frozen item still points at its `priority_score_id`, so explanations replay by the v1/v2 boundary. |

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

The seed prints the resulting policies and scores, e.g.:

```
Policies: 2026.v1 [2026-01-01T00:00:00Z, 2026-08-02T00:00:00Z), 2026.v2 [2026-08-02T00:00:00Z, ∞)
Priority scores (current marked with *):
  * HZ-CUTSLOPE-001    v=2026.v1  total= 93 risk=extreme  scheduling=schedulable
  * RDS-002            v=2026.v2  total= 70 risk=high     scheduling=blocked
  * HZ-REGISTERED-003  v=2026.v1  total= 33 risk=low      scheduling=schedulable
    RDS-002            v=2026.v1  total= 50 risk=moderate scheduling=blocked
```

The seed demonstrates the interval evolution:

- **Policy v1** covers `[2026-01-01, 2026-08-02)`; **v2** takes over from the
  boundary. v1 is *bounded*, not retired, so it still scores its old snapshots.
- **`RDS-002`** has two scores: its pre-boundary snapshot still binds **v1**
  (total 50, replayable), while the boundary snapshot — captured with
  `business_key = evidence-rds-002-20260802-0000`, 210 mm, road still closed —
  binds **v2** (total 70) and is the **current** score.
- The road is closed on both `RDS-002` snapshots, so they are `blocked` for
  scheduling, yet risk stays `moderate`/`high` — **never** zeroed.

## Run the tests

```bash
bin/rails test
```

The suite covers every invariant called out above: the exact sum, the locked
component ranges, immutability, interval-based policy selection, overlap
rejection (including a concurrent-publish race), bounding a policy without
breaking replay, business-key idempotency vs. conflict (including a concurrent
capture race), one-current-per-point under concurrent compute, `current`
following the latest snapshot, idempotent concurrent compute, historical replay,
a ≥10k-point ordering pass, and stable pagination under continuous equal-score
writes.

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
| `GET/POST /hazard_points/:id/evidence_snapshots` | List / capture snapshots (create only — immutable; `business_key` idempotent, 409 on payload conflict) |
| `GET /evidence_snapshots/:id` | Show a snapshot |
| `POST /evidence_snapshots/:id/priority` | **Compute** a score (optionally `?scoring_policy_id=` to replay a version) |
| `GET/POST /scoring_policies` | List / create (draft) policies with `effective_from` / `effective_until` |
| `POST /scoring_policies/:id/publish` | **Publish** (409 on overlapping interval) |
| `PATCH /scoring_policies/:id/bound` | **Bound** a published policy's `effective_until` without retiring it |
| `GET /scoring_policies/:id/queue` | **Queue**: stable, keyset-paginated ranking (`?limit=&cursor=&scheduling_status=&current=`) |
| `POST /scoring_policies/:id/queue_snapshots` | **Build** a named, frozen queue-read snapshot pinned to this policy (body: `name`) |
| `GET /queue_snapshots/:id` | Show a queue-read snapshot (`:id` = numeric id or name) |
| `GET /queue_snapshots/:id/page` | **Paginate** frozen items — stable across recomputes (`?limit=&cursor=`) |
| `GET /priority_scores/:id/explanation` | **Explain**: per-component breakdown + policy version/interval + `current` |

### Example: compute and explain

```bash
# Compute a priority score for snapshot 2 (uses the authoritative policy)
curl -X POST http://localhost:3000/api/v1/evidence_snapshots/2/priority
```

```jsonc
{
  "hazard_point": { "code": "RDS-002", "category": "road_slope" },
  "evidence_snapshot": { "business_key": "evidence-rds-002-20260802-0000" },
  "scoring_policy": {
    "version": "2026.v2",
    "effective_from": "2026-08-02T00:00:00Z",
    "effective_until": null
  },
  "components": [
    { "name": "rainfall", "score": 40, "max": 40 },
    { "name": "history",  "score": 0,  "max": 25 },
    { "name": "recency",  "score": 18, "max": 20 },
    { "name": "exposure", "score": 12, "max": 15 }
  ],
  "total_score": 70,
  "components_sum": 70,          // strictly equal to total_score
  "risk_level": "high",
  "scheduling_status": "blocked", // road closed -> scheduling only
  "road_blocked": true,
  "current": true                 // authoritative score for this point
}
```

### Example: paginated queue

```bash
curl "http://localhost:3000/api/v1/scoring_policies/1/queue?limit=100"
# -> { "items": [...ordered by total desc, hazard_point_id asc...],
#      "next_cursor": "50:2" }   # pass back as ?cursor=50:2
```

### Example: stable queue-read snapshot

```bash
# Freeze v2's current ranking into a named snapshot.
curl -X POST http://localhost:3000/api/v1/scoring_policies/2/queue_snapshots \
  -H 'Content-Type: application/json' -d '{"name":"queue-20260802-01"}'

# Page 1 (by name); then keep paging with the returned cursor.
curl "http://localhost:3000/api/v1/queue_snapshots/queue-20260802-01/page?limit=2"
# -> { "queue_snapshot": "queue-20260802-01",
#      "items": [ ... ], "next_cursor": "70:4" }

# Even if scores are recomputed now, resuming the ORIGINAL cursor returns the
# remaining FROZEN items — no misses, no duplicates:
curl "http://localhost:3000/api/v1/queue_snapshots/queue-20260802-01/page?limit=2&cursor=70:4"
```

---

## Project layout

```
app/
  controllers/api/v1/     # thin HTTP layer, no scoring logic
  models/                 # AR models; callbacks enforce immutability only
  scoring/scoring/        # PORO domain: engine, materializer, queue(+snapshot), presenter
db/migrate/               # schema + all invariant check constraints
docs/openapi.yaml         # API contract
test/                     # engine, model, service and integration tests
```
