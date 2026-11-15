# iOS client foundation

`Mizani.xcodeproj` is a native SwiftUI client that consumes the `MizaniShared` Kotlin/Native
framework from `:shared` and the local `MizaniCore` Swift package. Shared money values, finance
enums, transaction validation, wallet balance rules, income-source kinds, and the stable built-in
category catalog come from KMP. The iOS client creates a UGX workspace and wallets, supports
categorized expense and income entry, income-source management and links, atomic wallet transfers,
linked refunds, signed balance adjustments, transaction editing, reversible deletion and restore,
category management, savings goals with optional atomic linked-wallet transfers, and manual investment
snapshots with KMP-backed validation and portfolio totals. The iOS investment table is added by a
forward-only v4-to-v5 migration. A current-month cash-flow and spending-by-category summary comes from
the shared KMP analytics rule. It displays locally calculated balances from the SQLCipher-backed store.
Forward database migrations preserve prior transaction category and income-source references. An
optional six-digit app lock, shared KMP retry policy, biometric unlock, and lifecycle privacy shield
are implemented in source. The client is still incomplete and has not been built or run with
Xcode in this Windows environment. Use test data only until macOS CI and physical-device security
checks pass.

## Compatible Mac toolchain

The project uses Kotlin 2.4.21, Gradle 9.6.0, and Android Gradle Plugin 9.3.1. This combination is
inside Kotlin's published KMP compatibility ranges (Gradle through 9.7.0 and AGP through 9.3.1).
The table lists Xcode 26.4; use macOS Tahoe 26.2 or later, which supports Xcode 26.4. The framework
and app still need to build on macOS before this toolchain can be considered verified. Do not assume
a later Xcode release is compatible until Kotlin's table lists it.

Install Xcode and complete its first-launch setup, then confirm the active developer directory with
`xcode-select -p`. Install Android Studio and Android SDK Platform 37 if you also plan to build and
test the Android app on this Mac. Gradle's checked-in daemon criteria select JetBrains Runtime 25;
the Xcode build phase uses a local JDK 17 or newer to start Gradle and can use Android Studio's
bundled JBR. If automatic discovery does not find it, set `JAVA_HOME` or `ANDROID_STUDIO_JDK`.

## Build the simulator preview

From the repository root:

```sh
xcodebuild -project iosApp/Mizani.xcodeproj -scheme Mizani \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The Xcode build phase calls `scripts/ios/build-shared-framework.sh`, which resolves a local JDK and
invokes the Gradle wrapper through `/bin/sh`. Alternatively, open `Mizani.xcodeproj`, select the
**Mizani** scheme and an installed simulator, then build and run. The command above compiles the app
and shared framework but does not launch the simulator or validate runtime behavior.

The storage and initial repository have package tests. On macOS with Xcode 26.4 and Swift 6 or newer,
run them with:

```sh
swift test --package-path iosApp/MizaniCore
```

These package tests do not replace simulator and physical-device checks for Keychain accessibility,
file protection, relaunch persistence, or the complete finance flows.

This remains a development preview. Workspace, wallet, ledger, Activity, category-management,
basic monthly analytics, and app-lock flows are implemented in source, but iOS Keychain accessibility,
file protection, relaunch behavior, and those flows still need simulator and physical-device verification.
Budgets, recurring items, commitments, debts, full Android Insights parity,
imports/exports, notifications, and full Settings flows are not yet implemented in the iOS client.
The app-lock source and package tests also require macOS/Xcode compilation and Apple-device
verification. Do not submit this target to the App Store until those flows are complete and have passed
device testing and the release gates in
`docs/IOS_APP_STORE_READINESS.md`.
