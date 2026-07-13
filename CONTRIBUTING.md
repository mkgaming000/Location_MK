# Contributing to Live Location Share

Thank you for your interest in contributing! This document outlines the
development workflow and standards for this project.

## Development Setup

1. Install Flutter SDK >= 3.22.3
2. Install Android Studio (for Android SDK + emulator)
3. Install Java 17 (Temurin distribution recommended)
4. Fork & clone the repository
5. Run `flutter pub get` in the `live_location_share/` directory
6. Create a Firebase project and place `google-services.json` at
   `android/app/google-services.json`
7. Run `flutter run` to launch on a device or emulator

## Code Style

- Run `dart format lib/ test/` before every commit
- Run `flutter analyze` and fix all warnings before pushing
- Use `flutter_lints` (already configured in `analysis_options.yaml`)
- Prefer `const` constructors wherever possible
- Never commit hardcoded secrets, API keys, or passwords

## Pull Request Checklist

- [ ] `dart format` passes with no changes
- [ ] `flutter analyze` passes with no warnings
- [ ] `flutter test` passes
- [ ] No TODO/FIXME/XXX/HACK comments left in code
- [ ] No hardcoded secrets in source
- [ ] All new screens handle loading, empty, and error states
- [ ] All async operations handle failures gracefully
- [ ] Streams are cancelled in `dispose()`
- [ ] Database writes use `.set()` (overwrite), never `.push()` (history)

## Security Guidelines

This app handles live location data — security is paramount.

- **Never** store location history. Each publish must overwrite the previous
  value via `DatabaseReference.set()`.
- **Never** expose a device's location to non-paired users. All reads go
  through Firebase Database rules that verify pairing.
- **Never** add a "track by phone number" feature. Pairing must always
  require explicit Device ID or QR code exchange.
- **Always** request runtime permissions before accessing location.
- **Always** provide a visible way to stop sharing (in-app + notification).
- **Always** validate user input (device IDs, names) for length and format.

## Testing

- Unit tests live in `test/` and run via `flutter test`
- Write tests for all new models, services, and utility functions
- For UI tests, use `flutter_test`'s `WidgetTester`
- Integration tests should go in `integration_test/`

## CI/CD

GitHub Actions runs on every push and PR:

1. **Analyze & Test** — format check, static analysis, unit tests
2. **Security Audit** — secrets scan, rules validation, permission checks
3. **Build APK** — release APK build + artifact upload

All three must pass for a PR to be merged.

## Release Process

1. Update `version:` in `pubspec.yaml` (semver)
2. Update `CHANGELOG.md` (if present)
3. Tag the commit: `git tag v1.x.y && git push --tags`
4. CI will build the release APK automatically
5. Download the APK artifact from the Actions tab
6. Distribute via your preferred channel (Play Console, direct APK, etc.)

## Questions?

Open an issue with the `question` label.
