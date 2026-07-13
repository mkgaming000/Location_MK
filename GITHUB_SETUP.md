# GitHub Setup Guide — Location_MK Repository

This guide walks you through pushing the Live Location Share project to your
`Location_MK` GitHub repository and enabling the CI/CD pipeline.

## Step 1: Create the GitHub Repository

1. Go to [github.com/new](https://github.com/new)
2. Repository name: `Location_MK`
3. Set to **Private** (recommended — the app handles location data)
4. Do NOT initialize with README/license/.gitignore (we have our own)
5. Click **Create repository**

## Step 2: Initialize Git Locally

```bash
cd live_location_share

# Initialize git
git init
git branch -M main

# Stage all files
git add .

# Verify what will be committed
git status

# Commit
git commit -m "Initial commit: Live Location Share app with CI/CD pipeline"
```

## Step 3: Add Remote and Push

```bash
# Replace YOUR_USERNAME with your GitHub username
git remote add origin https://github.com/YOUR_USERNAME/Location_MK.git

git push -u origin main
```

## Step 4: Verify CI/CD Pipeline

1. Go to your repository on GitHub
2. Click the **Actions** tab
3. You should see a workflow run named **"Android APK Automatic Build"**
4. Click on it to view the 21-step pipeline
5. Wait for it to complete (approximately 10-15 minutes)

## Step 5: Download the APK

1. In the completed workflow run, scroll down to **Artifacts**
2. Click **Location-MK-APK** to download
3. Unzip the file — it contains:
   - `app-debug.apk` — debug build for testing
   - `app-release.apk` — release build (debug-signed in CI)
   - `build_info.txt` — version, commit, and build information

## Step 6: Add Real Firebase Configuration (Required for Production)

The CI pipeline uses a placeholder `google-services.json`. For the APK to
actually connect to Firebase, you must add your real config:

### Option A: Commit it to the repo (simple but less secure)

```bash
# Copy your real google-services.json to the project
cp /path/to/your/google-services.json android/app/google-services.json

# Remove it from .gitignore (temporarily)
sed -i '/^google-services.json$/d' .gitignore

git add android/app/google-services.json .gitignore
git commit -m "Add Firebase configuration"
git push
```

### Option B: Use GitHub Secrets (recommended for security)

1. Encode your `google-services.json` as base64:
   ```bash
   base64 -i google-services.json | pbcopy  # macOS
   # or
   base64 -w 0 google-services.json  # Linux
   ```

2. Add it as a GitHub repository secret:
   - Go to Settings → Secrets and variables → Actions
   - Click **New repository secret**
   - Name: `GOOGLE_SERVICES_JSON_BASE64`
   - Value: (paste the base64 string)

3. Add a step to the workflow (before the Firebase check):
   ```yaml
   - name: Decode Firebase config from secret
     if: env.GOOGLE_SERVICES_JSON_BASE64 != ''
     env:
       GOOGLE_SERVICES_JSON_BASE64: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
     run: |
       echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 -d > android/app/google-services.json
   ```

## Troubleshooting

### Build Fails: "Firebase configuration missing"
This is a WARNING, not an error. The pipeline creates a placeholder and
continues. The APK will compile but won't connect to Firebase. Follow Step 6
above to add real Firebase config.

### Build Fails: "flutter analyze found errors"
Run locally:
```bash
flutter analyze
```
Fix all errors, commit, and push again.

### Build Fails: "Unit tests failed"
Run locally:
```bash
flutter test
```
Fix failing tests, commit, and push again.

### Build Fails: "Security scan detected exposed secrets"
The security scan found what looks like an API key, token, or password in
your source code. Either:
- Remove the secret from source code
- Move it to an environment variable or GitHub Secret
- Add a `// noscan` comment if it's a false positive

### Build Fails: "Missing required Android permissions"
The AndroidManifest.xml is missing one of the required permissions. Check
the workflow log for which permission is missing and add it to the manifest.

### Build Fails: Gradle error
Common causes:
- Incompatible dependency versions
- Missing SDK component
- Cache corruption

Try:
```bash
flutter clean
flutter pub get
cd android && ./gradlew clean && cd ..
flutter build apk
```

### APK artifact not found
The workflow verifies APK output exists. If this fails, check:
- `flutter build apk` step completed successfully
- No Gradle errors in the build step
- The output path matches `build/app/outputs/flutter-apk/`

## Workflow Configuration

The workflow can be customized via environment variables at the top of
`.github/workflows/android-build.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `FLUTTER_CHANNEL` | `stable` | Flutter channel (stable/beta/dev) |
| `JAVA_VERSION` | `17` | Java JDK version |
| `ARTIFACT_NAME` | `Location-MK-APK` | Artifact name for APK upload |
| `VERSION_PREFIX` | `Location-MK-v1` | Version prefix for automatic versioning |
| `PROJECT_DIR` | `.` | Flutter project root (change if in subdirectory) |

## Manual Trigger

To run the workflow manually:
1. Go to Actions tab
2. Select "Android APK Automatic Build"
3. Click "Run workflow"
4. Select the branch (main)
5. Click "Run workflow"
