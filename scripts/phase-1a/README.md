# Phase 1A verification helpers

Run from the repository root. Full setup, exact commands, expected exits and limits: [ENVIRONMENT_SETUP.md](../../docs/phase-1a/ENVIRONMENT_SETUP.md).

- `database.cjs`: initializes a new owned native PostgreSQL cluster; applies authoritative migrations/seeds with tracking; inspects schema; tests rolled-back raw replay; stops only the verified owned server. It never deletes the retained database directory. Requires preinstalled PostgreSQL and existing `scripts/node_modules/pg`.
- `isolation.cjs`: manifest/path/live-server/private-marker guard and explicit local client construction. No dotenv or configured database URL fallback.
- `isolation.test.cjs`: target rejection, live-identity mismatch and ambient PG-setting controls. Run with `node --test scripts/phase-1a/isolation.test.cjs`.
- `contracts.cjs`: actual SQL financial/authorization probes, fictional tenants and explicit modeled base-table DML profile. Requires the freshly initialized/migrated cluster manifest; returns 1 for detected defects, 2 for a top-level infrastructure failure. It records vanilla grants before its first invocation, so rerun from a fresh setup when comparing native and modeled ACLs.
- `web-baseline.ps1`: copies source without environment files, reuses installed dependencies and runs isolated lint/build/type check. Use `-Bundler Webpack -Checks`; default Turbopack cannot follow this Windows dependency junction.

These helpers are a local test environment, not a deployment runner or a complete Supabase service stack. Evidence outputs are overwritten on repeat runs. Never redirect them to an existing/unknown database, supply production credentials, or treat expected-red contract tests as passing financial certification.
