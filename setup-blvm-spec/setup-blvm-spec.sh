#!/usr/bin/env bash
# Clone BTCDecoded/blvm-spec for CI (PROTOCOL.md / ARCHITECTURE.md / Orange Paper).
# Default: sibling of repo root at ../blvm-spec (matches cargo-spec-lock --spec-path ../blvm-spec/...).
# Optional: in-tree path (e.g. modules/blvm-spec) for mdBook and other layouts.
set -euo pipefail

REPO_ROOT="$(pwd)"
TARGET="${SETUP_BLVM_SPEC_TARGET:-}"
REPO_URL="${SETUP_BLVM_SPEC_REPO:-https://github.com/BTCDecoded/blvm-spec.git}"
DEPTH="${SETUP_BLVM_SPEC_DEPTH:-1}"

if [ -n "$TARGET" ]; then
  DEST="$REPO_ROOT/$TARGET"
  mkdir -p "$(dirname "$DEST")"
else
  DEST="$(dirname "$REPO_ROOT")/blvm-spec"
fi

echo "🔍 Ensuring blvm-spec at: $DEST"

# Replace incomplete or empty trees (e.g. failed prior run) so we always get usable markdown.
if [ -d "$DEST" ]; then
  if [ ! -f "$DEST/THE_ORANGE_PAPER.md" ] && [ ! -f "$DEST/PROTOCOL.md" ]; then
    echo "⚠️ Removing incomplete blvm-spec at $DEST"
    rm -rf "$DEST"
  fi
fi

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ]; then
  echo "✅ blvm-spec already present at $DEST"
  exit 0
fi

echo "📦 Cloning blvm-spec from $REPO_URL (depth $DEPTH)..."
git clone --depth "$DEPTH" "$REPO_URL" "$DEST"

echo "✅ blvm-spec ready at $DEST"
