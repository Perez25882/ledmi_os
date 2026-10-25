# Financial contract reproductions

Tests assert healthy behavior against actual code and installed SDK/SQL contracts. They remain red while defects exist. Across **30 dedicated cases**, **20 assertions reproduce failures**, **10 pass**, and **0 implemented cases are blocked in the final runs**. Case counts are not counts of distinct audit defects or a revised Phase 0 severity census.

## Mobile boundary

`flutter_billing_app-main/test/phase1a/mobile_financial.contract.dart` invokes the real checkout/refund/shift/queue services and installed Supabase SDK. Only connectivity is overridden. MockClient captures all HTTP; real temporary Hive persistence is closed/reopened in the retry test. Fictional credentials and a reserved `.invalid` address never reach the network. [Final output](evidence/mobile-contract-tests.txt) and [method report](mobile-task-report.md) document the fixture.

| Finding | Status | Observed contract |
| --- | --- | --- |
| M-01, five service results | Reproduced failure (5) | Cash/refund/open-shift scalar UUIDs, close-shift null and intent list reach code expecting `.error`, producing NoSuchMethodError. |
| M-02 | Reproduced failure (1) | Transmitted sale key differs from durable fallback key after Hive reopen for the same ambiguous acknowledgement. |
| M-05 online | Reproduced failure (1) | GHS4 cash + GHS6 MoMo on a GHS10 sale sends a full GHS10 cash-finalization request before the separate decode error. |
| M-05 offline | Reproduced failure (1) | The queued sale loses cash/MoMo tender attribution instead of retaining it or safely rejecting the unsupported split. |
| M-09 initial request | Reproduced failure (1) | First refund request omits the durable fallback identity. |
| M-09 queued replay | Reproduced failure (1) | Two real queue replays transmit `[null, null]` refund keys rather than the stored key. |
| SDK scalar/list controls | Verified passing behavior (2) | SDK correctly decodes UUID String and RETURNS TABLE List; the service assumptions cause the mismatch. |

These tests prove transmitted/persisted contracts. They do not execute database duplicate commits or provider capture. The downstream split-payment intent amount after M-01 aborts, real MoMo authorization/settlement and hardware interruption behavior remain **static findings not yet reproduced** by this suite.

## Database boundary

`scripts/phase-1a/contracts.cjs` executes the unchanged migration functions on the owned cluster with fictional tenants. API probes use transaction-local roles and JWT claims. Direct writes use an explicitly modeled base-table DML grant profile, not a claimed production ACL. Concurrent probes use two real SQL sessions, lock a stock row with a third session, verify both calls are blocked with `pg_blocking_pids`, then release and inspect committed stock/log/refund state. No replacement financial algorithm or function instrumentation is used. Unexpected infrastructure errors are classified as blocked, not financial reproductions.

| Finding / control | Status | Final run evidence |
| --- | --- | --- |
| B-01 | Reproduced failure | First fictional capture finalizes; second same-branch/day finalization raises 22P02, empty-string integer conversion. |
| B-02 | Reproduced failure | Quick-sale intent is created; captured finalization raises P0001 for missing inventory with NULL product. |
| B-04 | Reproduced failure | Concurrent +5/+7 receiving from 10 leaves 15, expected 22; both movements logged. Which writer wins may vary on rerun. |
| B-05 | Reproduced failure | Same-key concurrent +5 creates 2 movement logs, expected 1; stock is 15. Do not infer a doubled stock increase: the lost update can mask it. |
| B-06 | Reproduced failure | Concurrent refunds record total quantity 2 against original sold quantity 1. |
| B-07 | Reproduced failure | Cashier directly inserts a successful payment under modeled DML grants; independent persisted count is 1. |
| B-08 cart | Reproduced failure | Branch-scoped cashier relocates an active cart to an unassigned branch. |
| B-08 inventory | Verified passing behavior | Tested branch-scoped manager cannot relocate inventory; original branch is preserved. This narrows the earlier static risk. |
| B-09 checkout / refund | Reproduced failures (2) | Accountant without process_sales can perform both operations. |
| B-16 | Reproduced failure | Receiving accepts another tenant's product and creates one cross-tenant product inventory row in the caller's branch. |
| Stable cash key | Verified passing behavior | Same key returns the same sale UUID and deducts stock once (10 to 9). |
| Tenant / branch reads | Verified passing behavior (2) | Cashier sees 0 inventory rows from another tenant or unassigned branch. |
| Outsider / anonymous receiving | Verified passing behavior (2) | Both denied by tested stock RPC boundary. |
| Service finalizer boundary | Verified passing behavior | Authenticated role cannot execute service-only finalizer. |
| Valid owner receiving | Verified passing behavior | Same-tenant receiving changes stock 10 to 12. |

The machine-readable [db-contract-results.json](evidence/db-contract-results.json) has **10 reproduced failures, 8 passing behaviors, 0 blocked**, plus expected/actual values and lock-barrier observations. It matches run ID in [database-isolation.json](evidence/database-isolation.json). Mobile adds ten failures and two controls. These deliberate red suites are distinct from the now-green original 46 tests.

Remaining **static findings not yet reproduced** include broader variants of the audit defects outside these inputs, hosted API/JWT admission, provider event delivery, crash recovery on actual devices and full POS-to-dashboard settlement. No final case is labeled blocked merely because it correctly detects a financial failure. Fixing those defects requires a separately authorized phase; no financial migration, mobile service or production payment function was repaired here.
