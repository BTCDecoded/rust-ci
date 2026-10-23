#!/usr/bin/env bash
set -euo pipefail
CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-80}"
FAIL_PERCENT="${FAIL_PERCENT:-97}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
SHOW_DF="${SHOW_DF:-true}"

# Inputs must be non-negative integers (bash arithmetic is integer-only).
require_uint() {
  local name="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "::error::runner-disk-guard: $name must be a non-negative integer (got $value)"
      exit 1
      ;;
  esac
}
require_uint threshold-percent "$THRESHOLD_PERCENT"
require_uint fail-percent "$FAIL_PERCENT"
require_uint min-free-gb "$MIN_FREE_GB"
# Strip leading zeros so values like "08" are not parsed as octal.
THRESHOLD_PERCENT=$((10#$THRESHOLD_PERCENT))
FAIL_PERCENT=$((10#$FAIL_PERCENT))
MIN_FREE_GB=$((10#$MIN_FREE_GB))

# POSIX df for the filesystem containing PATH: prints "<pct_used> <avail_kb> <mount>",
# or nothing if df cannot read the path.
df_stats() {
  local path="$1"
  df -Pk "$path" 2>/dev/null | awk 'NR==2 { gsub(/%/,"", $5); print $5, $4, $6 }' || true
}

if [ "$SHOW_DF" = "true" ]; then
  df -h
fi

# Paths whose filesystems are checked: root, cache root, and (when set and
# present) the job workspace and runner temp dir. On self-hosted runners the
# latter two often live on a separate data volume (e.g. /mnt/data).
CHECK_PATHS=(/ "$CACHE_ROOT")
for p in "${GITHUB_WORKSPACE:-}" "${RUNNER_TEMP:-}"; do
  if [ -n "$p" ] && [ -e "$p" ]; then
    CHECK_PATHS+=("$p")
  fi
done

# Measure every check path once per filesystem. Fills STAT_PATHS/STAT_PCT/
# STAT_AVAIL/SUMMARY; unreadable paths get a warning and are skipped so they
# never count as "disk full".
measure() {
  local p stats pct avail mnt seen=" "
  STAT_PATHS=(); STAT_PCT=(); STAT_AVAIL=(); SUMMARY=""
  mkdir -p "$CACHE_ROOT" 2>/dev/null || true
  for p in "${CHECK_PATHS[@]}"; do
    stats="$(df_stats "$p")"
    read -r pct avail mnt <<<"$stats" || true
    case "${pct:-}${avail:-}" in
      ''|*[!0-9]*)
        echo "::warning::runner-disk-guard: cannot stat $p"
        continue
        ;;
    esac
    case "$seen" in
      *" ${mnt:-$p} "*) continue ;;
    esac
    seen="$seen${mnt:-$p} "
    STAT_PATHS+=("$p"); STAT_PCT+=("$pct"); STAT_AVAIL+=("$avail")
    SUMMARY="$SUMMARY $p=${pct}%"
  done
}

measure
SHOULD_PRUNE=0
for i in "${!STAT_PATHS[@]}"; do
  if [ "${STAT_PCT[$i]}" -gt "$THRESHOLD_PERCENT" ]; then
    SHOULD_PRUNE=1
  fi
done

if [ "$SHOULD_PRUNE" -eq 1 ]; then
  echo "runner-disk-guard: pruning under $CACHE_ROOT (used:${SUMMARY} threshold=${THRESHOLD_PERCENT}%)"
  # -mindepth 1: never delete CACHE_ROOT itself, only old entries beneath it.
  find "$CACHE_ROOT" -mindepth 1 -maxdepth 2 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
  if [ "$SHOW_DF" = "true" ]; then
    df -h
  fi
  measure
fi

# Fail fast (after pruning) if any checked filesystem is still too full, so the
# job stops here with a clear message instead of rustc dying with ENOSPC.
MIN_FREE_KB=$(( MIN_FREE_GB * 1024 * 1024 ))
FAILED=0
for i in "${!STAT_PATHS[@]}"; do
  p="${STAT_PATHS[$i]}"; pct="${STAT_PCT[$i]}"; avail_kb="${STAT_AVAIL[$i]}"
  if [ "$pct" -gt "$FAIL_PERCENT" ] || [ "$avail_kb" -lt "$MIN_FREE_KB" ]; then
    free_h="$(awk -v k="$avail_kb" 'BEGIN { printf "%.1fG", k / 1048576 }')"
    echo "::error::runner disk full: $p ${pct}% used, ${free_h} free (fail-percent=${FAIL_PERCENT}% min-free-gb=${MIN_FREE_GB})"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "runner-disk-guard: ok (used:${SUMMARY} fail-percent=${FAIL_PERCENT}% min-free-gb=${MIN_FREE_GB})"
