# iOS client foundation

`Mizani.xcodeproj` is a native SwiftUI shell that consumes the `MizaniShared` Kotlin/Native
framework from `:shared`. It currently shares the money value and currency model with Android.

## Compatible Mac toolchain

The current versions are Kotlin 2.4.21, Gradle 9.6.0, and Android Gradle Plugin 9.3.1. Kotlin's
compatibility table lists Xcode 26.4 for this combination. Use macOS Tahoe 26.2 or later, which
supports Xcode 26.4. Do not assume a later Xcode release is compatible until Kotlin's table lists it.

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

This is an integration and design preview. Financial persistence, encryption, onboarding, ledger
entry, import/export, app lock, notifications, and full Settings flows are not implemented in the
iOS client. Do not submit this target to the App Store until those flows are complete and have
passed device testing and the release gates in `docs/IOS_APP_STORE_READINESS.md`.
