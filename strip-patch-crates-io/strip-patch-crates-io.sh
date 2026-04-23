#!/usr/bin/env bash
# Remove [patch.crates-io] blocks so CI resolves blvm-* from crates.io (no sibling repos).
# Includes fuzz/Cargo.toml: committed patches are for local monorepo; CI strips before build.
# Local dev keeps committed patches when the monorepo layout exists.
set -euo pipefail

strip_one() {
  local f="$1"
  [ -f "$f" ] || return 0
  grep -q '^\[patch\.crates-io\]' "$f" 2>/dev/null || return 0
  awk '
    /^\[patch\.crates-io\]/ { skip = 1; next }
    skip && /^\[/ { skip = 0 }
    !skip { print }
  ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  echo "Stripped [patch.crates-io] from $f"
}

while IFS= read -r -d '' f; do
  strip_one "$f"
done < <(
  find . \
    -name Cargo.toml \
    -not -path './target/*' \
    -not -path './_temp-*/*' \
    -not -path './.git/*' \
    -print0 2>/dev/null
)

while IFS= read -r -d '' f; do
  strip_one "$f"
done < <(
  find . \
    -path '*/.cargo/config.toml' \
    -not -path './target/*' \
    -not -path './_temp-*/*' \
    -not -path './.git/*' \
    -print0 2>/dev/null
)
