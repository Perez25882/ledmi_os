# React Native / Expo foundation decision

Status: founder-approved platform direction; proposed technical foundation pending implementation approval. React Native + Expo is the primary mobile direction for the **3–5-shop pilot**. Flutter is retained as the existing implementation and a source of regression contracts. This decision does not change the locked Ghana/Paystack product scope or create an Expo application.

## Architecture recommendation

Use TypeScript strict mode, Expo Router for navigation, a domain/application layer independent of React, adapters for Supabase/Paystack initiation, and repositories for local storage. Views invoke application operations; a durable local transaction and outbox entry are committed before a sale is acknowledged locally. Keep server authorization and payment verification authoritative. Share versioned JSON schemas/fixtures and money/idempotency rules across dashboard, future mobile and backend; do not share framework-specific UI or port Flutter's failing SDK response assumptions.

Use a development build from the hardware integration stage. Expo Go includes a fixed native library set; custom native libraries require a rebuilt native application. Select the SDK and printer library only after device compatibility validation, then pin compatible versions. [Expo development-build guidance](https://docs.expo.dev/develop/development-builds/faq/)

## Offline storage and identity

Recommend `expo-sqlite` for products, branch caches, local transactions, outbox and retry history. It supports persistent SQLite across app restarts. Evaluate transaction boundaries, journal configuration, migration recovery and encryption on pilot devices before accepting durability claims. Async key/value storage can hold preferences, but is not the proposed financial queue. An additional database abstraction is optional only if it preserves explicit atomic operations and predictable migrations. [Expo SQLite](https://docs.expo.dev/versions/latest/sdk/sqlite/)

Proposed contracts:

| Contract | Required rule |
| --- | --- |
| Money | Integer pesewas plus `currency: GHS`; explicit conversion at existing GHS/SQL/provider boundaries, never implicit floating-point units. Existing database amounts are not migrated by this record. |
| Sale / refund / stock operation | Client-generated immutable operation UUID, tenant, branch, actor, device, version and occurrence time, with server validation. |
| Tender | Explicit cash/card/MoMo allocations summing to sale total; pending provider money cannot be represented as verified cash. |
| Retry identity | Persist operation and key before first send; reuse across ambiguous response, retry, queue replay and restart. Server uniqueness and canonical acknowledgement required. |
| Queue state | Durable pending/in-flight/acknowledged/needs-review transitions with attempt/error metadata; never infer success from connectivity alone or silently drop exhausted retries. |
| Device identity | App-generated installation UUID persisted with queue ownership; account/tenant namespace and explicit device enrollment. Hardware IDs are not financial identity. |

Foreground resume and network recovery should trigger bounded replay; correctness must not depend on uninterrupted background execution. Device/clock changes, process death, token expiration and app upgrades require contract tests. Reinstallation or account switching must not silently regenerate identities for retained pending work. Loss of local storage requires reconciliation, not assumptions of an empty queue.

## Secure storage

Use `expo-secure-store` for small authentication material and, if chosen, database-encryption keys. It uses Android Keystore-backed encrypted storage and iOS Keychain. Its uninstall/backup/biometric behavior differs by platform; it must not be the sole store for irreplaceable transaction data. Test session refresh, lock/unlock, logout and reinstall recovery explicitly. Never bundle service-role, Paystack secret or NVIDIA keys; never retain PAN/CVV. Public mobile configuration is not secret storage. [Expo SecureStore](https://docs.expo.dev/versions/latest/sdk/securestore/)

## Native builds, scanning and printing

Android development requires the Android native toolchain and physical low-end pilot devices. iOS requires a macOS/Xcode build route or an approved cloud build/signing route and physical-device checks. Expo's local EAS build workflow does not officially support Windows; do not assume the current Windows workspace proves iOS build readiness. Cloud build/account/signing setup requires future authorization; none was performed. [Expo local-build constraints](https://docs.expo.dev/build-reference/local-builds/)

Use `expo-camera`'s CameraView barcode callback as the initial scanning candidate. Configure camera permission, supported retail barcode types and repeat-scan suppression; verify EAN/UPC reads, low light, denied permission and manual-entry fallback on both platforms. Its documented callback is an API capability, not evidence that our pilot hardware has passed. [Expo Camera](https://docs.expo.dev/versions/latest/sdk/camera/)

Bluetooth receipt printing remains **unverified**. Inventory the exact printer models, Android/iOS support, transport (Classic/BLE/vendor SDK), paper width, character encoding, pairing and reconnect behavior before choosing a native module. Do not promise that a generic Android printer will work with iOS or Expo Go. Prototype in a development build with the actual printers; printing failure must preserve a completed sale and permit a safe reprint. No native printer dependency or app scaffold is selected here.

## Flutter transition

Retain Flutter and its tests while shared transaction contracts and server financial defects are reviewed. Before any shop cutover, inventory outstanding Hive transactions/refunds, reconcile server acknowledgements, drain the queue or implement an explicitly reviewed transfer preserving operation IDs and tender attribution. Prevent both apps from independently replaying the same unresolved operation. No uninstall, queue reset or automatic destructive conversion is acceptable.

Future approval sequence: agree shared contracts and server fixes; create the Expo foundation; prove offline persistence/replay and exact printer/scanner hardware; rehearse branch-by-branch migration and reconciliation; then approve pilot rollout. These are future gates, not Phase 1A implementation work. No Expo application, dependency installation, native build or deployment was created in this phase.
