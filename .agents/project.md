# Project Context

FlClash is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. It supports Android, iOS, Windows, macOS, and Linux, using a Material You design with Surfboard-like UI.

## Version Notes

- Release CI pins Flutter 3.44.4. Local SDK may diverge, so trust the CI
  version as the source of truth for release builds.
- Dart SDK constraint: `>=3.8.0 <4.0.0`.

## Build Dependencies

Linux:

```bash
sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev
```

Windows:

- GCC and Inno Setup.
- `ANDROID_NDK` env var for Android builds.

macOS:

```bash
npm install -g appdmg
```

iOS:

- Xcode with the iOS SDK, plus a paid Apple Developer account for the
  Network Extension entitlement.
- `ios/Flutter/FlClash.xcconfig` owns `FLCLASH_BUNDLE_ID`,
  `FLCLASH_TUNNEL_BUNDLE_ID`, `FLCLASH_APP_GROUP`, and
  `FLCLASH_DEVELOPMENT_TEAM`. Change the bundle identifier and team there
  rather than in the Xcode project.
- The App Group and both bundle identifiers must exist in the developer
  account before the app can be signed.
