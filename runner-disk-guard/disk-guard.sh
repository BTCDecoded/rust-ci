#!/usr/bin/env bash
set -euo pipefail
CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-80}"
FAIL_PERCENT="${FAIL_PERCENT:-97}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
SHOW_DF="${SHOW_DF:-true}"

# POSIX df: percent used (no %) for the filesystem containing PATH.
pct_used_for_path() {
  local path="$1"
  df -P "$path" 2>/dev/null | awk 'NR==2 { gsub(/%/,"", $5); print $5 }' || echo 0
}

# POSIX df: available KiB for the filesystem containing PATH.
avail_kb_for_path() {
  local path="$1"
  df -Pk "$path" 2>/dev/null | awk 'NR==2 { print $4 }' || echo 0
}

if [ "$SHOW_DF" = "true" ]; then
  df -h
fi

mkdir -p "$CACHE_ROOT" 2>/dev/null || true

# Paths whose filesystems are checked: root, cache root, and (when set and
# present) the job workspace and runner temp dir. On self-hosted runners the
# latter two often live on a separate data volume (e.g. /mnt/data).
CHECK_PATHS=(/ "$CACHE_ROOT")
for p in "${GITHUB_WORKSPACE:-}" "${RUNNER_TEMP:-}"; do
  if [ -n "$p" ] && [ -e "$p" ]; then
    CHECK_PATHS+=("$p")
  fi
done

SHOULD_PRUNE=0
SUMMARY=""
for p in "${CHECK_PATHS[@]}"; do
  pct="$(pct_used_for_path "$p")"
  SUMMARY="$SUMMARY $p=${pct:-?}%"
  if [ "${pct:-0}" -gt "$THRESHOLD_PERCENT" ]; then
    SHOULD_PRUNE=1
  fi
done

if [ "$SHOULD_PRUNE" -eq 1 ]; then
  echo "runner-disk-guard: pruning under $CACHE_ROOT (used:${SUMMARY} threshold=${THRESHOLD_PERCENT}%)"
  find "$CACHE_ROOT" -maxdepth 2 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
  if [ "$SHOW_DF" = "true" ]; then
    df -h
  fi
fi

# Fail fast (after pruning) if any checked filesystem is still too full, so the
# job stops here with a clear message instead of rustc dying with ENOSPC.
MIN_FREE_KB=$(( MIN_FREE_GB * 1024 * 1024 ))
FAILED=0
SEEN_MOUNTS=" "
for p in "${CHECK_PATHS[@]}"; do
  # Report each filesystem once even if several paths share it.
  mnt="$(df -P "$p" 2>/dev/null | awk 'NR==2 { print $6 }' || true)"
  case "$SEEN_MOUNTS" in
    *" ${mnt:-$p} "*) continue ;;
  esac
  SEEN_MOUNTS="$SEEN_MOUNTS${mnt:-$p} "
  pct="$(pct_used_for_path "$p")"
  avail_kb="$(avail_kb_for_path "$p")"
  pct="${pct:-0}"
  avail_kb="${avail_kb:-0}"
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
