# Phase 1A build and test results

## Build repair: W-20

Installed Next.js is 16.1.6. `app/dashboard/sales/page.tsx` now accepts optional `searchParams: Promise<{ branch?: string; from?: string; to?: string }>`, awaits it once and uses the resulting filters. This is the only production application change. Authorization, filtering and exports were not redesigned.

A fresh isolated webpack build before the edit reproduced the generated PageProps error: synchronous search parameters lacked Promise methods. Afterward the clean webpack production build passed, including framework type validation and 42/42 static pages. Lint passed with 0 errors and 46 existing warnings; the post-build type check also passed. All runs copied zero environment files. See [before result](evidence/web-before-webpack-20261025-223721-result.json), [after result](evidence/web-after-webpack-20261025-223748-result.json) and their adjacent logs.

The unchanged default `npm run build` uses Turbopack and fails in this isolated Windows layout because the dependency junction points outside its filesystem root. The verified command is `npm run build -- --webpack`, invoked by the environment helper. We do not claim a successful default Turbopack build. Existing middleware, Supabase Edge/Node-version and cache warnings remain visible.

## Webhook fixture repair

The original two failures first stopped at an absent fake `.update().eq().is()` chain. Both synchronized webhook test copies now implement that chain and assert the business-ID backfill data and filters. The next run exposed a second fixture problem: the fake intent used 50,000 as database GHS instead of 500 GHS. Its value is now 500; the provider event remains 50,000 pesewas. Handler production code and financial assertions are unchanged. Tests are neither skipped nor weakened.

Evidence preserves the progression: [original failures](evidence/webhook-before.txt), [builder-only correction](evidence/webhook-builder-fixed.txt), [final webhook run](evidence/webhook-tests.txt). `scripts/verify-edge-functions.js` confirms all eight mirrored function files match.

## Executed results

| Check | Result | Evidence |
| --- | --- | --- |
| Existing Flutter suite | 36 pass, exit 0 | [mobile-existing-tests.txt](evidence/mobile-existing-tests.txt) |
| Existing Paystack initiation suite | 5 pass, exit 0 | [initiate-tests.txt](evidence/initiate-tests.txt) |
| Existing Paystack webhook suite | 5 pass, exit 0 | [webhook-tests.txt](evidence/webhook-tests.txt) |
| New mobile contracts | 2 controls pass, 10 assertions fail, exit 1 | [mobile-contract-tests.txt](evidence/mobile-contract-tests.txt) |
| New database contracts | 8 pass, 10 assertions fail, 0 blocked, exit 1 | [db-contract-results.json](evidence/db-contract-results.json) |
| Isolation helper controls | 3 pass, exit 0 | [isolation-tests.txt](evidence/isolation-tests.txt) |
| New mobile test directory analyzer | No issues, exit 0 | [mobile-contract-analyze.txt](evidence/mobile-contract-analyze.txt) |
| Dashboard lint / webpack build / generated type check | All exit 0 | [web result](evidence/web-after-webpack-20261025-223748-result.json) |
| Schema assertions | Pass: required RLS tables, core functions, selected constraints/indexes and 23 history entries | [schema-validation.json](evidence/schema-validation.json) |

The original 46-test baseline is now **46 passing / 0 failing**, compared with Phase 0's 44/2. The 30 additional financial/authorization contract cases are a separate **10 passing / 20 failing** baseline; these are healthy-behavior assertions detecting unresolved defects. They must not be presented as a green financial suite. Isolation tests are a further three infrastructure controls, not financial cases.

The mobile `.contract.dart` file runs explicitly and is outside default `_test.dart` discovery; no test has a skip annotation or an inverted expected-failure assertion. The final mobile run has no fixture/compile errors. The superseded first fixture diagnostic is retained separately and not counted as a defect reproduction. Targeted analyzer success does not replace full-project Flutter analysis or resolve the six pre-existing informational audit findings.

Review covered general code safety, JavaScript helpers, React route compatibility and Flutter fixture causality. Identified helper issues in PostgreSQL environment handling, cleanup, connection lifetime and concurrency assertions were corrected. Migration SQL, production payment handlers and mobile financial services were not modified. Reproduction commands and environment limits are in [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md).
