# Phase 1A completion report

Phase 1A established an isolated verification baseline and reproducible regressions. It does **not** establish financial correctness or readiness to launch. Work stops here; Phase 1B, financial remediation, Expo implementation and deployment require explicit founder approval.

Starting commit: `e4983adcfb11ac4873b84815010596428e76769a`. Working branch: `codex/phase-1a-verification`. Origin was fetched and existing local work preserved. Completed Phase 1A files are published to that working branch under the standing commit/push instruction; no merge or production deployment is part of this phase.

## Verified outcomes

| Acceptance area | Outcome |
| --- | --- |
| Isolation | Fresh native PostgreSQL 17.10 cluster bound to loopback, manifest/live-identity/private-marker checks, three passing isolation controls; no configured cloud database used. Owned server stopped; fictional data retained. |
| Web build | W-20 corrected with awaited Promise search parameters. Clean webpack production build, lint and generated type check pass. Default Turbopack remains incompatible with this helper's dependency junction. |
| Existing tests | 36 Flutter + 5 initiation + 5 webhook = **46 pass, 0 fail**. Fake webhook builder and GHS fixture corrected; production payment handlers unchanged. |
| Migrations | 22 authoritative migrations plus role seed apply; tracked repeat skips all 23. Direct SQL replay exposes migration 021 duplicate-policy failure, documented for review. |
| Schema and authorization | 28 application tables have RLS; catalog captures constraints, indexes, functions, policies, triggers and effective grants. Tests distinguish vanilla native grants from modeled API DML grants. |
| Critical contract coverage | **30 dedicated cases: 20 reproduced failures, 10 passing controls, 0 final blocked cases.** Real mobile services/SDK/Hive and real database functions are exercised within stated boundaries. |
| Mobile direction | Expo decision record covers architecture, durability, shared contracts, identity, secure storage, build/hardware constraints and Flutter transition. No Expo app created. |
| Review | General, JavaScript, React and Flutter reviews complete; substantive helper findings corrected and final review approved. |

Only three existing files changed: the sales page and the two mirrored webhook test files. New files are isolated helpers, regression tests and reports/evidence. Financial migrations, mobile production financial services and production Edge Function handlers remain unchanged. The earlier audit's untracked work was preserved outside this phase's commit.

## Remaining failures and verification limits

The dedicated red cases reproduce M-01/M-02/M-05/M-09 and B-01/B-02/B-04/B-05/B-06/B-07/B-08-cart/B-09/B-16 under their documented inputs. B-08 inventory relocation is denied in the tested case, narrowing that earlier static hypothesis. Case counts do not replace the audit's 58-defect census or imply every variant has been reproduced.

Migration 021 is not raw-replay idempotent. No migration was rewritten; a safe remediation proposal is recorded for founder review. The original cloud runner's transport and hosted schema drift were not validated. Native PostgreSQL with minimal auth functions is not a full Supabase stack: Auth/JWT verification, PostgREST, Realtime, Storage, pg_cron and real default grants remain unverified. Modeled direct-write failures must not be represented as observed production ACLs.

Mobile HTTP tests prove outbound payloads and queue identity, not duplicate SQL commits or provider settlement. Bluetooth printers, scanner hardware, real device interruption/recovery, iOS builds and complete offline-to-dashboard payment reconciliation remain untested. Existing lint/framework warnings and full-project Flutter informational findings remain. There are no blocked final implemented contract cases; these broader unexecuted checks are verification limits and future work, not passing assumptions.

No production data/infrastructure, real customer data or live payment operations were used. The database cluster and fictional records were retained after guarded shutdown. Only freshly created web/mobile test temporary copies were cleaned. No existing data was deleted.

## Reports and evidence

1. [Environment setup and commands](ENVIRONMENT_SETUP.md)
2. [Build and test results](BUILD_AND_TEST_RESULTS.md)
3. [Migration verification](DATABASE_MIGRATION_VERIFICATION.md)
4. [Financial contract reproductions](FINANCIAL_CONTRACT_REPRODUCTIONS.md)
5. [Authorization results](AUTHORIZATION_TEST_RESULTS.md)
6. [Expo architecture decision](EXPO_ARCHITECTURE_DECISION.md)
7. This completion report.

[Evidence notes](evidence/README.md) distinguish final results, intermediate fixture diagnostics and grant profiles. [TASK_REPORT.md](TASK_REPORT.md) records the implementation scope and handoff. The next decision is founder review of this baseline and a separately authorized remediation/foundation scope. No next phase has begun.
