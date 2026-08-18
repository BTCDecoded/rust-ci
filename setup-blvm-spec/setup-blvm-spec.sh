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

spec_is_usable() {
  [ -f "$DEST/PROTOCOL.md" ] && [ -f "$DEST/ARCHITECTURE.md" ] && return 0
  [ -f "$DEST/THE_ORANGE_PAPER.md" ] && return 0
  return 1
}

# Replace incomplete trees (e.g. failed prior run) so we always get usable markdown.
# Only wipe in CI. Locally, a sibling that fails spec_is_usable must not be deleted.
if [ -d "$DEST" ] && ! spec_is_usable; then
  if [ "${CI:-}" = "true" ]; then
    echo "⚠️ Removing incomplete blvm-spec at $DEST (CI)"
    rm -rf "$DEST"
  else
    echo "❌ Incomplete blvm-spec at $DEST (missing PROTOCOL.md / ARCHITECTURE.md / THE_ORANGE_PAPER.md)."
    echo "   Not removing local tree. Set CI=true to wipe, or fix/replace $DEST."
    exit 1
  fi
fi

if [ -d "$DEST/.git" ]; then
  if [ "${CI:-}" = "true" ]; then
    echo "🔄 Refreshing blvm-spec at $DEST (CI)"
    git -C "$DEST" fetch --depth="$DEPTH" origin main
    git -C "$DEST" checkout --detach FETCH_HEAD
    echo "✅ blvm-spec at $(git -C "$DEST" rev-parse --short HEAD)"
  else
    echo "✅ blvm-spec already present at $DEST (local checkout — not refreshed)"
  fi
  exit 0
fi

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ] && spec_is_usable; then
  echo "✅ blvm-spec already present at $DEST (no .git — shallow copy)"
  exit 0
fi

echo "📦 Cloning blvm-spec from $REPO_URL (depth $DEPTH)..."
git clone --depth "$DEPTH" "$REPO_URL" "$DEST"

echo "✅ blvm-spec ready at $DEST"
