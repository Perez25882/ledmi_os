# Phase 1A mobile financial contracts

Run explicitly from `flutter_billing_app-main` in PowerShell:

```powershell
& C:/tools/flutter/bin/flutter.bat test --no-pub --reporter expanded test/phase1a/mobile_financial.contract.dart
```

The suite asserts correct financial behavior against the actual checkout,
refund, shift, Supabase/PostgREST and Hive implementations. Financial defects
remain unfixed by design during Phase 1A, so their assertions currently fail.
The `.contract.dart` suffix keeps these expected-red cases outside default
`flutter test` discovery; no case is skipped or inverted to make it pass.

Two SDK controls establish successful JSON decoding independently of the app
adapters. Other cases exercise M-01 response consumption, M-02 durable cash
retry identity, M-05 split tender attribution, and M-09 refund retry identity.

Only connectivity is overridden. HTTP is wholly intercepted by `MockClient`
using fictional identities and a `.invalid` host. Supabase automatic refresh,
deep-link discovery and session persistence are disabled. Hive uses a fresh
system temporary directory per case; teardown closes the SDK, transport and
Hive, then deletes that directory. The suite never loads `.env`, starts a real
database, calls Paystack, or launches a native platform plugin.

Lost-response fixtures represent an ambiguous acknowledgement at the HTTP
boundary. They prove transmitted/persisted identities, not actual database
commit counts or inventory effects. The online split case checks the outgoing
full-cash finalization request before the separate M-01 decode defect aborts
execution. Later unrelated intent amounts and provider authorization remain
outside that reproduction. Database concurrency and deduplication require the
separate isolated database suite.
