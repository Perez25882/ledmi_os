# Phase 1A evidence notes

Final database run ID: `6564104b-5730-45f7-8bae-7e20263bd064`. `database-isolation.json` and `db-contract-results.json` match. The token-bearing manifest is outside the repository; `database-manifest-path.txt` records only its local path and is not a portable credential. Reproduce by creating a new cluster as described in the environment report.

- Final setup: `database-setup-final.txt`; successful shutdown: `database-teardown.txt`.
- `migrations-first.json` and `migrations-tracked-repeat.json`: first application and tracked repeat; `migration-raw-repeat.json`: separate rolled-back raw reapplication checks.
- `db-contract-grants-before.json`: vanilla native authenticated SELECT/INSERT snapshot **before** modeled DML grants. `database-catalog.json`: full final catalog **after** explicit base-table grant fixture. Neither claims production ACLs.
- `schema-validation.json`: final required-object assertions; `db-contract-results.json`: final 18 SQL cases, 10 reproduced failures / 8 passes / 0 blocked.
- `mobile-contract-tests.txt`: final 12 mobile cases, 10 failing assertions / 2 passing SDK controls. `mobile-existing-tests.txt`: original 36 passing tests. `mobile-contract-analyze.txt`: clean targeted analysis.
- `web-after-webpack-20261025-223748-result.json` and associated logs: passing final isolated lint/build/type check. Before-webpack files reproduce W-20. Before-default files expose the Turbopack junction limitation.
- `webhook-tests.txt` and `initiate-tests.txt`: final 5+5 passing Deno tests. `webhook-before.txt` and `webhook-builder-fixed.txt` preserve intermediate builder/unit fixture failures, not final results.
- `isolation-tests.txt`: final three passing infrastructure controls. `isolation-before.txt` and `isolation-review-red.txt` are superseded test-first/review diagnostics.
- `mobile-contract-fixture-first-run.txt` is superseded fixture diagnostics, not financial evidence. `database-complete-setup.txt`, `database-stop-first.txt`, and initial setup output are earlier controlled setup attempts. Final fresh setup is authoritative. Native subprocess logs can be overwritten by teardown; they are auxiliary diagnostics.

Final financial suites deliberately exit 1. An unexpected exception must not be counted as a reproduced defect; SQL results distinguish blocked cases, with a top-level infrastructure failure returning 2. Test data are fictional. Generated source definitions/catalog details describe repository SQL and local fixtures only. Console text logs have trailing whitespace and surplus final blank lines trimmed for publication; result text and assertions are preserved.
