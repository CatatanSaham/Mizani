# Changelog

Notable changes to Mizani are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/2.0.0/), and release versions follow the `MAJOR.MINOR.PATCH` format used by Gradle.

The first recorded version is `1.1.0`; earlier history for the `v1.0.0` tag has not been reconstructed.

## [Unreleased]

### Changed

- Update project references for the repository's move to the Nyota Foundry organization
  (`NyotaFoundry/Mizani`), including README badges and the clone URL, issue-template links,
  release-checklist privacy-policy URLs, the Gradle root project name, and the sideloaded update
  check. Sideloaded builds released before this change may report a failed update check because the
  old GitHub API path redirects; install this build manually once.
- Split continuous integration into separate Android and iOS workflows so each platform reports its
  own status instead of one badge going red for an unrelated platform failure.
- Keep the iOS workflow on the build gate while the `MizaniCore` package test backlog is triaged
  outside CI.

### Fixed

- Fix the iOS Swift package manifest so `swift test --package-path iosApp/MizaniCore` compiles under
  Swift 6.

## [1.13.0] - 2026-11-15

### Added

- Add replayable, feature-specific in-app guides with animated spotlights, a dimmed page that stays readable, steps that switch the Bills tab so recurring schedules are explained rather than skipped, and small page-level help buttons; keep Home focused on the first transaction.
- Add a Kotlin Multiplatform shared money foundation and an early native iOS preview while keeping
  the existing Android data and financial flows in place.
- Share stable finance and preference enums, transaction amount/fee validation, and wallet balance
  rules with iOS while preserving persisted Android values.
- Share curated currency metadata with Android and iOS, and add an initial encrypted iOS flow for
  workspace setup, wallets, expenses, and income.
- Share the built-in category catalog and stable Android category IDs with iOS, add category-aware
  transaction entry, and migrate the iOS encrypted database forward without changing ledger rows.
- Add atomic iOS wallet transfers with shared balance semantics and transfer-fee categorization.
- Add iOS refunds linked to active expenses and signed balance adjustments using shared ledger rules.
- Add iOS transaction editing, reversible deletion, and restore with stable ledger IDs and balance updates.
- Add private, debounced iOS Activity search across transaction notes, types, wallets, categories,
  currencies, and amounts, with lazy row rendering for large ledgers.
- Share Activity search normalization and matching between Android and iOS in KMP.
- Add iOS category creation, renaming, archive/restore, and per-type reordering while preserving
  transaction references in the encrypted local database, with the minimum-active-category rule
  shared through KMP.
- Add KMP-backed iOS income-source kinds, management, and income transaction links; the forward
  schema migration preserves existing nullable source IDs.
- Share posted-ledger cash-flow totals and category spending between Android and iOS, and add a basic
  current-month Insights summary to the iOS preview.
- Share the six-digit app-lock PIN policy, PBKDF2 work factor, retry backoff, and background grace
  period through KMP.
- Add an iOS PIN lock with device-only Keychain storage, biometric unlock, and lifecycle privacy
  shielding; Apple-platform build and device verification remain outstanding.
- Share featured country-pack and wallet defaults with iOS, expose currency precision through KMP,
  and add an iOS first-run preview acknowledgment with country, currency, wallet, and opening-balance
  setup.
- Share decimal-to-minor-unit input parsing and rounding rules across Android and iOS through KMP.
- Make iOS opening balances, transaction inputs, and displayed amounts respect the selected
  currency's minor-unit precision.
- Share savings-goal amount and allocation-overflow rules in KMP; add iOS goal management with
  encrypted, additive storage, atomic linked-wallet contributions, and Hide balances support.
- Share investment asset types, draft validation, and checked portfolio totals through KMP; add
  encrypted iOS investment snapshots with archive/restore and Hide balances support.
- Align Android Gradle Plugin 9.3.1 with Kotlin Multiplatform 2.4.21's published compatibility range.
- Add an initial SQLCipher-backed iOS storage package with a device-only Keychain database key and
  encrypted-file and repository tests.
- Add iOS commitment management for the curated currency set with KMP-backed validation/conversion,
  cached reference rates, and expense-linked progress that accounts for active refunds, using an
  additive encrypted schema migration. iOS reminders and backup/restore remain unavailable.
- Disclose commitment-target currency conversion alongside foreign-currency transaction conversion;
  both requests send currency codes only and save the returned rate and date locally.

### Changed

- Explain how wallet starting balances and recorded activity combine, show a signed balance
  breakdown, and let users record a dated adjustment to match a provider statement.
- Run Android verification and the iOS preview/shared-rule checks in the same CI workflow.
- Make the Xcode-to-Gradle framework build portable across Macs and document the currently
  compatible Apple toolchain without pinning a developer-specific JDK path.
- Advance the iOS encrypted schema with an additive v4-to-v5 investment table migration while
  preserving existing ledger, goal, and contribution records.

### Fixed

- Restore feature-guide spotlights, keep the provider picker usable during its walkthrough step, scroll highlighted controls into view, keep the destination page and its chrome laid out behind every step, move the coach card clear of the highlighted control, and use one provider catalog for selection and review labels.
- Parse shared mobile-money messages and Home dashboard calculations off the UI thread; preserve
  Home-tab navigation after imported transactions; show an actionable recovery screen when saved
  totals cannot be represented; reconcile income fees across wallet balances, spending totals and
  exports; reject out-of-range transaction amounts and fees; and use checked integer arithmetic
  for dashboard and budget totals.
- Use remaining landscape width for the More screen's management and app sections.
- Reject ledger writes, wallet reactivation, restores and backup replacements that overflow checked
  wallet balances, while keeping a repair path for older invalid ledgers.
- Correct the display symbols for Nigerian naira, Ghanaian cedi, euro, and British pound.

## [1.12.0] - 2026-11-14

### Added

- Add searchable country choices worldwide and use the selected country's currency as the onboarding default.

### Changed

- Center single-column More destinations at a consistent readable width and make cards fill their
  content column by default, keeping sibling cards aligned across orientations.

### Fixed

- Anchor the app-lock recovery note at the bottom of the screen, away from the PIN keypad.
- Keep paired metric cards the same height and align labels on pages with info actions.
- Give app-lock keypad buttons a clear outline against the screen gradient.

## [1.11.0] - 2026-11-13

### Added

- Add adaptive two-pane layouts for half-open book and tabletop postures that keep navigation and
  content on either side of the hinge, with slight folds and split-screen windows falling back to
  the single-pane layout.

### Changed

- Make foldable navigation panels navigation-only: the book sidebar and tabletop dock now show the
  Mizani header, the five destinations and one privacy line instead of repeating Home's quick
  actions and workspace name, while Home keeps its action card and the global Add action returns on
  Activity, Insights and More in half-open postures with a pane-contained chooser.

### Fixed

- Keep the single-date picker inside the content pane in half-open postures instead of centering it
  across the hinge, so the calendar and its actions stay on one side of the display.
- Keep an open add chooser across screen rotation: the flat bottom sheet and the half-open
  pane-contained chooser are restored and re-shown after Activity recreation instead of closing
  silently.

## [1.10.0] - 2026-11-13

### Changed

- Redesign the Home screen around a single scrolling dashboard: a full-width gradient balance hero
  with period progress and income, spending and signed net; one quick-actions row for expense,
  income, transfer and import; upcoming bills with date badges and a 7-day due total; a seven-day
  spending pulse; and responsive one- or two-column layouts for phones, foldables and tablets. The
  Home FAB is removed and bottom navigation labels now stay visible down to 300dp.
- Group each day's Activity transactions into a single card with hairline dividers between rows and
  drop the duplicate per-day shown count.
- Redesign Insights into a responsive two-column analysis screen with the cash-flow hero and export
  action in the app bar.
- Bring More and Settings onto the responsive content width and section rhythm, keeping Settings a
  centered 680dp reading column.
- Compute Home's seven-day pulse in a single ledger pass for faster dashboard loads.
- Currency selection now covers all current world currencies with a searchable, full-height picker;
  discontinued codes remain available only for existing records.
- Open balance-visibility prompts directly at the App lock section, with an inline explanation, a
  toast, and automatic scroll.
- Show the installed build code and install source in About & privacy, and let Play-installed
  builds open the Play Store listing.

### Fixed

- Add breathing room below the Bills tabs and more readable line spacing in Bills explanatory copy.
- Add a release-version check and Play update troubleshooting guidance so duplicate version codes,
  wrong tracks/rollouts, and sideload-signature mismatches are caught before publishing.

## [1.9.0] - 2026-11-08

### Added

- Add a first-class Recurring section inside Bills so users can create, edit, archive, record and
  delete repeating bills and expected income without confusing schedules with actual transactions.
- Add a debt workspace with clear empty-state guidance, protected debt summaries, payment progress,
  due dates, and payment recording through the existing transactional ledger.

### Changed

- Standardize Bills and recurring primary call-to-action buttons on the medium corner shape.
- Refine the Daily Momentum card with a compact stat layout, clearer progress hierarchy, and a
  consistent medium-rounded Record today CTA.
- Standardize filled, tonal, and outlined action buttons on the medium corner shape across the app;
  text-only links and icon-only controls remain intentionally lighter.
- Group the Home screen’s primary expense and income actions into a labelled quick-add module for
  clearer dashboard hierarchy.
- Update the Google Play policy audit and release checklist for the 29 October 2026 permission,
  trader-status, age-signals, Japan, and technical-quality changes without adding restricted
  permissions to the app.
- Clarify that recurring schedules are forecasts until the user records an occurrence, and make the
  multi-sheet Excel workbook the recommended export for analysis while retaining CSV compatibility.
- Choose an uninterrupted pane around separating foldable hinges and keep the activity explicitly
  resizable for foldable and multi-window layouts.
- Tighten recurring-item validation and preserve stable IDs, revisions and tombstones as the local
  foundation for a future encrypted device-to-desktop sync protocol.
- Improve custom-accent hero contrast by keeping both gradient stops dark enough for white text.

## [1.8.0] - 2026-11-01

### Added

- Add private, on-device Daily Momentum points, streaks and recognition milestones based on
  tracked calendar days; progress never rewards spending, uses a network, or exposes financial
  details in notifications.

### Changed

- Enable the daily local money reminder by default after onboarding, while preserving an explicit
  Settings opt-out and preventing scheduling before a workspace exists.
- Adapt navigation to use a rail on wider windows and icon-only navigation at narrow or large-font
  scales; reflow Home and Activity actions and summaries instead of squeezing text into rows.
- Clarify Daily Momentum around tracked days and streaks, add a direct record-today action, and
  replace unsupported “unlocked” wording with honest recognition milestones.

### Fixed

- Provide an in-app notification-permission action for the default daily reminder on Android 13+
  instead of leaving delivery dependent on a settings-only link.
- Keep Home, Insights, and new transaction dates current across foregrounding, midnight, and local
  time-zone changes; preserve large monetary summaries at larger text sizes.
- Keep Activity search responsive on large local ledgers by indexing searchable transaction text
  per snapshot and coalescing rapid typing before filtering.
- Re-align shared reminder scheduling when habit-only check-ins are enabled and keep the privacy
  notice aligned with the default reminder behavior.

## [1.7.1] - 2026-10-30

### Changed

- Default the app theme to Light instead of following the system appearance; users can still choose
  Light, Dark or Follow system in Settings.

## [1.7.0] - 2026-10-30

### Added

- Add optional on-device money check-ins for weekly spending, expected income, investment valuation,
  debt payments and savings goals. Check-ins use category controls, a single daily notification
  budget and generic private copy so financial details stay out of notification surfaces.
- Add an accessible Send feedback flow from More and About & privacy that prepares a privacy-safe
  message for the official Mizani contact through the user's email app, with clear delivery and
  sensitive-data guidance.

### Changed

- Prevent previous pages from showing through during route changes by giving every navigation
  destination an opaque, clipped surface and adding a top-level tab regression check.
- Add concise, accessible in-app help popups for unfamiliar money concepts and clarify primary-currency,
  conversion-rate, investment, transaction-type, message-import and notification wording.
- Extend the existing WorkManager reminder schedule to evaluate local habit signals without a
  network, analytics SDK or new account/backend dependency; update the Privacy Notice and security
  guidance to document the local processing and descriptive-only behavior.
- Use Google Play's in-app update flow for Play-installed builds: ordinary releases can download
  flexibly in the background and high-priority releases can request an immediate update when the
  app is active. Sideloaded builds retain the manual GitHub release check.
- Update the Privacy Notice to explain the optional feedback email handoff and email-provider
  processing.

### Fixed

- Ensure feedback emails open with the official recipient, subject and user-entered message
  populated in compatible email clients.
- Prevent the bottom navigation and Add control from flashing before the first route is attached.

## [1.6.0] - 2026-10-30

### Added

- Add offline investment snapshots so users can record a holding's name, provider or location,
  asset category, cost basis, current manual value, valuation date and note without creating a
  duplicate ledger transaction.
- Add protected Investments navigation, archive handling, checked gain/loss summaries, Room
  migration coverage, encrypted-backup portability and an Investments Excel sheet.

### Changed

- Update the in-app Terms and Privacy Notice to describe local investment records and keep the
  feature explicitly separate from brokerage connectivity, trading and financial advice.
- Show reminder times in an explicit locale-aware 12-hour AM/PM format and compare scheduled
  delivery against the full local wall-clock instant so boundary timing is not delayed by a retry window.

## [1.5.1] - 2026-10-30

### Changed

- Update the in-app Terms and Privacy Notice provider details to Paul Ochieng, the supplied
  `paul.ochieng.dev@gmail.com` contact, and Kampala, Uganda; the legal documents now require
  renewed acceptance at their 30 October 2026 revisions.

### Fixed

- Make all application route changes immediate so the previous page is not composited behind the
  destination during Back, CTA, or detail navigation; onboarding keeps its local page animation.

## [1.5.0] - 2026-10-29

### Fixed

- Expand offline mobile-money import detection beyond MTN MoMo and Airtel Money to include
  M-Pesa, Orange Money, Moov, Wave, Telecel, Tigo, EcoCash, OPay, PalmPay, Moniepoint and
  other supported African networks; accept provider `ID:` references, ISO dates and exact-message
  hashes when a provider omits a reference.
- Keep incoming import reviews honest: received money no longer inherits an arbitrary recent
  income category. The review asks the user to choose what the money represents before saving.
- Preserve daily reminder delivery when Android runs a delayed one-shot after its target date;
  the worker now performs the current-day check instead of silently discarding the reminder.
- Make bill payment linking predictable on mobile by showing only eligible expenses (after refunds,
  in the workspace currency, and within the remaining target) and showing link/unlink failures
  beside the bill instead of away from the action.
- Support bills and commitments in a currency different from the workspace, saving the daily
  reference rate and converted workspace target so progress, Money Outlook, exports, and backups
  remain consistent.
- Stabilize the reviewed-import handoff by returning background parsing results to the main UI
  thread before updating Compose state or navigating.

### Changed

- Rework the Home wallet area into a compact grouped list with inline balance privacy and a clear
  `See all` path; show the getting-started action before wallets for empty ledgers and limit quick
  wallet rows to three to keep the screen scannable.
- Clarify Money Outlook copy and mask protected coverage estimates with dots instead of repeating
  the privacy state in a long sentence; the accessible label still explains that the estimate is hidden.
- Keep More-screen detail routes opaque during Back transitions to prevent the reported gray/frozen
  appearance, with regression coverage for Wallets and Categories navigation.
- Improve reminder wording, explain Android background-delivery limits, and add a test-notification
  action so users can verify permission and channel delivery immediately.
- Improve commitment-card spacing so payment summaries, progress details, and payment guidance are
  easier to scan without lines appearing crowded or touching.

## [1.4.0] - 2026-10-28

### Fixed

- Keep Money Outlook's derived coverage and upcoming-payment amounts masked with wallet balances,
  while keeping the saved daily target visible.

### Changed

- Put Bills & commitments in the primary bottom navigation and make the one-off payment flow clear
  to new users.
- Widen the commitment and daily-target dialogs, improve field-level validation, and add a direct
  route to record or link bill payments without duplicating ledger transactions.
- Remove the detailed calculation panel from Money Outlook while retaining a short estimate basis.
- Refine the Home wallet summary so privacy controls are distinct, labels are not duplicated, and a
  single wallet uses the available width.

## [1.3.0] - 2026-10-28

### Added

- Import reviewed MTN MoMo and Airtel Money confirmation text by paste or Android share, with local reference deduplication and no SMS access.
- Track one-off commitments with partial payments linked to existing expenses and optional private reminders.
- Add Money Outlook with a clear 30-day obligation reserve, recorded-spending runway, and a user-set daily target when history is insufficient.

### Fixed

- Keep app lock, appearance preferences, and saved legal acceptance through compatible app updates; only changed legal documents require renewed acceptance.
- Associate imported amounts with the sent or received action, excluding fee and balance values from transaction suggestions.

### Security

- Require fresh PIN or enabled biometric confirmation before exporting financial records or creating encrypted backups.
- Keep Home and Wallets balances concealed until the user confirms with their app PIN or enabled biometrics.
- Process shared transaction text only in memory, discard the source message after review, and keep commitment notifications generic.

### Changed

- Replace deep-teal and true-black dark surfaces with soft-charcoal and warm-slate choices; keep saved theme mode and accent preferences.
- Add active wallet shortcuts to Home, including for a new ledger with no transactions.
- Replace cramped preset accent chips with a spaced custom color picker; saved accents apply across the app.
- Add subtle accent-tinted edges to shared cards and the bottom bar, with stronger definition in dark mode.
- Replace the post-splash loader copy and progress bar with a centered logo and radiating pulse rings.
- Reuse rendered Storyset illustrations on screen revisits instead of parsing the same SVG again.
- Center onboarding content consistently in its available viewport, with scrolling on shorter screens.
- Inset the bottom navigation in a rounded, lightly bordered surface with consistent spacing.
- Open the selected transaction when a row in Home’s recent activity is tapped.
- Clarify the floating Add sheet with equally prominent, descriptive choices for expenses, income, and wallet transfers.
- Make Money Outlook easier to scan with a clearer coverage estimate, concise setup guidance, and expandable calculation details.

### Removed

- Temporarily remove app and budget sharing entry points.

## [1.2.0] - 2026-10-28

### Added

- Added a Storyset illustration to the final onboarding step.
- Added saved appearance preferences for system/light/dark mode, five accent themes, and a true-black dark surface option.
- Added sharing for the official Mizani project link and a reviewed, plan-only text summary for each saved budget.

### Changed

- Simplified first-wallet setup so name suggestions follow the selected wallet type.
- Applied the selected accent and dark surface style across app surfaces while keeping income, expense, transfer, and positive insight colors consistent.
- Updated the Privacy Notice to explain which budget details are sent to an app the user selects for sharing.

### Fixed

- Resuming unfinished setup no longer asks users to accept current Terms and Privacy Notice again.

## [1.1.0] - 2026-10-27

### Added

- Added in-app screens for dependency licenses and required third-party notices.

### Changed

- Licensed Mizani-authored source and executable forms under Apache-2.0, with the original developer and project reference in `NOTICE`; third-party components, artwork, and branding remain separately governed.
- Moved the required Storyset credit from the main About screen into the dedicated Third-party notices screen.
- Updated the Terms and Privacy notices with provider information; the Terms also clarify the Apache source-code grant and separate third-party terms.
