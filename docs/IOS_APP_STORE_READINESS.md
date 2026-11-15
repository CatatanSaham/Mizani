# iOS and App Store readiness

**Status:** Not ready for financial use or App Store submission. Reviewed against Apple and Kotlin
official guidance on 14 November 2026.

The current `iosApp` target is an incomplete SwiftUI development preview. It has an early SQLCipher
storage foundation and workspace, wallet, categorized expense/income, income-source, transfer, refund,
balance-adjustment, category-management, transaction edit/delete/restore, and basic current-month
cash-flow/category-summary flows, plus savings goals with optional linked-wallet contributions and
manual investment snapshots with KMP-backed validation, portfolio totals, and archive/restore. Goal
amount validation comes from KMP and linked transfers, contribution history, and allocation updates are
committed together in the encrypted store. Investment records use an additive v4-to-v5 encrypted-schema
migration. The summary uses the common KMP analytics rule. The source also has
an initial app-lock PIN and optional biometric flow. First-run setup now warns about preview limits
and uses shared country, currency, and wallet choices; that acknowledgment is not legal consent. The client has not
been built or run with Xcode in the current Windows environment and is not ready for real financial
records. The Android app remains the only complete client. This checklist is a release gate, not a
claim of legal approval or App Store acceptance.

The source now also includes KMP-backed commitment currency rules, encrypted commitment management,
cached currency-rate lookup, and progress linked to existing expenses. The additive v5-to-v6 migration,
SwiftUI flow, and repository tests have not been compiled or run with Xcode. iOS commitment reminders
and backup/restore are not implemented.

The iOS setup currently offers seven featured country packs plus “Other” and ten curated currencies.
Android accepts a broader runtime ISO-country currency set, so currency-option parity remains work.
Foreign-currency transaction entry and several Android financial features are still absent.

## Before building the iOS client further

- Use macOS Tahoe 26.2 or later with Xcode 26.4.x for the current Kotlin 2.4.21 line. The project
  uses Gradle 9.6.0 and AGP 9.3.1, within Kotlin's published KMP compatibility ranges. Build and run
  on an iOS simulator and a physical device before calling the iOS client functional; Windows checks
  cannot establish the Apple framework build. Wait for Kotlin's compatibility table to list a newer
  Xcode line before upgrading Xcode.
- Confirm the Apple team, bundle identifier, deployment target, app icon, signing, version/build
  values, privacy policy URL, support contact, category, age rating, screenshots, and review notes.
- Complete the remaining native iOS equivalents of the rest of the ledger features,
  backup and restore, unencrypted export warnings, file sharing, imports, reminders, settings, legal
  documents, and accessibility behavior. Budgets/recurring schedules, commitment reminders, debts, and full
  Insights parity also remain absent. The app-lock PIN, biometric unlock, and lifecycle shield now
  exist in source but remain uncompiled and unverified on Apple platforms. Keep the app usable
  without an account and keep financial records on the device.
- Keep the first-run preview warning distinct from legal consent. Adapt and review iOS-specific legal
  documents before adding a legal-consent gate or submitting the app.
- Validate Keychain accessibility, file protection, ciphertext, relaunch persistence, locked-device
  behavior, and recovery on simulator and physical hardware before using iOS storage for financial
  data. The current package tests do not exercise the iOS-only protection attributes.
- Design and test iOS key storage and backup exclusion deliberately. Android Keystore and SQLCipher
  behavior cannot be assumed to transfer to iOS. Preserve the documented encrypted-backup format
  or provide a compatible import/export path before claiming cross-platform data portability.
- Keep third-party frameworks minimal. Audit the final archive for bundled privacy manifests,
  required-reason API use, licenses, and actual network/data behavior. The empty manifest in the
  preview is not a completed production audit.

## App Store review gates

- **App completeness:** remove preview labels and incomplete/placeholder paths only after the
  corresponding features work. Apple guideline 2.1 expects final, tested, functional submissions;
  the current iOS shell does not meet that bar.
- **Privacy policy:** provide a public privacy-policy URL in App Store Connect and an easily
  accessible policy inside the app. The current project has no confirmed public URL. Adapt the
  Android-specific runtime Privacy Notice to actual iOS storage, backup, permissions, exports, and
  network behavior before publication.
- **App Privacy details:** declare the real practices of the iOS binary and every SDK in App Store
  Connect. Apple answers are app-level, so disclose any collection on either platform. Recheck the
  optional Frankfurter exchange-rate request and any feedback or diagnostics integration when they
  are ported.
- **Privacy manifest:** validate `PrivacyInfo.xcprivacy` and the manifests of every included SDK.
  Update required-reason API declarations if the final application or dependencies use covered APIs.
- **Publisher eligibility:** Apple guideline 3.2.1(viii) says apps used for financial trading,
  investing, or money management should come from the financial institution performing those
  services. Guideline 5.1.1(ix) also addresses apps that require sensitive user information and
  legal-entity submission. Confirm Mizani's classification and the appropriate publisher with
  Apple and qualified counsel before creating a release listing.
- **Encryption/export compliance:** if the production iOS app incorporates encryption, answer the
  App Store Connect export-compliance questions for the actual algorithms and distribution
  regions. Do not mark the app exempt without confirming the applicable requirements.
- **Review access and quality:** provide working review access that does not expose real user data,
  exercise the first-run experience, VoiceOver and Dynamic Type, safe areas, rotation, offline use,
  file flows, upgrade behavior, and error recovery on supported iOS versions. Do not submit an
  untested iOS build.

## Official references

- [Kotlin Multiplatform compatibility guide](https://kotlinlang.org/docs/multiplatform/multiplatform-compatibility-guide.html)
- [Kotlin direct Xcode integration](https://kotlinlang.org/docs/multiplatform/multiplatform-direct-integration.html)
- [Apple Xcode and macOS system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Kotlin: add KMP to an existing Android project](https://developer.android.com/kotlin/multiplatform/migrate)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: manage app privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Apple privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
