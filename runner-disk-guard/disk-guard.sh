#!/usr/bin/env bash
set -euo pipefail
CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
THRESHOLD_PERCENT="${THRESHOLD_PERCENT:-80}"
FAIL_PERCENT="${FAIL_PERCENT:-97}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-15}"
SHOW_DF="${SHOW_DF:-true}"

# Normalize and refuse to operate on an empty path or the filesystem root.
CACHE_ROOT="${CACHE_ROOT%/}"
if [ -z "$CACHE_ROOT" ] || [ "$CACHE_ROOT" = "/" ]; then
  echo "::error::runner-disk-guard: CACHE_ROOT must be a non-empty path other than /"
  exit 1
fi

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
require_uint min-age-minutes "$MIN_AGE_MINUTES"
# Strip leading zeros so values like "08" are not parsed as octal.
THRESHOLD_PERCENT=$((10#$THRESHOLD_PERCENT))
FAIL_PERCENT=$((10#$FAIL_PERCENT))
MIN_FREE_GB=$((10#$MIN_FREE_GB))
MIN_AGE_MINUTES=$((10#$MIN_AGE_MINUTES))
MIN_FREE_KB=$(( MIN_FREE_GB * 1024 * 1024 ))

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

# CACHE_ROOT filesystem only (not deduped away when it shares a mount with /).
read_cache_fs() {
  local stats
  stats="$(df_stats "$CACHE_ROOT")"
  read -r CACHE_PCT CACHE_AVAIL_KB _ <<<"$stats" || true
  case "${CACHE_PCT:-}${CACHE_AVAIL_KB:-}" in
    ''|*[!0-9]*)
      CACHE_PCT=""
      CACHE_AVAIL_KB=""
      return 1
      ;;
  esac
  return 0
}

cache_fs_is_failing() {
  [ "$CACHE_PCT" -gt "$FAIL_PERCENT" ] || [ "$CACHE_AVAIL_KB" -lt "$MIN_FREE_KB" ]
}

# Headroom for the current build: at or below the prune threshold, with the
# configured free-space floor (min-free-gb 0 means MIN_FREE_KB is 0).
cache_fs_has_headroom() {
  [ "$CACHE_PCT" -le "$THRESHOLD_PERCENT" ] && [ "$CACHE_AVAIL_KB" -ge "$MIN_FREE_KB" ]
}

# Bucket dirs: cargo, target, or *-target at depth 1 (flat) or up to 3
# (repo-scoped: $CACHE_ROOT/<org>/<repo>/cargo). maxdepth 3 avoids walking
# into cache-key contents. Skip a match whose ancestor is already a bucket.
list_bucket_dirs() {
  local dir rel parent base nested
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    rel="${dir#"$CACHE_ROOT"/}"
    [ "$rel" != "$dir" ] || continue
    nested=0
    parent="$(dirname "$rel")"
    while [ "$parent" != "." ]; do
      base="$(basename "$parent")"
      case "$base" in
        cargo|target|*-target) nested=1; break ;;
      esac
      parent="$(dirname "$parent")"
    done
    [ "$nested" -eq 0 ] || continue
    printf '%s\n' "$dir"
  done < <(find "$CACHE_ROOT" -mindepth 1 -maxdepth 3 -type d \
    \( -name cargo -o -name target -o -name '*-target' \) -print 2>/dev/null || true)
}

# True if DIR is a cache-key path under CACHE_ROOT (never CACHE_ROOT itself).
is_safe_key_dir() {
  local dir="$1"
  [ -n "$dir" ] || return 1
  [ "$dir" != "/" ] || return 1
  [ "$dir" != "$CACHE_ROOT" ] || return 1
  case "$dir" in
    "$CACHE_ROOT"/*) ;;
    *) return 1 ;;
  esac
  return 0
}

# Age prune: delete cache-key dirs with mtime older than 7 days. Does not
# delete structural parents (e.g. $CACHE_ROOT/<org>) or CACHE_ROOT itself.
prune_mtime_plus7() {
  local bucket dir count=0
  while IFS= read -r bucket; do
    [ -n "$bucket" ] || continue
    while IFS= read -r dir; do
      is_safe_key_dir "$dir" || continue
      echo "runner-disk-guard: prune (+7d): $dir"
      rm -rf -- "$dir" 2>/dev/null || true
      count=$((count + 1))
    done < <(find "$bucket" -mindepth 1 -maxdepth 1 -type d -mtime +7 -print 2>/dev/null || true)
  done < <(list_bucket_dirs || true)
  echo "runner-disk-guard: age prune removed $count cache entries (mtime +7d)"
}

# LRU fallback: oldest cache-key dirs first, skipping entries touched in the
# last MIN_AGE_MINUTES so a concurrent save/restore is not clobbered. Stop
# once the cache filesystem is at or below threshold-percent with at least
# min-free-gb free. A failed rm (e.g. another user owns the dir) is ignored
# and the loop continues over the snapshot list (it does not retry forever).
prune_lru() {
  local dir count=0
  echo "runner-disk-guard: LRU prune under $CACHE_ROOT (used ${CACHE_PCT}%, $((CACHE_AVAIL_KB / 1024))M free; fail-percent=${FAIL_PERCENT}% min-free-gb=${MIN_FREE_GB} min-age-minutes=${MIN_AGE_MINUTES})"
  while IFS=$'\t' read -r _ dir; do
    [ -n "${dir:-}" ] || continue
    is_safe_key_dir "$dir" || continue
    echo "runner-disk-guard: LRU prune: $dir"
    rm -rf -- "$dir" 2>/dev/null || true
    count=$((count + 1))
    if ! read_cache_fs; then
      break
    fi
    if cache_fs_has_headroom; then
      echo "runner-disk-guard: LRU recovered headroom (cache ${CACHE_PCT}% used, $((CACHE_AVAIL_KB / 1024))M free) after $count entries"
      break
    fi
  done < <(
    {
      while IFS= read -r bucket; do
        [ -n "$bucket" ] || continue
        find "$bucket" -mindepth 1 -maxdepth 1 -type d \
          -mmin +"${MIN_AGE_MINUTES}" -printf '%T@\t%p\n' 2>/dev/null || true
      done < <(list_bucket_dirs || true)
    } | sort -n || true
  )
  echo "runner-disk-guard: LRU pruned $count cache entries"
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
  prune_mtime_plus7
  if [ "$SHOW_DF" = "true" ]; then
    df -h
  fi
  measure
fi

if read_cache_fs && cache_fs_is_failing; then
  prune_lru
  if [ "$SHOW_DF" = "true" ]; then
    df -h
  fi
  measure
fi

# Fail fast (after pruning) if any checked filesystem is still too full, so the
# job stops here with a clear message instead of rustc dying with ENOSPC.
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
