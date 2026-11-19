# Project structure

## Module decision

The project keeps one Android application module (`:app`) and adds one Kotlin Multiplatform library
(`:shared`) for code that is safe to run on Android and iOS. Android-only packages remain organized
inside `:app`; the iOS application is a native SwiftUI project under `iosApp/` and consumes the
framework exported by `:shared`.

The shared module contains platform-neutral currency and money types, decimal-to-minor-unit input
rules, curated currency and featured country-pack catalogs, built-in categories, stable
finance/preference enums, transaction validation, wallet balance rules, posted-ledger analytics,
the app-lock PIN policy, goal allocation bounds, the minimum-active-category archive rule, and Activity search rules. Android
storage, export, lock, and UI remain in `:app`. The iOS project includes a SQLCipher-backed workspace
and wallet repository in source, category-aware ledger entry, transfers, refunds, adjustments,
transaction editing/deletion/restoration, Activity search, category management, and savings goals with
atomic linked-wallet contributions. The storage and
app flows still lack Apple-platform verification and full feature parity. Its current-month
cash-flow summary and category attribution call the shared analytics rules. Do not move Android-only code into
`:shared` merely to make the module larger.

## Package layout

```text
com.mizani.money (Android :app)
|-- MizaniApplication.kt            application + SQLCipher native load + container
|-- MainActivity.kt                 FragmentActivity, theme, root routing, lock lifecycle
|-- di/AppContainer.kt              explicit dependency graph (manual DI)
|-- core/
|   |-- money/                      shared values/input rules; Android runtime catalog, conversion, formatting
|   |-- model/                      Android global country discovery; featured packs/defaults/enums are shared
|   |-- legal/                      runtime Terms of Service and Privacy Notice
|   |-- importing/                  bounded local parser for user-shared transaction text
|   |-- time/                       DateRange, periods, recurring date math
|   `-- security/                   Android PBKDF2-HMAC-SHA256; PIN policy comes from `:shared`
|-- data/
|   |-- local/                      Room entities, DAOs, encrypted database, Keystore key
|   `-- repo/                       FinanceRepository (write boundary), FinanceModels.kt,
|                                   SettingsRepository, BackupValidator.kt
|-- domain/
|   |-- analytics/                  deterministic analytics and insight engines
|   |-- engagement/                 local Daily Momentum rules
|   |-- notifications/              local check-in notification rules
|   `-- export/                     CSV/XLSX and encrypted backup/restore
|-- ui/                             AppViewModel, navigation, fold layout, theme, components
|-- reminder/                       Android WorkManager and notification adapters
`-- feature/                        onboarding, home, transactions, commitments, debts, wallets,
                                    investments, insights, more, settings, legal, lock
```

## Cross-platform build structure

```text
:app      Android application (Jetpack Compose + Room/SQLCipher)
:shared   KMP library (money/currency/country/category catalogs, finance, analytics, app-lock and search rules)
iosApp/   Native SwiftUI client consuming MizaniShared and MizaniCore
iosApp/MizaniCore/  Native encrypted database, validated repository and macOS tests
scripts/ios/ Xcode build helper for the shared framework integration
```

## Dependency direction

```
feature / ui  ->  domain  ->  data  ->  core
                     \--------------------^
```

Platform integration direction:

```
:app    -> :shared
iosApp  -> MizaniShared framework from :shared
iosApp  -> MizaniCore Swift package for native storage
```

- `:shared` common code has no Android, Apple, or Compose dependency and is covered by common tests
  executed on the Android host. iOS native compilation still requires macOS and Xcode.
- Finance and preference enum names, curated currency and built-in category metadata, transaction
  amount/fee validation, wallet balance derivation, posted-ledger analytics, and Activity search text
  rules now come from `:shared`; common tests preserve stored names, category IDs, financial results,
  and search behavior.
  Both repositories use the common minimum-active-category archive rule inside their platform write
  transactions.
- Income-source kinds and stable persisted names are shared; the iOS repository validates source
  types through `IosFinanceRules` and rechecks source references inside its SQLCipher write
  transaction.
- Featured country-pack defaults are shared; Android's runtime-generated global country list and
  Android-only feature models remain in `:app`.
- Decimal input parsing and rounding live in `:shared/core.money/MoneyInputRules`; Android display
  formatting, runtime currency discovery, and foreign-rate conversion remain in `app/core.money`.
  Currency, Money, and MoneyLimits types come from `:shared`.
- Investment asset types, draft validation, and checked active-portfolio totals live in KMP; platform
  repositories persist manual snapshots in their respective encrypted local stores.
- `core.time` is currently Android/JVM-only and has not been moved to common code.
- `MizaniCore` owns native iOS SQLCipher and Keychain storage and the initial validated ledger
  repository. Its schema migration seeds the shared category catalog while retaining transaction
  category references and advances v2 databases to v3 with income-source storage, v3 to v4 with
  goal/contribution storage, and v4 to v5 with manual investment snapshots, without rewriting existing
  transaction rows. The repository supports category creation, rename, archive/restore and ordering,
  income-source creation, rename and transaction linkage, goal management and atomic linked-wallet
  contributions, and investment snapshot management. Swift package tests cover encryption,
  fail-closed behavior, Activity search, migrations and ledger persistence; they require macOS to run.
  The iOS first-run flow collects preview acknowledgment and shared country/currency/wallet choices;
  it is not legal consent. App-lock source now exists but is uncompiled and unverified on Apple
  platforms. Budgets, recurring items, commitments, debts, full Android Insights parity,
  imports/exports, notifications, full Settings and release flows remain unimplemented.
- `domain.analytics` consumes plain entities/models and has **no Android UI dependency**; it is deterministic.
- `data.local` depends on `core.model` and Room/SQLCipher; it does not know about screens.
- Android `data.repo` is the only layer that opens Room write transactions. `FinanceRepository` is
  its validated write boundary. The iOS `IOSFinanceRepository` validates with KMP rules and writes
  through the actor-owned SQLCipher connection.
- `ui`/`feature` read through `AppViewModel`/repositories and never touch DAOs or SQLite directly.
- `feature` packages are package-by-feature; each owns its screen, local state and dialogs.

## State and data flow

```
Room (SQLCipher) --Flow--> FinanceRepository --Flow--> AppViewModel --StateFlow--> Compose
        ^                                                     |
        └──────────── validated suspend mutations <───────────┘
```

The local database is the canonical source of truth. The only network path is an explicit request for a
currency-pair reference rate; it never sends a transaction amount or detail. `LedgerSnapshot` combines the
small set of Room flows once, so screens derive analytics from a consistent in-memory view and a write is
reflected immediately.

## Where things belong

| Change | Location |
|---|---|
| Shared money values/arithmetic | `shared/src/commonMain/.../SharedMoney.kt` + `shared/src/commonTest/.../MoneyTest.kt` |
| Android currency catalog | `app/src/main/.../core/money/Currencies.kt` + `app/src/test/.../MoneyTest.kt` |
| Android money conversion | `app/src/main/.../core/money/CurrencyConversion.kt` + `app/src/test/.../MoneyTest.kt` |
| Shared decimal-to-minor parsing | `shared/src/commonMain/.../MoneyInputRules.kt` + common money input tests |
| Platform money formatting | Android `app/core/money/MoneyFormat.kt`; iOS SwiftUI presentation helpers |
| New transaction type | `core/model/TransactionType`, repository validation, add-screen picker, analytics rules, tests |
| New analytic metric | `domain/analytics`, an explanation string, unit test, UI card |
| New database column/table | `data/local` entity + DAO + versioned migration test; never destructive migration |
| New screen | `feature/<name>` + route in `ui/Navigation.kt` |
| Shared visual element | `ui/components` once it has 2+ call sites |
| Preference | `SettingsRepository` (DataStore), never in the encrypted ledger |

## Testing layout

```
app/src/test/          pure JVM: money, analytics, insights, dates, PIN hashing
app/src/androidTest/   encrypted Room/SQLCipher CRUD, guest journey, app lock, backup/restore
app/schemas/           exported Room schema (checked in for migration tests)
shared/src/commonTest/ KMP common money/currency rules, executed by the Android host-test task
```

## KMP evolution path

1. Keep shared value types, stable domain enums and deterministic rules in `:shared/commonMain` and
   add common tests that pin persisted values and Android behavior.
2. Move country/currency metadata and date/recurrence rules only after replacing JVM-specific APIs
   and verifying Android behavior remains identical.
3. Define platform-neutral repository contracts and snapshots, then move deterministic analytics
   rules incrementally with Android parity tests.
4. Implement and security-review iOS persistence, key management, app lock, backup/restore, import,
   export, and native system integrations. Android Room entities and SQLCipher stay in Android code.
5. Consider sharing UI only after native iOS feature flows are complete and usability requirements
   for both platforms are understood.

When a platform-independent financial rule is needed by both clients, keep one implementation in
`:shared/commonMain` and test it with common test vectors. Keep locale formatting, secure storage,
notifications, and file access in native adapters. Before moving a rule, verify its Android output
against the existing behavior so the KMP migration cannot change saved financial results silently.

Keep `FinanceRepository` as the Android write boundary. iOS requires its own validated repository
boundary. Do not add modules merely for aesthetics.

## Website

`website/` is an Angular project outside the Gradle build. It contains the promotional site,
standalone local CSV analysis page, legal pages, and static-host security headers. The CSV page has
no server endpoint; it reads Mizani's transaction export in browser memory and runs deterministic
calculations. It does not persist data or accept provider API keys. See
[`website/README.md`](../website/README.md) for the local preview command and limitations.
