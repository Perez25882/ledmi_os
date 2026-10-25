# Phase 1A mobile contract task report

Date: 2026-10-25. Scope: isolated regression evidence; financial production code is unchanged.

## Files

- `flutter_billing_app-main/test/phase1a/mobile_financial.contract.dart`
- `flutter_billing_app-main/test/phase1a/README.md`
- `docs/phase-1a/evidence/mobile-contract-tests.txt`
- `docs/phase-1a/evidence/mobile-contract-fixture-first-run.txt` (superseded fixture diagnostics)
- `docs/phase-1a/evidence/mobile-existing-tests.txt`
- `docs/phase-1a/evidence/mobile-contract-analyze.txt`
- This report.

## Method and isolation

The suite calls the actual `CheckoutService`, `RefundService`, `ShiftService`,
`OfflineQueueService`, `SessionManager`, and installed Supabase/PostgREST SDK.
No test implements a substitute sale/refund/deduplication algorithm. The only
service override returns a configured connectivity state, avoiding platform
plugins. Real Hive persistence uses a new system temporary directory per test,
and the cash fallback case closes and reopens its queue box.

Supabase uses an injected `http/testing.dart` MockClient, a reserved `.invalid`
host, an unsigned fictional JWT and invented UUIDs. Every HTTP request is
captured locally; unexpected paths fail locally. Automatic refresh, deep links
and persistent SDK auth storage are disabled. No environment file is loaded,
no credentials or customer data are used, and there is no provider, database or
real network operation. Teardown disposes Supabase/HTTP, closes Hive and deletes
only the test's freshly created temporary directory.

## Contracts and boundaries

| Case | Causal assertion | Limit |
| --- | --- | --- |
| SDK controls | A successful JSON UUID is decoded to String; RETURNS TABLE is decoded to List. **Verified passing (2).** | SDK HTTP contract only |
| M-01 | Healthy acceptance asserted; **reproduced failures (5):** cash/refund/open-shift Strings, close-shift null and intent List all raise `NoSuchMethodError` on `.error` | Does not claim database commits |
| M-02 | Original transmitted key must equal durable fallback key. **Reproduced failure (1):** keys differ after Hive reopen | Lost acknowledgement is simulated; duplicate database records not executed |
| M-05 online | GHS4 cash/GHS6 MoMo must not send a GHS10 full-cash finalization. **Reproduced failure (1):** that request is sent | Captures request before M-01 aborts; later full-value intents/provider authorization remain static findings |
| M-05 offline | Reject without cash queue, or retain attribution. **Reproduced failure (1):** ordinary sale payload contains no cash/MoMo attribution | No provider authorization offline; no new storage schema is prescribed |
| M-09 online | First refund key must equal persisted fallback identity. **Reproduced failure (1):** first request has null/missing key | Lost acknowledgement is simulated |
| M-09 replay | Two actual replays must transmit the original queue key. **Reproduced failure (1):** keys are `[null, null]` | M-01 is observed after each request so it cannot mask missing outbound keys; database stock effects not executed |

Every defect assertion expects healthy behavior and stays red while its defect
exists. `.contract.dart` is an explicit runnable test target, excluded from
default `_test.dart` discovery. No skip annotations, expected-failure inversion,
adapter fixes, dependency additions, migration edits or native changes are used.

## Verification commands

Commands run from `C:/Users/DELL/Desktop/POS/flutter_billing_app-main`:

```powershell
& C:/tools/flutter/bin/dart.bat format test/phase1a/mobile_financial.contract.dart
& C:/tools/flutter/bin/flutter.bat test --no-pub --reporter expanded test/phase1a/mobile_financial.contract.dart
& C:/tools/flutter/bin/flutter.bat test --no-pub --reporter expanded
& C:/tools/flutter/bin/flutter.bat analyze --no-pub test/phase1a
```

The formatter completed successfully. The explicit contract command completed
with **12 tests: 2 controls pass, 10 financial assertions fail; exit 1**. This is
expected defect detection, **not** a passing financial suite. The final log has
no missing-plugin, compile or fixture errors. Test execution took approximately
three seconds after compilation; cold SDK startup/compilation was slower.

The first fixture run is preserved separately for transparency and is superseded:
it lacked HTTP response request metadata required by installed PostgREST and
explicit PKCE storage (Supabase creates default shared-preferences storage even
with implicit flow). Only the test fixture was corrected. Its failures are not
counted as financial reproductions. The final run's two SDK controls prove those
fixture issues are resolved.

The existing default test command completed with **36 passed, exit 0**. Its
expanded log confirms only the original auth-error and billing-total tests are
discovered; the intentional red cases are excluded by filename discovery.

Targeted analyzer verification completed with **No issues found, exit 0**
(260.9 seconds). This result covers the new Phase 1A test directory; it does not
replace a full-project analyzer baseline or claim the pre-existing six
informational audit findings elsewhere have been corrected.

## Decisions and remaining work

The suite targets transmitted/persisted contracts, which remain testable even
when M-01 prevents normal completion. This avoids a legacy wrapper fixture that
would hide the installed SDK behavior. It intentionally does not pretend to
prove SQL concurrency, actual inventory movement counts, provider settlement,
device callbacks or hardware behavior.

After founder approval of financial fixes, use these contracts to verify the
adapters and retry identities, then extend split tender coverage against the
approved shared transaction schema. Database concurrency/authorization belongs
to the separate disposable database verification. No commit or push is performed
by this delegated task; the lead owns review and publishing.
