#!/usr/bin/env bash
# Verifies that all required Android permissions are declared in the
# AndroidManifest.xml file. Exits with code 1 if any permission is missing.
#
# Usage: ./scripts/verify_permissions.sh <path-to-manifest>

set -euo pipefail

MANIFEST="${1:-android/app/src/main/AndroidManifest.xml}"

if [ ! -f "$MANIFEST" ]; then
    echo "::error::AndroidManifest.xml not found at: $MANIFEST"
    exit 1
fi

echo "=========================================="
echo "  Android Permission Verification"
echo "=========================================="
echo "Manifest: $MANIFEST"
echo ""

# Required permissions per the app specification.
REQUIRED_PERMISSIONS=(
    "ACCESS_FINE_LOCATION"
    "ACCESS_COARSE_LOCATION"
    "ACCESS_BACKGROUND_LOCATION"
    "FOREGROUND_SERVICE"
    "FOREGROUND_SERVICE_LOCATION"
    "POST_NOTIFICATIONS"
    "WAKE_LOCK"
    "INTERNET"
    "ACCESS_NETWORK_STATE"
)

ALL_FOUND=true
FOUND_COUNT=0
TOTAL=${#REQUIRED_PERMISSIONS[@]}

for perm in "${REQUIRED_PERMISSIONS[@]}"; do
    if grep -q "android.permission.${perm}" "$MANIFEST"; then
        echo "  ✅ ${perm}"
        FOUND_COUNT=$((FOUND_COUNT + 1))
    else
        echo "  ❌ ${perm} — MISSING"
        ALL_FOUND=false
    fi
done

echo ""
echo "Result: ${FOUND_COUNT}/${TOTAL} permissions found"

# Verify foreground service type is declared
echo ""
echo "Checking foreground service type..."
if grep -q 'foregroundServiceType="location"' "$MANIFEST"; then
    echo "  ✅ foregroundServiceType=\"location\" declared"
else
    echo "  ❌ foregroundServiceType=\"location\" NOT declared"
    ALL_FOUND=false
fi

echo ""

if [ "$ALL_FOUND" = true ]; then
    echo "✅ All required Android permissions are present."
    exit 0
else
    echo "::error::Missing required Android permissions. See output above."
    exit 1
fi
