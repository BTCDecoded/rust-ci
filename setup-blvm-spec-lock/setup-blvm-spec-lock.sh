#!/usr/bin/env bash
# Clone BTCDecoded/blvm-spec-lock for CI path dependency resolution.
# Default: sibling of repo root at ../blvm-spec-lock (matches [patch.crates-io] and path deps).
set -euo pipefail

REPO_ROOT="$(pwd)"
REPO_URL="${SETUP_BLVM_SPEC_LOCK_REPO:-https://github.com/BTCDecoded/blvm-spec-lock.git}"
DEPTH="${SETUP_BLVM_SPEC_LOCK_DEPTH:-1}"
DEST="$(dirname "$REPO_ROOT")/blvm-spec-lock"

echo "🔍 Ensuring blvm-spec-lock at: $DEST"

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ]; then
  echo "✅ blvm-spec-lock already present at $DEST"
  exit 0
fi

echo "📦 Cloning blvm-spec-lock from $REPO_URL (depth $DEPTH)..."
git clone --depth "$DEPTH" "$REPO_URL" "$DEST"

echo "✅ blvm-spec-lock ready at $DEST"
