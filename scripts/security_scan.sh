#!/usr/bin/env bash
# Security scan — checks for exposed secrets, API keys, tokens, and
# passwords in the source code. Exits with code 1 if any secret is found.
#
# Usage: ./scripts/security_scan.sh <project-root>

set -euo pipefail

PROJECT_ROOT="${1:-.}"

echo "=========================================="
echo "  Security Scan"
echo "=========================================="
echo "Scanning directory: $PROJECT_ROOT"
echo ""

SECRETS_FOUND=false

# --- 1. Check for API keys, tokens, passwords in Dart source ---
echo "1. Scanning Dart source for hardcoded secrets..."
# Match patterns like: apiKey = "AIza...", api_key: "xxx", password = "yyy"
# Exclude comments and the placeholder google-services.json
SECRET_PATTERN='(api[_-]?key|secret|password|token|bearer|private[_-]?key)\s*[:=]\s*["\x27][^"\x27]{12,}["\x27]'

if grep -rnE "$SECRET_PATTERN" \
    --include="*.dart" \
    --include="*.kt" \
    --include="*.java" \
    --include="*.gradle" \
    --include="*.properties" \
    "$PROJECT_ROOT" 2>/dev/null | grep -v "//" | grep -v "PLACEHOLDER" | grep -v "test/"; then
    echo "  ❌ Hardcoded secret detected in source code!"
    SECRETS_FOUND=true
else
    echo "  ✅ No hardcoded secrets in source code."
fi
echo ""

# --- 2. Check for GitHub tokens ---
echo "2. Scanning for GitHub tokens..."
if grep -rnE '(ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82})' \
    --include="*.dart" \
    --include="*.kt" \
    --include="*.java" \
    --include="*.yml" \
    --include="*.yaml" \
    --include="*.json" \
    --include="*.gradle" \
    --include="*.properties" \
    --include="*.md" \
    "$PROJECT_ROOT" 2>/dev/null; then
    echo "  ❌ GitHub token detected in repository!"
    SECRETS_FOUND=true
else
    echo "  ✅ No GitHub tokens found."
fi
echo ""

# --- 3. Check for AWS keys ---
echo "3. Scanning for AWS access keys..."
if grep -rnE '(AKIA[0-9A-Z]{16})' \
    --include="*.dart" \
    --include="*.kt" \
    --include="*.yml" \
    --include="*.yaml" \
    --include="*.json" \
    "$PROJECT_ROOT" 2>/dev/null; then
    echo "  ❌ AWS access key detected!"
    SECRETS_FOUND=true
else
    echo "  ✅ No AWS keys found."
fi
echo ""

# --- 4. Check for private keys ---
echo "4. Scanning for private keys..."
if grep -rn "BEGIN.*PRIVATE KEY" \
    --include="*.dart" \
    --include="*.kt" \
    --include="*.pem" \
    --include="*.key" \
    --include="*.txt" \
    "$PROJECT_ROOT" 2>/dev/null; then
    echo "  ❌ Private key detected!"
    SECRETS_FOUND=true
else
    echo "  ✅ No private keys found."
fi
echo ""

# --- 5. Check for common password patterns ---
echo "5. Scanning for password assignments..."
if grep -rnE '(password|passwd|pwd)\s*[:=]\s*["\x27][^"\x27]{6,}["\x27]' \
    --include="*.dart" \
    --include="*.kt" \
    --include="*.gradle" \
    --include="*.properties" \
    "$PROJECT_ROOT" 2>/dev/null | grep -v "//" | grep -v "test/" | grep -v "keyPassword" | grep -v "storePassword"; then
    echo "  ❌ Password pattern detected!"
    SECRETS_FOUND=true
else
    echo "  ✅ No password patterns found."
fi
echo ""

# --- 6. Check for .env files committed ---
echo "6. Checking for committed .env files..."
if find "$PROJECT_ROOT" -name ".env" -not -path "*/.dart_tool/*" -not -path "*/build/*" 2>/dev/null | head -5; then
    echo "  ⚠️  .env file found — ensure it's in .gitignore"
else
    echo "  ✅ No .env files found."
fi
echo ""

# --- Summary ---
echo "=========================================="
if [ "$SECRETS_FOUND" = true ]; then
    echo "  ❌ SECURITY SCAN FAILED — secrets detected!"
    echo "=========================================="
    exit 1
else
    echo "  ✅ SECURITY SCAN PASSED — no secrets found."
    echo "=========================================="
    exit 0
fi
