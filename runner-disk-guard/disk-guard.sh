#!/usr/bin/env bash
set -euo pipefail
CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-80}"
SHOW_DF="${SHOW_DF:-true}"

if [ "$SHOW_DF" = "true" ]; then
  df -h
fi

if [ "$(df / | tail -1 | awk '{print $5}' | sed 's/%//')" -gt "$THRESHOLD_PERCENT" ]; then
  find "$CACHE_ROOT" -maxdepth 2 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
  if [ "$SHOW_DF" = "true" ]; then
    df -h
  fi
fi
