# Build notes

## Android (primary) - built and tested here
Toolchain installed for this project (user space, no system changes): Flutter 3.47.7 stable in `~/development/flutter`, Temurin JDK 17 in `~/development/jdk17`,
Android SDK (platform 35/36, build-tools 35/36, platform-tools, plus NDK r28c and CMake 3.22.1 that Gradle fetched itself) in `~/Library/Android/sdk`. `source ~/development/env.sh` sets the paths.
```bash
flutter build apk --release --split-per-abi     # arm64-v8a is the one for modern phones; armeabi-v7a for old 32-bit devices
flutter build appbundle --release               # for Play Store
```
Signing: currently the Flutter default (debug key). For distribution create a keystore and configure `android/app/build.gradle.kts` `signingConfigs`.
minSdk/targetSdk come from the Flutter defaults. Permissions: INTERNET, ACCESS_NETWORK_STATE only (no microphone, camera, location, storage).

## iOS - NOT built or tested
This Mac has only the Command Line Tools (no Xcode), so `flutter doctor` reports iOS as unavailable. To build: install Xcode + CocoaPods, `flutter build ios`, set a bundle id/team.
Configured but unverified: `LSApplicationQueriesSchemes: tel`. iOS does not run background sync like Android; this app only syncs in the foreground by design.
