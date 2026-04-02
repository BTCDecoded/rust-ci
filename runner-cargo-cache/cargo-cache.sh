#!/usr/bin/env bash
# Self-hosted runner: bind env, restore/save Cargo + target caches under /tmp/runner-cache.
set -euo pipefail

op="${1:?operation required: bind-env|restore|save|prune}"

case "$op" in
bind-env)
  : "${CACHE_KEY:?CACHE_KEY required}"
  CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
  INCLUDE_TARGET="${INCLUDE_TARGET:-true}"
  echo "CARGO_CACHE_DIR=$CACHE_ROOT/cargo/$CACHE_KEY" >>"$GITHUB_ENV"
  if [ "$INCLUDE_TARGET" = "true" ] || [ "$INCLUDE_TARGET" = "1" ]; then
    echo "TARGET_CACHE_DIR=$CACHE_ROOT/target/$CACHE_KEY" >>"$GITHUB_ENV"
  fi
  ;;

restore)
  if [ -n "${CARGO_CACHE_DIR:-}" ]; then
    if [ -d "$CARGO_CACHE_DIR/registry" ] && [ "$(ls -A "$CARGO_CACHE_DIR/registry" 2>/dev/null)" ]; then
      mkdir -p "$HOME/.cargo/registry"
      rsync -a --delete "$CARGO_CACHE_DIR/registry/" "$HOME/.cargo/registry/" || true
    else
      echo "💿 No Cargo registry cache found"
    fi
    if [ -d "$CARGO_CACHE_DIR/git" ] && [ "$(ls -A "$CARGO_CACHE_DIR/git" 2>/dev/null)" ]; then
      mkdir -p "$HOME/.cargo/git"
      rsync -a --delete "$CARGO_CACHE_DIR/git/" "$HOME/.cargo/git/" || true
    else
      echo "💿 No Cargo git cache found"
    fi
  fi

  if [ -n "${TARGET_CACHE_DIR:-}" ]; then
    if [ -d "$TARGET_CACHE_DIR" ] && [ "$(ls -A "$TARGET_CACHE_DIR" 2>/dev/null)" ]; then
      mkdir -p ./target
      rsync -a --delete "$TARGET_CACHE_DIR/" ./target/ || true
    else
      echo "💿 No target cache found, will build from scratch"
    fi
  fi

  if [ -n "${CONSENSUS_TARGET_DIR:-}" ]; then
    if [ -d "$CONSENSUS_TARGET_DIR" ] && [ "$(ls -A "$CONSENSUS_TARGET_DIR" 2>/dev/null)" ]; then
      mkdir -p ../blvm-consensus/target
      rsync -a --delete "$CONSENSUS_TARGET_DIR/" ../blvm-consensus/target/ || true
    else
      echo "💿 No blvm-consensus target cache found"
    fi
  fi
  if [ -n "${PROTOCOL_TARGET_DIR:-}" ]; then
    if [ -d "$PROTOCOL_TARGET_DIR" ] && [ "$(ls -A "$PROTOCOL_TARGET_DIR" 2>/dev/null)" ]; then
      mkdir -p ../blvm-protocol/target
      rsync -a --delete "$PROTOCOL_TARGET_DIR/" ../blvm-protocol/target/ || true
    else
      echo "💿 No blvm-protocol target cache found"
    fi
  fi
  if [ -n "${NODE_TARGET_DIR:-}" ]; then
    if [ -d "$NODE_TARGET_DIR" ] && [ "$(ls -A "$NODE_TARGET_DIR" 2>/dev/null)" ]; then
      mkdir -p ../blvm-node/target
      rsync -a --delete "$NODE_TARGET_DIR/" ../blvm-node/target/ || true
    else
      echo "💿 No blvm-node target cache found"
    fi
  fi
  ;;

save)
  if [ "${SAVE_TARGET_ONLY:-false}" = "true" ] || [ "${SAVE_TARGET_ONLY:-0}" = "1" ]; then
    if [ -n "${TARGET_CACHE_DIR:-}" ] && [ -d "./target" ]; then
      rsync -a --delete "./target/" "$TARGET_CACHE_DIR/" || true
    fi
    exit 0
  fi

  if [ -n "${CARGO_CACHE_DIR:-}" ] && [ "$CARGO_CACHE_DIR" != "" ]; then
    mkdir -p "$CARGO_CACHE_DIR/registry" "$CARGO_CACHE_DIR/git"
    if [ -d "$HOME/.cargo/registry" ]; then
      rsync -a --delete "$HOME/.cargo/registry/" "$CARGO_CACHE_DIR/registry/" || true
    fi
    if [ -d "$HOME/.cargo/git" ]; then
      rsync -a --delete "$HOME/.cargo/git/" "$CARGO_CACHE_DIR/git/" || true
    fi
  fi
  if [ -n "${TARGET_CACHE_DIR:-}" ] && [ -d "./target" ]; then
    rsync -a --delete "./target/" "$TARGET_CACHE_DIR/" || true
  fi
  if [ -n "${CONSENSUS_TARGET_DIR:-}" ] && [ -d "../blvm-consensus/target" ]; then
    rsync -a --delete ../blvm-consensus/target/ "$CONSENSUS_TARGET_DIR/" || true
  fi
  if [ -n "${PROTOCOL_TARGET_DIR:-}" ] && [ -d "../blvm-protocol/target" ]; then
    rsync -a --delete ../blvm-protocol/target/ "$PROTOCOL_TARGET_DIR/" || true
  fi
  if [ -n "${NODE_TARGET_DIR:-}" ] && [ -d "../blvm-node/target" ]; then
    rsync -a --delete ../blvm-node/target/ "$NODE_TARGET_DIR/" || true
  fi
  ;;

prune)
  CACHE_ROOT="${CACHE_ROOT:-/tmp/runner-cache}"
  echo "🧹 Cleaning up old caches..."
  if [ -d "$CACHE_ROOT/cargo" ]; then
    find "$CACHE_ROOT/cargo" -maxdepth 1 -type d -mtime +1 2>/dev/null | head -n -5 | xargs rm -rf 2>/dev/null || true
  fi
  if [ -d "$CACHE_ROOT/target" ]; then
    find "$CACHE_ROOT/target" -maxdepth 1 -type d -mtime +1 2>/dev/null | head -n -3 | xargs rm -rf 2>/dev/null || true
  fi
  for SUB in blvm-consensus-target blvm-protocol-target blvm-node-target; do
    D="$CACHE_ROOT/$SUB"
    if [ -d "$D" ]; then
      find "$D" -maxdepth 1 -type d -mtime +1 2>/dev/null | head -n -3 | xargs rm -rf 2>/dev/null || true
    fi
  done
  ;;

*)
  echo "Unknown operation: $op" >&2
  exit 1
  ;;
esac
