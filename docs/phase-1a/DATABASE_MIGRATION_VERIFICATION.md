# Database migration verification

## Applied and repeated

The isolated native PostgreSQL 17.10 run applied all **22 unchanged authoritative migrations**, `001_` through `022_`, followed by the one intended role seed: **23 applied, zero failed**. The filename-tracked rerun skipped all 23, with zero new applications. SHA-256 values and per-file statuses are in [migrations-first.json](evidence/migrations-first.json) and [migrations-tracked-repeat.json](evidence/migrations-tracked-repeat.json).

The repository's cloud entry point and this run's safer local adapter are distinguished in [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md). Both consume `infra/supabase/migrations/` and `infra/supabase/seed/`; the cloud runner itself was not executed. The local adapter adds per-file transactions and verifies cluster ownership before use. No SQL from the reference-only `database_architecture/` directory was applied.

Each migration was also reapplied independently inside a rolled-back transaction. **21 reapplications succeeded; `021_branch_scope_enforcement.sql` failed** with SQLSTATE `42710`: `policy "shifts_select" for table "shifts" already exists`. See [migration-raw-repeat.json](evidence/migration-raw-repeat.json). The role seed was tested through tracking, not separately reapplied without tracking. Successful tracking is therefore not a claim that every SQL file is idempotent.

Proposed remediation for founder review: separately approve a narrowly scoped, transactional policy migration that drops/recreates or conditionally replaces the intended named policies, and decide how fresh-install replay of 021 should be supported. Validate both fresh and existing databases and compare effective policies before release. A later migration alone cannot make raw replay of 021 succeed before reaching it. Phase 1A does not rewrite 021 or any financial migration.

## Catalog verification

[database-catalog.json](evidence/database-catalog.json) records columns, constraints, indexes, function definitions/security attributes/effective execution rights, policies, non-internal triggers, table grants, role attributes, default privileges, extensions and migration history. [schema-validation.json](evidence/schema-validation.json) asserts the expected 28 application tables have RLS, eight core RPCs exist, selected payment/invoice uniqueness controls exist, and history has 23 rows.

| Catalog object | Observed |
| --- | --- |
| Public relations | 32: 28 RLS-enabled application tables, non-RLS migration-history table, 2 materialized views, 1 ordinary view |
| Constraints / indexes | 122 / 119 |
| Public functions | 35, including extension functions |
| RLS policies / non-internal triggers | 51 / 19 |
| Extensions | plpgsql, uuid-ossp; no pg_cron |
| Default-privilege catalog entries | None in this fresh native cluster |

Migration history is verification metadata, not an application entity. Views do not have table RLS; migration 020's direct view-access revocations are retained. Counts establish object presence, not exhaustive business correctness. Several SECURITY DEFINER functions retain a null `proconfig` (no function-local search_path); this remains a hardening finding, not a Phase 1A fix.

## Effective grants and schema-drift boundaries

Vanilla PostgreSQL does not reproduce a hosted Supabase project's implicit/default table grants. The original authenticated SELECT/INSERT snapshot is [db-contract-grants-before.json](evidence/db-contract-grants-before.json): base-table DML is absent. The contract harness then explicitly grants base-table DML to modeled API roles, leaving view and function revocations intact, so RLS/write boundaries can actually be exercised. The final full catalog was captured **after that modeled DML profile**. Its table grants are test-fixture grants, not evidence of hosted production ACLs.

Effective function checks account for PUBLIC inheritance. `safe_finalize_sale(uuid)` and `process_payment_capture(uuid,uuid)` are service-only in this cluster. `process_stock_in` and `process_refund` remain executable by anon through PUBLIC; anonymous stock receiving nevertheless fails its internal identity guard in the executed control. See [AUTHORIZATION_TEST_RESULTS.md](AUTHORIZATION_TEST_RESULTS.md).

The local final schema is an ordered clean installation, not a comparison against a live production snapshot. Historical reference schema files and duplicate function deployment directories remain unchanged. The guarded cron path was not exercised without pg_cron. Full Supabase Auth, PostgREST/JWT validation, Realtime and hosted configuration remain unverified. No production credentials or target were used to fill those gaps.
