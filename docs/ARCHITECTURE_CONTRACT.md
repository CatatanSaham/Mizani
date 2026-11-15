# Product architecture contract (Mizani V1)

This is an offline-first financial application. Android remains the complete client today; iOS has
an early native wallet and ledger-entry slice with a basic shared Insights summary, but must not be
treated as ready for financial use or store submission until its storage, security, and complete
feature flows are implemented and validated.

## Canonical data and identity

- The local encrypted database is the canonical data source. UI layers read from it; the
  network (when it exists) would only feed it.
- No account is required. Guest mode does not depend on any server response.
- Before an account exists, financial data must not be synchronized to an application
  backend. There is no backend endpoint; internet access is used only for optional public
  exchange-rate lookups.
- Creating an account would enable synchronization; it must never replace the local
  database. Local export and deletion remain available.

## Technology

- Kotlin Multiplatform shared library (`:shared`) for platform-independent financial value types,
  stable built-in category metadata/IDs, deterministic ledger analytics, and rules. Its common
  contract includes `Currency`, `Money`, `MoneyLimits`, and the stable finance and preference enums
  consumed by Android persistence and backup code.
- Android application (`:app`) keeps Jetpack Compose, Material 3, Navigation Compose, Room, SQLCipher,
  DataStore, Android Keystore, AndroidX BiometricPrompt, and manual dependency injection.
- Native SwiftUI iOS project (`iosApp`) consumes the `MizaniShared` framework and the `MizaniCore`
  Swift package. `MizaniCore` provides SQLCipher/Keychain storage and a validated repository for the
  initial workspace, wallet, category-aware expense and income, atomic transfer, linked refund, and
  signed balance adjustment flows. Category management preserves transaction references, and
  income sources use the forward-migrated encrypted schema and KMP-backed kind catalog.
  Apple-platform build and
  runtime behavior remain unverified in the current Windows environment.
- Room for relational local state, with exportable schema and no destructive migrations.
- SQLCipher (`net.zetetic:sqlcipher-android`) for the encrypted database.
- Android Keystore, AES-GCM-wrapped random 256-bit database passphrase.
- DataStore for non-sensitive preferences and the salted PIN hash.
- AndroidX BiometricPrompt for biometric unlock.
- Manual dependency injection (`AppContainer`) for Android; no Hilt.

## KMP sharing policy

- Keep Compose and SwiftUI user interfaces native. A shared financial rule belongs in
  `:shared/commonMain` once both clients need it; both clients call that implementation instead of
  carrying separate copies of the rule.
- Transaction amount/fee validation and wallet balance derivation now start in
  `:shared/commonMain`; Android calls those implementations from its existing repository and
  snapshot boundaries, and the iOS repository calls the same rules through the Kotlin/Native
  framework.
- The built-in category catalog and existing Android category IDs now come from
  `:shared/commonMain`; Android retains its existing `DefaultCategories` adapter and iOS seeds its
  local category table from the same catalog.
- Income-source kinds and their persisted names come from shared enums; iOS exposes that catalog
  through the narrow `IosFinanceRules` bridge rather than defining another Swift enum.
- The rule that permits source metadata only on income transactions lives in `:shared/commonMain`;
  Android and iOS repositories apply it before persistence, and iOS rechecks source availability
  within its encrypted write transaction.
- Investment asset types, manual snapshot validation, and checked portfolio aggregation live in
  `:shared/commonMain`; Android and iOS keep investment records in their own encrypted local stores
  and do not create ledger transactions for snapshot changes.
- The rule that prevents archiving the final active category of a type lives in
  `:shared/commonMain`; Android and iOS invoke it from their platform repositories while counting
  categories inside their respective write transactions.
- Activity search text normalization and matching live in `:shared/commonMain`; each native screen
  builds its own in-memory search index from its platform record model and calls the shared rules.
- Posted-ledger cash-flow totals and category spend attribution live in `:shared/commonMain`;
  Android maps its Room snapshot at the analytics boundary, and iOS calls the same calculation via
  the narrow native bridge. Both keep date selection and presentation native. Income remains gross
  while its positive fee reduces wallet credit and counts as spending; expenses include positive
  fees, transfers count only positive fees, refunds reduce category spend while retaining positive
  fees, and deleted rows are excluded.
- The optional app-lock PIN length and validation, PBKDF2 work factor, failed-attempt backoff, and
  background grace period also live in `:shared/commonMain`. Each platform keeps verifier storage,
  biometric prompts, and lifecycle handling in its native security boundary.
- Keep platform APIs and persistence behind each client boundary. Android Room entities, SQLCipher,
  Keystore, DataStore, and Android workers stay in `:app`; iOS owns its storage, Keychain, biometric,
  file, and notification adapters.
- Map platform persistence models to platform-neutral models at each repository boundary; promote a
  model to `:shared` when both clients need the same contract. Never expose Room entities, DAOs, or
  SQLite APIs to `commonMain` or SwiftUI.
- Before moving existing financial behavior, add common test vectors and compare Android results to
  the current implementation. Preserve persisted enum names, database meaning, backup JSON fields,
  rounding, and transaction boundaries.
- CI builds the Android app and iOS preview in one workflow, and runs the shared test suite on both
  the Android host and an iOS simulator. Native iOS release readiness remains a separate gate.

## Platform data boundary

- Existing Android data remains in the encrypted Room database. No Android schema, migration,
  backup format, or DataStore key changes are part of the KMP foundation.
- Shared code must remain platform-independent and must not access Android or Apple APIs, storage,
  UI, or secrets directly.
- Persisted enum names remain stable across the move to `commonMain`; common tests lock down their
  Room, DataStore, and backup representations.
- Before iOS should be used with real financial data, validate its encrypted local database and
  Keychain behavior on Apple devices, then implement biometric/app-lock, backup/restore, and export
  flows. Keep iOS data on-device and preserve the existing offline-first and data-minimization rules.
- Do not share Room entities with common code. Shared domain code consumes platform-neutral value
  objects and validated snapshots; repository implementations own persistence on each platform.

## Money and ledger rules

- Money is `Long` minor units + currency code. Never persist money as Float or Double.
- Wallets and ledger amounts use the workspace currency. A foreign-currency transaction also
  stores the original amount, currency, decimal rate and provider date; conversion uses decimal
  arithmetic and rounds to the workspace currency's minor unit.
- The exchange-rate request contains only the currency pair. Transaction amounts, payees and notes
  stay on device. Rates are daily reference rates, not bank/card settlement quotes.
- Commitment targets may be denominated in a currency other than the workspace currency. The
  commitment stores its saved daily reference rate and workspace-currency equivalent so progress,
  reserves, exports and restores remain deterministic without re-fetching a rate.
- Transfers between a user's wallets are not expenditure or income. Fees are expenditure.
- Expected income is not received income. Recurring schedules are forecasts and reminders; they
  never create cash or spending until the user records the actual occurrence. Recording one
  occurrence advances the schedule by exactly one interval, so overdue occurrences remain visible
  for deliberate reconciliation rather than being silently skipped.
- Savings contributions are not ordinary spending when money merely moves between the
  user's own wallets.
- Refunds reduce net spending in the original category. Adjustments never count as income
  or spending.
- Deletions are soft (tombstone) so analytics and future sync never resurrect money history.
- Stable entity IDs, revisions, timestamps and tombstones are the current local foundation for a
  future device-to-desktop sync protocol. They are not a sync protocol by themselves: any future
  implementation must still define device identity, conflict resolution, tombstone retention,
  restore ordering and encrypted transport before it adds wireless, Bluetooth or network sync.
- Android financial writes happen in Room transactions with validation at the repository boundary;
  iOS writes are validated by its repository and committed through the actor-owned SQLCipher store.
- Commitment payments associate one active expense with one obligation; they never create a
  second ledger row. Linked refunds reduce the paid total. Deleting an expense removes its link;
  restoring that expense does not relink it. Transfers and non-expense transactions cannot be
  linked. Archiving an obligation preserves its history but removes it from Outlook reserves and
  reminder scheduling.
- Money Outlook subtracts unpaid obligations due within 30 days from active liquid wallets,
  excludes expected income, and uses recorded daily expense history only after seven observed
  days; otherwise it uses the user's optional daily target.

## Analytics rules

- All financial analytics are deterministic, explainable, locally computed and tested.
- Show the source or basis of estimates in concise in-app copy when it affects interpretation.
  Keep detailed methodology in supporting documentation. Add an in-app explanation only when it
  materially helps users understand a decision-relevant metric.
- Insufficient history is shown honestly: no runway/trend/savings-rate claims without data.
- Charts are always accompanied by a textual interpretation and TalkBack descriptions.
- No opaque financial health score, no creditworthiness claim and no AI-generated advice.

## AI boundary

- Deterministic, locally computed analytics remain the only source of every number shown in the app.
- Any future AI is an optional layer: local-only, opt-in, fact-constrained and verifier-gated. A
  response is discarded unless every claim is traceable to a Kotlin-supplied fact and no new number
  appears. Deterministic copy is shown whenever the model is absent or verification fails.
- No AI model or inference runtime is shipped in the APK, and no AI model download or network
  access is added.
- No financial payload in prompts: only sanitized facts with stable IDs and category labels may be
  sent to a local model, and nothing leaves the device.

## Security and privacy

- No advertising SDK; no financial telemetry; no financial values in logs.
- Guest financial data never leaves the device. The optional rate request sends only currency
  codes over HTTPS to Frankfurter.
- Android backup is disabled and all data domains are excluded from backup/transfer rules.
- Database bytes without the device Keystore key must not be sufficient to read data.
- The app lock PIN is a salted PBKDF2-HMAC-SHA256 hash; verification is constant-time.
- No secrets, service-role keys or API keys in the APK.

## Explicit V1 boundaries

- Transaction import is user-initiated through shared or pasted text for supported African
  mobile-money confirmations (including MTN MoMo, Airtel Money, M-Pesa, Orange Money, Moov, Wave,
  Telecel, Tigo, EcoCash, OPay, PalmPay and Moniepoint). Never request broad SMS access or monitor
  messages in the background. Parse locally, require review before saving, discard the raw message,
  and retain only a normalized provider reference—or a deterministic exact-message digest when no
  provider reference exists—for deduplication. Incoming money must be assigned an explicit income
  category during import review because the message cannot prove whether it is salary, a transfer,
  a reimbursement, a loan or a gift.
- Manual investment snapshots are supported for record-keeping only: name, provider/location,
  broad asset category, cost basis, current manual value, valuation date and note are stored in the
  encrypted local database. They do not create ledger transactions, alter wallet balances, fetch
  market prices, connect to providers, execute trades, or provide investment/tax advice. A future
  trade-history feature must define canonical ledger links and transactionally update both domains.
- The native iOS investment snapshot flow stores integer minor-unit values in its SQLCipher database;
  its additive v4-to-v5 migration retains earlier transaction, goal, and contribution rows.
- No cloud sync implementation in this build; the UI states this and offers encrypted backup.
- Single base currency per workspace; expense and income entry may be converted from another
  supported currency using the latest available daily Frankfurter reference rate. Bills and
  commitments may also use another supported currency and retain the rate used for their target.
- No split transactions yet.
