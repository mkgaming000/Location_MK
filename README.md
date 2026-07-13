# Live Location Share

A permission-based live location sharing Flutter application built with Firebase.
This app allows users to share their live GPS location with other connected (paired) users in real-time.
**This is NOT a mobile number tracking app.** Both users must install the app and explicitly agree to share their location.

## Features

- Anonymous Firebase Authentication
- Real-time GPS location updates (3-5 second intervals)
- Android Foreground Service for background location sharing
- Persistent notification with "Stop Sharing" action
- Device pairing via Device ID or QR Code (bidirectional verification)
- Online/Offline status for connected devices
- Copy GPS coordinates to clipboard
- Open coordinates directly in Google Maps (app or web fallback)
- Material 3 design with Dark/Light/System mode support
- No location history ever stored (only latest location kept)
- Automatic reconnection after network recovery
- Battery-efficient implementation (10s heartbeat, throttled status polling)
- Comprehensive error handling with user-friendly messages
- Editable device name

## Tech Stack

- **Flutter** 3.22+ + **Dart** 3.3+
- **Firebase Authentication** (Anonymous)
- **Firebase Realtime Database**
- **Material Design 3**
- Packages: `geolocator`, `flutter_background_service`, `flutter_local_notifications`, `permission_handler`, `qr_flutter`, `mobile_scanner`, `connectivity_plus`, `provider`, `google_fonts`, `url_launcher`, `share_plus`

## Project Structure

```
live_location_share/
├── .github/workflows/
│   └── android-build.yml          # CI/CD: analyze, test, security audit, build APK
├── android/
│   ├── app/
│   │   ├── build.gradle           # AGP 8.3.2, Kotlin 1.9.23, minSdk 23, targetSdk 34
│   │   ├── google-services.json   # REPLACE with your Firebase config
│   │   ├── proguard-rules.pro
│   │   └── src/main/
│   │       ├── AndroidManifest.xml # All permissions + foreground service
│   │       ├── kotlin/com/livelocation/app/MainActivity.kt
│   │       └── res/               # Material 3 styles, adaptive icon, etc.
│   ├── build.gradle
│   ├── settings.gradle.kts
│   └── gradle/wrapper/gradle-wrapper.properties
├── lib/
│   ├── main.dart                  # App entry, service init, Provider setup
│   ├── models/
│   │   ├── device.dart
│   │   └── live_location.dart
│   ├── screens/
│   │   ├── home_screen.dart       # Two big cards: Share / Receive
│   │   ├── share_screen.dart      # GPS/Internet/Sharing status + ON/OFF switch
│   │   ├── receiver_screen.dart   # Paired devices list + live location detail
│   │   └── pair_device_screen.dart # My QR code / Add by ID or scan
│   ├── services/
│   │   ├── auth_service.dart      # Firebase anonymous auth (singleton)
│   │   ├── background_service.dart # Foreground service isolate
│   │   ├── device_identity.dart   # UUID generation + persistence
│   │   ├── firebase_service.dart  # Realtime DB reads/writes
│   │   ├── location_service.dart  # Geolocator + connectivity wrapper
│   │   └── theme_controller.dart  # Theme mode persistence
│   ├── utils/
│   │   ├── constants.dart         # App-wide constants
│   │   ├── error_messages.dart    # Firebase error → human message
│   │   ├── permissions.dart       # Runtime permission helpers
│   │   └── theme.dart             # Material 3 light/dark themes
│   └── widgets/
│       ├── copy_button.dart       # Copy-to-clipboard button
│       ├── device_card.dart       # Paired device card
│       ├── states.dart            # EmptyState / ErrorState / LoadingState
│       └── status_card.dart       # Status display card
├── test/
│   └── models_test.dart           # Unit tests for models + constants
├── database.rules.json            # Firebase Realtime DB security rules
├── firebase.json
├── pubspec.yaml
├── analysis_options.yaml
├── CONTRIBUTING.md
└── README.md
```

## Setup Instructions

### 1. Install Prerequisites

- Flutter SDK >= 3.22.3 (`flutter doctor` should pass)
- Android Studio (for Android SDK + emulator)
- Java 17 (Temurin distribution recommended)
- A Firebase project (free tier is fine)

### 2. Create a Firebase Project

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Create a new project
3. Enable **Authentication** → Sign-in method → **Anonymous**
4. Enable **Realtime Database** → Start in test mode initially
5. Add an Android app:
   - Package name: `com.livelocation.app`
   - Download `google-services.json`
   - Place it at `live_location_share/android/app/google-services.json`
6. After testing, replace the test-mode rules with the contents of
   `database.rules.json` from this repo

### 3. Apply Database Security Rules

Copy the contents of `database.rules.json` into the Realtime Database Rules
tab in Firebase Console. These rules enforce:

- A device's live location can ONLY be read by its owner OR by devices that
  have an entry under `pairings/{their_device_id}/{my_device_id}` (i.e.
  the target device has explicitly paired with the reader).
- Only the authenticated owner (matching `user_devices/{uid}/device_id`)
  can write to `live_locations/{device_id}`.
- Pairings can only be written by the owner of the parent device_id.
- All fields are validated for type and reasonable ranges (latitude
  -90..90, longitude -180..180, accuracy 0..5000m, name ≤100 chars).
- No extra fields are allowed (`$other: { ".validate": false }`).

### 4. Build & Run

```bash
cd live_location_share
flutter pub get
flutter run                    # debug mode
flutter build apk --release    # release APK
```

## Android Permissions

The app requests the following permissions at runtime:

| Permission | Purpose |
|---|---|
| `ACCESS_FINE_LOCATION` | Precise GPS coordinates |
| `ACCESS_COARSE_LOCATION` | Approximate location fallback |
| `ACCESS_BACKGROUND_LOCATION` | Continue sharing when app is minimized |
| `FOREGROUND_SERVICE` | Run the persistent notification service |
| `FOREGROUND_SERVICE_LOCATION` | Foreground service type (Android 14+) |
| `POST_NOTIFICATIONS` | Show the persistent notification (Android 13+) |
| `WAKE_LOCK` | Keep CPU awake during location updates |
| `INTERNET` | Sync with Firebase |
| `ACCESS_NETWORK_STATE` | Detect network changes for auto-reconnect |
| `CAMERA` | Scan QR codes for pairing |

## How It Works

### Pairing Flow

1. Each installation generates a unique Device ID (UUID v4) on first launch,
   stored in `SharedPreferences`.
2. The device ID is registered under `user_devices/{uid}/device_id` in
   Firebase — this is the keystone of the security model.
3. Users pair by exchanging Device IDs (typed or via QR code).
4. Pairing writes an entry to `pairings/{my_device_id}/{their_device_id}`.
5. **Pairing is one-directional**: pairing with them allows YOU to read THEIR
   location. For mutual visibility, both sides must pair independently.

### Sharing Flow

1. User taps "Start Sharing" → app requests location + notification permissions.
2. Android Foreground Service starts with a persistent notification.
3. The service writes the latest GPS coordinates to
   `live_locations/{device_id}` every 3-5 seconds via `.set()` (overwrite,
   no history).
4. A 10-second heartbeat timer refreshes the `online` flag and `timestamp`
   even without movement.
5. Sharing continues when the app is minimized, screen is locked, or screen
   is off.
6. User can stop sharing via the in-app button or the notification action.

### Receiving Flow

1. Receiver screen subscribes to `live_locations/{paired_device_id}` via
   Firebase `onValue` stream.
2. DB rules verify the pairing exists before allowing the read.
3. When the paired device updates its coordinates, the receiver sees them
   in real-time.
4. Tapping a device expands a detail panel with lat/lng/accuracy/last-updated.
5. Buttons let the user copy coordinates or open them in Google Maps.

### Background Service Isolate

The foreground service runs in a separate Dart isolate. This means:

- Auth state does NOT transfer — the isolate signs in anonymously and gets
  its own UID.
- The isolate registers its UID → device_id mapping in `user_devices/`
  before publishing, so DB rules accept its writes.
- The isolate handles its own Firebase initialization, network reconnect,
  and location monitoring.
- Publish failures retry up to 3 times with exponential backoff.

## Privacy & Security

- **No location history**: Every publish uses `.set()` (overwrite), never
  `.push()` (append). Only the latest single point exists at any time.
- **Pairing enforcement**: DB rules verify `pairings/{target_device_id}/{my_device_id}`
  exists before allowing a read. Non-paired users cannot read your location.
- **No mobile number tracking**: The app does not collect, store, or transmit
  phone numbers. Pairing requires explicit Device ID or QR code exchange.
- **Owner-only writes**: Only the UID registered under `user_devices/{uid}/device_id`
  can write to `live_locations/{device_id}`.
- **Encrypted transport**: All communication uses HTTPS via Firebase.
- **No analytics**: The app does not include any analytics or advertising SDKs.
- **No backup**: `android:allowBackup="false"` prevents location data from
  being included in Google cloud backups.
- **Field validation**: DB rules validate all fields for type and range —
  no malformed data can be written.

## Error Handling

The app handles the following error scenarios with user-friendly messages:

- Permission denied / permanently denied (with "Open Settings" action)
- GPS disabled (with "Open Settings" action)
- Internet disconnected (with auto-reconnect on recovery)
- Receiver offline (shows "Offline" status with last-seen time)
- Firebase unavailable (retry with backoff)
- Location unavailable (graceful degradation)
- QR code scan errors (debounced, with retry)
- Pairing errors (duplicate, self-pairing, network)

## CI/CD — Android APK Automatic Build

GitHub Actions (`.github/workflows/android-build.yml`) runs automatically on
every push to `main`, on pull requests, and via manual `workflow_dispatch`.

### Pipeline Steps (21 steps in a single job)

| # | Step | Description |
|---|------|-------------|
| 1 | Checkout | Fetch repository with full history |
| 2 | Setup Java 17 | Temurin distribution |
| 3 | Setup Flutter | Stable channel, cached |
| 4 | Cache Gradle | Speeds up subsequent builds |
| 5 | Cache Pub | Speeds up dependency resolution |
| 6 | Verify Java | `java -version` output check |
| 7 | Verify Flutter | `flutter --version` output check |
| 8 | Flutter Doctor | `flutter doctor -v` health check |
| 9 | Firebase Check | Verifies `google-services.json` exists; creates placeholder if missing |
| 10 | Permission Check | Verifies all 9 required Android permissions in manifest |
| 11 | Security Scan | Scans for API keys, tokens, passwords, private keys, `.env` files |
| 12 | Pub Get | `flutter pub get` — install dependencies |
| 13 | Analyze | `flutter analyze --no-fatal-infos` — static analysis |
| 14 | Test | `flutter test` — unit tests |
| 15 | Versioning | Generates `Location-MK-v1.<run_number>` + updates pubspec.yaml |
| 16 | Build Debug | `flutter build apk --debug` |
| 17 | Build Release | `flutter build apk --release` |
| 18 | Verify APK | Confirms APK files exist in output directory |
| 19 | Upload Artifact | Uploads `Location-MK-APK` artifact (30-day retention) |
| 20 | Upload Logs | On failure, uploads build logs for debugging |
| 21 | BUILD STATUS Report | Generates markdown summary table in Actions UI |

### Automatic Versioning

Each build generates a version string: `Location-MK-v1.<run_number>`

The version is:
- Written to `pubspec.yaml` (so the APK embeds it)
- Written to `build_info.txt` (included in the artifact)
- Displayed in the GitHub Actions step summary

### BUILD STATUS Report

The final step generates a markdown report visible in the Actions UI:

```
## 📱 BUILD STATUS — PASS/FAIL

| Step | Status |
|------|--------|
| Firebase Config | ✅ PASS / ⚠️ WARN |
| Android Permissions | ✅ PASS / ❌ FAIL |
| Security Scan | ✅ PASS / ❌ FAIL |
| Flutter Pub Get | ✅ PASS / ❌ FAIL |
| Flutter Analyze | ✅ PASS / ❌ FAIL |
| Unit Tests | ✅ PASS / ❌ FAIL |
| Debug APK Build | ✅ PASS / ❌ FAIL |
| Release APK Build | ✅ PASS / ❌ FAIL |
| APK Verification | ✅ PASS / ❌ FAIL |
| Artifact Upload | ✅ PASS / ❌ FAIL |
```

### Error Handling

The pipeline stops immediately on any error and shows the complete log.
On failure, build logs are uploaded as a separate artifact for debugging.

**Detected error types:**
- Dependency errors (`flutter pub get` failure)
- Gradle failures (`flutter build apk` Gradle errors)
- Flutter compile errors (`flutter build apk` Dart errors)
- Missing Firebase configuration (`google-services.json` not found)
- Android manifest permission validation (missing required permissions)
- Security violations (exposed API keys, tokens, passwords)

### Downloading the APK

1. Go to the **Actions** tab in your GitHub repository
2. Click on the latest workflow run
3. Scroll down to **Artifacts**
4. Download `Location-MK-APK` (contains `app-debug.apk`, `app-release.apk`, and `build_info.txt`)

### Local Testing of CI Scripts

```bash
# Test permission verification
./scripts/verify_permissions.sh android/app/src/main/AndroidManifest.xml

# Test security scan
./scripts/security_scan.sh .

# Test build info generation
./scripts/generate_build_info.sh "Location-MK-v1.42" "abc123" "main" "42"
```

### Release Signing (Optional)

For Play Store-ready release builds, provide a signing keystore:

1. Generate a keystore:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties`:
   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```

3. Add `key.properties` and `*.jks` to `.gitignore` (already configured)

4. Push to GitHub — the workflow will detect the keystore and use it for
   release signing. Without a keystore, release builds use debug signing
   (fine for testing, not for Play Store).

## License

This project is provided as-is for educational and production use.
