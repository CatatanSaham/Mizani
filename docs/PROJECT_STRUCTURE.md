# Project structure

## Module decision

The project keeps one Android application module (`:app`) and adds one Kotlin Multiplatform library
(`:shared`) for code that is safe to run on Android and iOS. Android-only packages remain organized
inside `:app`; the iOS application is a native SwiftUI project under `iosApp/` and consumes the
framework exported by `:shared`.

The shared module is intentionally small at first. It contains the platform-neutral currency and
money value types and amount limits. Android storage, validation transactions, exports, lock, and UI
remain in `:app`. The iOS project is an integration preview and has no production ledger, encrypted
storage, or complete budgeting flows yet. Do not move Android-only code into `:shared` merely to make
the module larger.

## Package layout

```text
com.mizani.money (Android :app)
|-- MizaniApplication.kt            application + SQLCipher native load + container
|-- MainActivity.kt                 FragmentActivity, theme, root routing, lock lifecycle
|-- di/AppContainer.kt              explicit dependency graph (manual DI)
|-- core/
|   |-- money/                      shared value types; Android catalog, conversion, formatting
|   |-- model/                      domain enums, country packs, default categories
|   |-- legal/                      runtime Terms of Service and Privacy Notice
|   |-- importing/                  bounded local parser for user-shared transaction text
|   |-- time/                       DateRange, periods, recurring date math
|   `-- security/                   PBKDF2-HMAC-SHA256, PIN policy
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
:shared   KMP library (commonMain money/currency types; Android and iOS targets)
iosApp/   SwiftUI iOS preview consuming the MizaniShared framework
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
```

- `:shared` common code has no Android, Apple, or Compose dependency and is covered by common tests
  executed on the Android host. iOS native compilation still requires macOS and Xcode.
- Android money parsing/formatting, runtime currency discovery, and decimal conversion remain in
  `app/core.money`; its `Currency`, `Money`, and `MoneyLimits` types come from `:shared`.
- `core.time` is currently Android/JVM-only and has not been moved to common code.
- `domain.analytics` consumes plain entities/models and has **no Android UI dependency**; it is deterministic.
- `data.local` depends on `core.model` and Room/SQLCipher; it does not know about screens.
- `data.repo` is the only layer that opens write transactions. `FinanceRepository` is the single validated write
  boundary so money records, balances, and imports never partially apply.
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
| Android money parsing/formatting | `app/src/main/.../core/money/MoneyFormat.kt` + `app/src/test/.../MoneyTest.kt` |
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

1. Keep shared value types and deterministic rules in `:shared/commonMain` and add common tests.
2. Move country/currency metadata and date/recurrence rules only after replacing JVM-specific APIs
   and verifying Android behavior remains identical.
3. Define platform-neutral repository contracts and snapshots before considering shared analytics.
4. Implement and security-review iOS persistence, key management, app lock, backup/restore, import,
   export, and native system integrations. Android Room entities and SQLCipher stay in Android code.
5. Consider sharing UI only after native iOS feature flows are complete and usability requirements
   for both platforms are understood.

Keep `FinanceRepository` as the Android write boundary. iOS requires its own validated repository
boundary. Do not add modules merely for aesthetics.
