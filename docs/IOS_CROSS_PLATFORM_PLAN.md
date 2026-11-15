# iOS cross-platform implementation decision

**Status:** In progress. The current iOS target is not ready for financial use or distribution.

## Decision

Keep the product's user interfaces native: Jetpack Compose on Android and SwiftUI on iOS. Move
platform-independent finance models and deterministic rules into the existing `:shared/commonMain`
module as Android behavior is covered by common test vectors. Keep persistence, cryptography,
biometrics, file access, notifications, and lifecycle integration behind each platform's repository
boundary.

Android's Room database, SQLCipher integration, Keystore-wrapped key, DataStore, and transactional
`FinanceRepository` remain in `:app`. iOS will have a separate validated repository backed by a
reviewed, encrypted local store with a device-bound key. No Room entity, Android API, or platform
secret may cross into common code.

Use native SQLCipher SQLite behind an actor-based iOS repository. The security review rejected
whole-file encrypted snapshots because of write amplification, crash recovery, query, and large-ledger
risks. The local `MizaniCore` Swift package pins the official SQLCipher.swift 4.20.0 community
release and records its BSD-style attribution in third-party notices. Debug/Release builds and device
behavior remain unverified until macOS/Xcode testing is available.

Generate a random 256-bit database key and store it in Keychain with
`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`, without synchronization. Protect the database,
WAL, SHM, and temporary files with complete file protection and exclude them from cloud backup.
Verify SQLCipher on every opened connection. If the key is missing while database files exist, fail
closed; never make a replacement key that would orphan records. The app PIN remains an access
barrier and is not the database key.

## Alternatives considered

1. **Share the UI and persistence stack.** Rejected for this migration: it would replace the existing
   native Android UI and require both platforms to adopt one storage implementation. It adds broad
   rewrite risk without helping preserve Android's existing Room data.
2. **Implement a separate Swift domain and rules layer.** Rejected: transaction validation,
   recurring rules, analytics, and backup semantics could drift between Kotlin and Swift.
3. **Share KMP domain rules with native UI and platform repositories.** Chosen: it preserves the
   working Android app, gives both clients one implementation for rules that are truly
   platform-independent, and keeps secure system APIs native.

## Compatibility and data rules

- Persisted enum names stay stable. Common tests pin values consumed by Room, DataStore, and backup
  JSON; never rename an entry without a compatible migration.
- Keep money as integer minor units plus currency code. Keep exchange rates as exact decimal text
  and reproduce Android rounding with shared test vectors before moving conversion logic.
- Preserve soft deletion, transaction IDs, refund links, transfers, and commitment payment
  associations. A linked payment must continue to reuse its existing ledger transaction.
- Keep Android and iOS stores separate. Map their records to shared domain snapshots at repository
  boundaries; do not move the Room schema.
- Cross-platform backup portability requires golden fixtures in both directions. Never copy or
  restore the Android database file on iOS.

## iOS storage threat model

The authorized user writes records from SwiftUI through `IOSFinanceRepository` to the `MizaniCore`
actor, which is the only owner of the SQLCipher connection. The database key crosses
the app/Keychain boundary once per open. The protected assets are the ledger, goals, investment
snapshots, their WAL/SHM files, and the random database key. No financial values may be logged or
sent over the network.

| Threat | Control | Verification |
| --- | --- | --- |
| Someone reads copied app files or an iCloud/device backup | SQLCipher encryption; database and sidecars are excluded from backup | Mac package tests scan for plaintext; device checks inspect backup exclusion and database/WAL files |
| Keychain item disappears while database files remain | Key provider refuses to generate a replacement key | Package test covers existing DB and WAL without a key; device recovery test verifies no overwrite |
| Wrong key or modified database is accepted | Verify SQLCipher is loaded and force a read from `sqlite_master` on open | Package tests reject wrong keys and altered database bytes |
| Device is locked or has no passcode | `WhenPasscodeSetThisDeviceOnly` Keychain key and complete file protection | Simulator and physical-device tests cover keychain status, lock/unlock, and passcode removal |
| A financial write is interrupted | Initial setup and ledger changes use prepared statements inside explicit SQLite transactions after KMP validation | Package tests cover setup, persistence, transaction lifecycle, and verify rejected changes leave the ledger unchanged |

Package test source covers the connection, ciphertext, fail-closed behavior, schema migration,
transaction create/edit/delete/restore, overflow rejection and recovery from legacy invalid balances,
and local Activity search matching. The package tests have not been run with Xcode here and do not
prove iOS Keychain behavior on hardware, the SwiftUI flows, or the complete recovery path.

## Implementation sequence and acceptance gates

1. **Shared contracts (started).** Stable finance and preference enums, transaction amount/fee
   validation, wallet balance derivation, Activity search normalization/matching, and the built-in
   category catalog with pinned Android IDs and the minimum-active-category archive rule now live in
   common code. Android and iOS call these rules from their repository boundaries, and iOS also calls
   the shared search rules. Android repository writes,
   restore, backup replacement and wallet opening balances now receive checked balance validation;
   Home and balance screens expose a repair state for older invalid ledgers. A platform-neutral
   transaction projection now drives posted-ledger income, spending, fee, refund, and category
   totals in both Android and iOS, with common test vectors and Android behavior coverage. App-lock
   PIN format, PBKDF2 work factor, retry backoff, and foreground grace-period policy are also shared;
   the iOS Keychain verifier, native biometric prompt, pre-database lock check, lifecycle shield, and
   delayed connection close now have an initial implementation. Continue moving one
   platform-independent rule at a time. Decimal-to-minor-unit parsing, featured country-pack
   defaults, and curated currency precision are now exposed through KMP to both native clients.
   Gate: Android
   unit/instrumentation tests and common tests pass without Room schema or backup changes.
2. **iOS security/storage proof (started).** `MizaniCore` now opens SQLCipher, verifies the cipher
   is active, generates and stores a random database key in Keychain, fails closed when a key is
   missing for existing database files, applies iOS file protection and backup exclusion, and creates
   the initial encrypted schema. The category-table v1-to-v2 migration preserves transaction rows
   and seeds the shared catalog; the v2-to-v3 migration adds income-source storage while preserving
   nullable transaction source IDs. The v3-to-v4 migration adds goals and goal-contribution tables
   without rewriting existing ledger rows; the additive v4-to-v5 migration adds manual investment
   snapshots without changing transactions, goals, or contribution history. Linked-wallet goal contributions insert the transfer,
   contribution history, and allocation update in one SQLite transaction and validate balances before
   commit. Early v1 databases without the nullable source column receive it additively before the
   category migration. Interrupted migrations roll back and retry on the next open. A source ID with no catalog row is retained;
   editing that same income row may preserve the ID, while new assignments still require an available
   source. Package test source covers the migrations, goal writes, atomic contribution rollback, and legacy-reference edits. Transaction writes now
   validate derived balances before commit, and Activity
   remains available to edit or remove a legacy row when balances are invalid. The iOS biometric and
   app-lock source is now in place, but device-lock behavior, reinstall, Keychain accessibility,
   recovery behavior, and interrupted writes remain untested. Gate: macOS package tests, iOS simulator/device
   security checks, and agreed large-ledger performance limits pass.
3. **Core ledger vertical slice (started).** Workspace and wallet setup plus category-aware
   expense/income entry, atomic wallet transfers, linked refunds, signed balance adjustments, Home
   balances, Activity, transaction editing, and reversible deletion and restore use the encrypted iOS
   repository. Activity now has a debounced, in-memory search index for notes, types, wallets,
   categories, currencies, and integer minor-unit amounts; it preserves ledger order, renders rows
   lazily, and does not write search state to disk. First-run setup now asks users to acknowledge
   preview limits, and collects a shared country, currency, wallet type, and opening balance. This is
   not legal consent. Still add relaunch UI recovery and reviewed iOS legal documents. Gate: the same
   common rule vectors pass on Android host and iOS simulator; iOS repository tests cover
   migrations, transaction lifecycle, and ledger persistence, and Activity search tests run on macOS.
4. **Feature parity (started).** The encrypted category table supports category creation, renaming,
   archive/restore, and per-type ordering; income-source kinds come from KMP and sources can be
   created, renamed and linked to income without changing existing transaction IDs. Goal target and
   allocation rules now come from KMP; the iOS client can create, edit, archive/restore, and contribute
   to goals, recording any linked-wallet transfer atomically. Manual investment snapshots now use
   KMP asset types, validation, and checked portfolio totals with encrypted iOS persistence and
   archive/restore. Commitment management now has KMP-backed currency validation/conversion, cached
   reference rates, encrypted storage, and progress linked to existing expenses with active refunds
   accounted for; its v5-to-v6 migration is additive. iOS currently limits these options to the ten
   curated KMP currencies, while Android accepts the runtime ISO-country currency set; unify that
   supported-currency contract before claiming currency parity. Still add budgets/recurring schedules, debts,
   full deterministic
   Insights parity (iOS currently shows only a shared current-month cash-flow/category summary),
   and import review. Gate: category, investment, and commitment repository tests plus macOS UI checks
   pass; each remaining flow
   has repository, common-rule, accessibility, offline, and upgrade tests.
5. **Protection and system flows.** Verify the initial app lock/PIN throttling and biometric flows on
   Apple platforms, then add encrypted backup/restore, CSV/XLSX export warnings, file sharing,
   reminders, settings, legal documents, privacy manifest, and notifications. Gate: cross-platform
   backup golden fixtures, fresh-install and upgrade/restore
   tests, privacy and dependency/license review.
6. **Release readiness.** Run Android CI plus iOS simulator tests/build on macOS; exercise a physical
   iPhone/iPad, VoiceOver, Dynamic Type, background/foreground locking, offline use, recovery,
   accessibility, and large ledgers. Configure signing and App Store metadata only after these gates
   pass.

## Current blockers

- The Windows environment cannot run Xcode, iOS Simulator, or physical-device tests.
- Kotlin 2.4.21, Gradle 9.6.0, and AGP 9.3.1 now fall within Kotlin's published KMP compatibility
  matrix. Earlier Android-host checks passed, but the latest investment-rule verification could not
  start because the Gradle wrapper download was denied. The iOS targets are disabled on Windows, so
  macOS CI must still establish that the framework and SwiftUI app build successfully.
- `iosApp` has preview-limits acknowledgment, country/currency-aware workspace and wallet setup,
  KMP-backed money input conversion and currency-precision-aware display, category-aware expense/income,
  income-source links, transfers, refunds,
  adjustments, Activity search, transaction edit/delete/restore, category and goal management,
  manual investment snapshots, commitment management linked to existing expenses, and a basic
  current-month summary that consumes the common KMP analytics rule. Goal, investment, and commitment
  writes use forward encrypted-schema migrations and KMP validation. Their source-level tests and the
  SwiftUI changes have not run on macOS.
  Full Android Insights parity, legal consent, foreign-currency transaction entry, commitment
  reminders, backup/restore, and most Android features are not
  implemented; the source and package tests have not been built or run with Xcode here.
- Before adding cross-platform backup/import, align the remaining ledger edge differences: Android
  can accept a new refund's dangling link when a category is supplied, while iOS rejects missing or
  deleted targets; iOS preserves an unchanged refund link when its expense is in Recently deleted,
  while Android requires that source to be active for an edit. iOS prevents changing an expense with
  any linked refunds (including deleted refunds) and requires a deleted transaction to be restored
  before editing; Android does not apply those same edit guards. Android stores adjustment fees that
  balance rules ignore, while iOS rejects those fees. Refund totals remain uncapped on both clients.
- Shared wallet balance derivation uses checked `Long` arithmetic. Android and iOS repository writes
  now reject invalid prospective balances; Android screens and the iOS preview keep Activity available
  for user-directed recovery of older invalid data. Android host/unit/build checks are available here,
  but the iOS package source tests and SwiftUI app cannot be verified without macOS/Xcode.
- Signing, the production bundle identity, privacy declarations, legal copy, and App Store metadata
  still need platform-specific review.
