# Authorization test results

## Method and grant profiles

Tests use invented businesses A/B, separate branches, products and users for owner, branch manager, branch cashier, accountant and an outsider who belongs only to B. Bootstrap and independent persisted-state inspection use the owned-cluster administrator. Authorization probes execute `SET LOCAL ROLE authenticated` or `anon` with transaction-local fictional claims; the configured role is reset by commit/rollback. Service finalization probes use `service_role`. They do not test RLS as a superuser or treat a fictional JWT as proof of token authentication.

The native cluster initially has no API-role base-table DML grants. [db-contract-grants-before.json](evidence/db-contract-grants-before.json) captures authenticated SELECT/INSERT before the fixture. To test policies rather than stop at missing grants, the suite explicitly grants base-table SELECT/INSERT/UPDATE/DELETE to the three modeled API roles. It does not grant views or additional function execution. This represents a declared test configuration, **not a discovery of hosted Supabase permissions**. The [final catalog](evidence/database-catalog.json) shows this post-fixture profile and effective inherited function privileges.

## Executed boundaries

| Actor and boundary | Status | Observation |
| --- | --- | --- |
| Cashier reads another business's inventory | Verified passing behavior | Zero rows. |
| Cashier reads an unassigned branch in own business | Verified passing behavior | Zero rows. |
| Branch manager receives valid stock | Verified successful access | Both concurrent receiving calls reach the real RPC; correctness failures are tracked separately as B-04/B-05. |
| Owner receives valid same-business product | Verified passing behavior | Quantity 10 to 12. |
| Unrelated business member receives A's stock | Verified passing behavior | Denied. |
| Anonymous user receives stock | Verified passing behavior | Internal identity/authorization guard denies. |
| Cashier executes service-only finalizer | Verified passing behavior | Execution denied. |
| Service role finalizes fictional captured intent | Verified successful access | First capture finalizes; B-01/B-02 expose later data-contract failures. |
| Cashier directly creates successful payment (B-07) | Reproduced failure | Insert succeeds with one persisted payment under modeled DML grants. |
| Cashier relocates own active cart to unassigned branch (B-08) | Reproduced failure | Updated branch persists. |
| Manager relocates inventory to unassigned branch (B-08) | Verified passing behavior | Rejected/preserved original branch; the broader static hypothesis is not reproduced for this input. |
| Accountant without process_sales checks out/refunds (B-09) | Reproduced failures | Both RPCs succeed. |
| Owner receives foreign-business product into own branch (B-16) | Reproduced failure | Cross-business product/branch inventory row is created. |

Complete SQL observations and status counts are in [db-contract-results.json](evidence/db-contract-results.json). These inputs do not exhaust all entities, policies, custom roles or claim combinations.

## Privileged functions and RLS

All 28 application base tables have RLS enabled in the clean installation; 51 public policies exist. RLS presence alone does not establish tenant or operation safety. In particular, SECURITY DEFINER functions execute with their owner's privileges and must enforce actor, role, tenant, branch and product relationships internally.

`safe_finalize_sale(uuid)` and `process_payment_capture(uuid,uuid)` have effective execution false for anon/authenticated and true for service_role. `process_stock_in` and `process_refund` retain effective anon execution through PUBLIC inheritance. Revoking a named role's grant does not remove PUBLIC's grant. The anonymous stock control reaches an internal guard and is denied; this does not establish safe anonymous behavior for every privileged function. Several functions lack a function-local search_path, which remains a hardening concern.

`service_role` is NOLOGIN/BYPASSRLS in the fixture and is used only for trusted fictional capture finalization. Its successful access is not an end-user permission guarantee. The private isolation-marker schema is revoked from PUBLIC. `schema_migrations` is local verification metadata; modeled grants on base tables are not a production metadata-exposure assessment. Migration 020's view revocations were preserved.

## Verification limits

JWT signature/expiry checks, Supabase Auth enrollment/session handling, PostgREST exposed schemas, actual hosted default grants, Realtime subscriptions and production ACL drift were not exercised. No provider request or live account was used. The SQL failures prove reachable policy/function behavior under the stated grants and claims; production exploitability depends on its actual admission/grant configuration. Financial and security remediation remains outside Phase 1A.
