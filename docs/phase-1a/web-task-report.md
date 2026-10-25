# Phase 1A web task report

Scope: W-20 sales-route compatibility and isolated web verification only. Baseline: `e4983adcfb11ac4873b84815010596428e76769a`; installed Next.js: `16.1.6`. Existing dependencies were reused; none were installed.

## Changes

- `ledgermindv1-main/app/dashboard/sales/page.tsx`: changed the optional `searchParams` type from `{ branch?: string; from?: string; to?: string }` to `Promise<{ branch?: string; from?: string; to?: string }>`, awaited it once as `filters`, and used `filters` for the existing branch/date lookup and export props. The installed Next.js generated `PageProps` declares `searchParams?: Promise<any>`. Filtering, authorization, calculations, and export behavior were otherwise preserved.
- `scripts/phase-1a/web-baseline.ps1`: copies dashboard source into a unique OS temporary directory, excludes all `.env*`, `.npmrc`, generated/cache/output directories, and dependency directories; creates a dependency junction to the existing installation; checks the isolated copy contains zero environment files; runs the build and optional lint/typecheck; writes per-command logs and JSON exit results; detaches the junction and removes only its verified temporary run directory.

## Reproduction

From the repository root, using Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/phase-1a/web-baseline.ps1 -RunLabel default
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/phase-1a/web-baseline.ps1 -Bundler Webpack -Checks -RunLabel verified
```

The default path uses the unchanged package script, `npm run build`. With this Windows dependency junction, Turbopack fails because the junction points outside its filesystem root. This was reproduced in `evidence/web-before-default-20261025-223506-build.log` (exit 1). The explicit `--webpack` flag is therefore required for this isolated dependency-reuse workflow. The dashboard package script and Next.js configuration were not changed.

The helper installs nothing and starts no server. It removes inherited environment variables except a small OS/tool-path allowlist, restores them on completion, uses `http://127.0.0.1:1` and a fictional anonymous key for Supabase, points NVIDIA at the same unavailable loopback port, disables Next.js telemetry, and supplies blank temporary npm configuration files. Service-role, payment, private push, and AI credentials are absent. Every result records `environmentFilesCopied: 0`. The app's own `.env` remains outside the copied tree and is never loaded by these builds. Cleanup happens automatically, including after failure. No database or provider behavior is validated by this build.

## Verification

- Default build before change: exit 1 at Turbopack's dependency-junction filesystem boundary, as documented above.
- Fresh webpack build before change: exit 1 at `.next/types/app/dashboard/sales/page.ts:36:29`, reproducing W-20 exactly: the synchronous search parameters lack Promise methods. Evidence: `evidence/web-before-webpack-20261025-223721-build.log` and its result JSON. This was a separate clean source copy captured before editing the sales route.
- Fresh isolated lint after change: exit 0, with 0 errors and 46 pre-existing warnings; no rules were changed. Evidence: `evidence/web-after-webpack-20261025-223748-lint.log`.
- Fresh webpack production build after change: exit 0, including the framework's TypeScript gate, 42/42 static pages, and `/dashboard/sales` route output. Evidence: `evidence/web-after-webpack-20261025-223748-build.log`.
- Post-build generated-type check (`npm run typecheck`): exit 0. Evidence: `evidence/web-after-webpack-20261025-223748-typecheck.log`. The aggregate result JSON records all three commands at exit 0 and `environmentFilesCopied: 0`.

Non-blocking existing diagnostics remain visible: middleware-to-proxy deprecation, Supabase's `process.version` Edge-runtime warning, Node.js 20-and-below deprecation, and webpack cache serialization warnings. No warnings were suppressed.

## Decisions and remaining work

The build repair is deliberately limited to the asynchronous route prop contract. Financial defects, framework warnings, dashboard feature changes, dependency upgrades, and production deployment are outside this task. Lead review and publishing are required; this delegated agent did not commit or push. Next task: incorporate verified web results into `BUILD_AND_TEST_RESULTS.md` and the Phase 1A completion report.
