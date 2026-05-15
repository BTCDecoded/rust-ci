#!/usr/bin/env bash
set -euo pipefail
CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-80}"
SHOW_DF="${SHOW_DF:-true}"

# POSIX df: percent used (no %) for the filesystem containing PATH.
pct_used_for_path() {
  local path="$1"
  df -P "$path" 2>/dev/null | awk 'NR==2 { gsub(/%/,"", $5); print $5 }' || echo 0
}

if [ "$SHOW_DF" = "true" ]; then
  df -h
fi

mkdir -p "$CACHE_ROOT" 2>/dev/null || true

ROOT_PCT="$(pct_used_for_path /)"
CACHE_PCT="$(pct_used_for_path "$CACHE_ROOT")"

SHOULD_PRUNE=0
if [ "${ROOT_PCT:-0}" -gt "$THRESHOLD_PERCENT" ]; then
  SHOULD_PRUNE=1
fi
if [ "${CACHE_PCT:-0}" -gt "$THRESHOLD_PERCENT" ]; then
  SHOULD_PRUNE=1
fi

if [ "$SHOULD_PRUNE" -eq 1 ]; then
  echo "runner-disk-guard: pruning under $CACHE_ROOT ( / used=${ROOT_PCT}% cache mount used=${CACHE_PCT}% threshold=${THRESHOLD_PERCENT}% )"
  find "$CACHE_ROOT" -maxdepth 2 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
  if [ "$SHOW_DF" = "true" ]; then
    df -h
  fi
fi
