# Phase 1A environment setup

Baseline: `e4983adcfb11ac4873b84815010596428e76769a`, branch `codex/phase-1a-verification`. The lead fetched origin before starting and created this dedicated branch without resetting local work. Pre-existing `docs/launch-audit/`, `brag-output/` and `scripts/list-users.js` are preserved outside the Phase 1A commit. The locked PRD and team charter remain unchanged.

## Verified environment

Docker Desktop's Linux-engine pipe was unavailable. The supported alternative used here is a newly initialized native PostgreSQL 17.10 cluster, using installed binaries at `C:/Program Files/PostgreSQL/17/bin`. Existing Node, `scripts/node_modules/pg`, dashboard dependencies, Deno cache and Flutter SDK at `C:/tools/flutter` were reused. No application dependencies were installed or upgraded.

The database helper never reads dotenv or database URL variables. Its manifest must name a newly owned OS temporary directory, `127.0.0.1`, a high port, `phase1a_admin`, and a unique `phase1a_<uuid>` database. It rejects redirected filesystem paths. Connections verify the live data directory, cluster name, address and port, then a private run/token marker before application mutations. All ambient `PG*` settings are removed during client construction/native-tool execution; the caller's environment is restored. Three isolation controls pass in [isolation-tests.txt](evidence/isolation-tests.txt).

The final fresh setup used run `6564104b-5730-45f7-8bae-7e20263bd064`, port `61474`. Public metadata is in [database-isolation.json](evidence/database-isolation.json). The token-bearing manifest remains outside the repository; only its path is recorded. This is a disposable local trust-auth cluster, bound to loopback, containing fictional data. It is suitable for this single-machine verification, not deployment or an untrusted shared host.

Only minimal Supabase database boundaries are modeled: NOLOGIN `anon`/`authenticated`, BYPASSRLS `service_role`, `auth.users`, `auth.uid()` and `auth.jwt()`. This does not start Supabase Auth, PostgREST, Realtime, Storage or pg_cron. JWT claims are explicitly set by the test harness; signature validation is outside these tests.

## Migration entry point

The existing repository runner is `scripts/apply-migrations.js`: sorted `infra/supabase/migrations/*.sql`, then sorted `infra/supabase/seed/*.sql`, with filename tracking in `schema_migrations`. `database_architecture/` remains reference only. The cloud runner loads dotenv, forces IPv6 and disables TLS certificate verification, so it was inspected but not executed against an unknown configured target.

The Phase 1A entry point is `scripts/phase-1a/database.cjs migrate`: it executes the same unchanged authoritative files and filename tracking against the manifest-verified local cluster, with an explicit transaction per file. This verifies the migration SQL, ordering and tracking semantics; it does not validate the original runner's cloud transport, failure atomicity or Supabase CLI behavior.

## Exact commands

Run from `C:/Users/DELL/Desktop/POS` in PowerShell. Stop on unexpected nonzero exits. The financial contract command is intentionally expected to return 1; inspect its JSON statuses separately from infrastructure failures (exit 2).

```powershell
node --test scripts/phase-1a/isolation.test.cjs
node scripts/phase-1a/database.cjs setup
$phaseManifestPath = (Get-Content docs/phase-1a/evidence/database-manifest-path.txt -Raw).Trim()
node scripts/phase-1a/database.cjs migrate $phaseManifestPath first
node scripts/phase-1a/database.cjs inspect $phaseManifestPath
node scripts/phase-1a/database.cjs migrate $phaseManifestPath tracked-repeat
node scripts/phase-1a/database.cjs raw-repeat $phaseManifestPath
node scripts/phase-1a/contracts.cjs $phaseManifestPath
node scripts/phase-1a/database.cjs inspect $phaseManifestPath
node scripts/phase-1a/database.cjs stop $phaseManifestPath
```

Use a fresh setup for an independent run. The first contract invocation records vanilla grants, then adds its explicit base-table DML fixture. A second invocation on the same cluster would record those modeled grants as its starting state. Evidence files are overwritten by later runs; archive a run's evidence first if comparison is needed. Each contract uses new fictional UUIDs, without deleting existing data.

Teardown validates live cluster identity before stopping only that server. It retains the cluster and test data, and performs no directory deletion. [database-teardown.txt](evidence/database-teardown.txt) records successful teardown of the final run. Earlier setup attempts exposed Windows subprocess/port-format issues; the final script completed a separate fresh setup end to end. Failure cleanup is source-reviewed; deliberately injected partial-startup failure was not executed.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/phase-1a/web-baseline.ps1 -Bundler Webpack -Checks -RunLabel verified
Push-Location flutter_billing_app-main
& C:/tools/flutter/bin/flutter.bat test --no-pub --reporter expanded
& C:/tools/flutter/bin/flutter.bat test --no-pub --reporter expanded test/phase1a/mobile_financial.contract.dart
& C:/tools/flutter/bin/flutter.bat analyze --no-pub test/phase1a
Pop-Location
Push-Location infra/supabase/functions/paystack-initiate
deno test --cached-only --allow-env test.ts
Pop-Location
Push-Location infra/supabase/functions/paystack-webhook
deno test --cached-only --allow-env test.ts
Pop-Location
node scripts/verify-edge-functions.js
```

The web helper copies source without `.env*`/`.npmrc`, uses existing dependencies through a junction, clears inherited credentials, supplies fictional unavailable loopback endpoints and disables telemetry. It validates and cleans only its own temporary copy. Default Turbopack cannot follow this dependency junction outside its root; the verified path explicitly uses webpack. Mobile HTTP is intercepted locally; Deno has no network permission.

## Environment-variable inventory

No real values from this table are required for these isolated tests. Existing application environment files are neither copied into builds nor committed.

| Scope | Names | Phase 1A treatment |
| --- | --- | --- |
| Native database helper | `PHASE1A_PG_BIN` (optional) | Local binary directory override only; otherwise installed default path. Target comes exclusively from owned manifest. |
| Existing cloud migration runner | `DATABASE_URL`, `POSTGRES_URL`, `SUPABASE_DATABASE_URL` | Not used; never substitute an existing target. |
| Flutter | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PAYSTACK_PUBLIC_KEY` | Mock transport and fictional identities; no dotenv. |
| Dashboard public configuration | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | Helper supplies fake values as needed, no production files. |
| Server/Edge integrations | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `PAYSTACK_SECRET_KEY`, `PAYSTACK_WEBHOOK_SECRET`, `NVIDIA_API_KEY`, `NVIDIA_MODEL`, optional `NVIDIA_API_URL`, `VAPID_PRIVATE_KEY` | Absent/blank or local test fixtures only. Never expose service/provider secrets to a mobile/public bundle. |

Production credentials, customer records, deployment infrastructure and payment providers were not used. Native cluster verification remains narrower than a complete disposable Supabase stack.
