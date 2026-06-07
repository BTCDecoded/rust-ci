#!/usr/bin/env bash
# One-time bootstrap for an isolated runner HOME (see runner-toolchain-isolation.conf).
# Seeds rustup + common CI tools from the primary github-runner home when present.
set -euo pipefail

RUNNER_USER="${RUNNER_USER:-github-runner}"
RUNNER_HOME="${RUNNER_HOME:-/var/lib/github-runner-2}"
PRIMARY_HOME="${PRIMARY_HOME:-/var/lib/github-runner}"
TOOLCHAIN="${TOOLCHAIN:-1.88.0}"
CARGO_AUDIT_VERSION="${CARGO_AUDIT_VERSION:-0.22.1}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

mkdir -p "${RUNNER_HOME}"
chown "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"

if [[ ! -d "${PRIMARY_HOME}/.rustup" ]]; then
  echo "Primary rustup not found at ${PRIMARY_HOME}/.rustup" >&2
  exit 1
fi

echo "==> Seeding ${RUNNER_HOME}/.rustup from ${PRIMARY_HOME}/.rustup"
sudo -u "${RUNNER_USER}" mkdir -p "${RUNNER_HOME}/.rustup" "${RUNNER_HOME}/.cargo/bin"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "${PRIMARY_HOME}/.rustup/" "${RUNNER_HOME}/.rustup/"
else
  cp -a "${PRIMARY_HOME}/.rustup/." "${RUNNER_HOME}/.rustup/"
fi
chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}/.rustup"

echo "==> Shared registry/git symlinks (save disk; safe across isolated homes)"
sudo -u "${RUNNER_USER}" mkdir -p "${RUNNER_HOME}/.cargo"
for sub in registry git; do
  if [[ -d "${PRIMARY_HOME}/.cargo/${sub}" ]]; then
    ln -sfn "${PRIMARY_HOME}/.cargo/${sub}" "${RUNNER_HOME}/.cargo/${sub}"
  fi
done

echo "==> rustup proxies + verify toolchain ${TOOLCHAIN}"
# Use the primary rustup binary once; it writes proxies into RUNNER_HOME/.cargo/bin.
PRIMARY_RUSTUP="${PRIMARY_HOME}/.cargo/bin/rustup"
if [[ ! -x "${PRIMARY_RUSTUP}" ]]; then
  echo "rustup not found at ${PRIMARY_RUSTUP}" >&2
  exit 1
fi
sudo -u "${RUNNER_USER}" env \
  HOME="${RUNNER_HOME}" \
  CARGO_HOME="${RUNNER_HOME}/.cargo" \
  RUSTUP_HOME="${RUNNER_HOME}/.rustup" \
  PATH="${PRIMARY_HOME}/.cargo/bin:/usr/local/bin:/usr/bin" \
  bash --noprofile --norc -lc "
    set -euo pipefail
    rustup default '${TOOLCHAIN}'
    rustc --version
    cargo --version
    if [[ -x "${PRIMARY_HOME}/.cargo/bin/cargo-audit" ]]; then
      cp -a "${PRIMARY_HOME}/.cargo/bin/cargo-audit" "${RUNNER_HOME}/.cargo/bin/" || true
    fi
    if ! command -v cargo-audit >/dev/null 2>&1 || ! cargo-audit --version | grep -qF '${CARGO_AUDIT_VERSION}'; then
      cargo install cargo-audit --version '${CARGO_AUDIT_VERSION}' --locked --force
    fi
    cargo-audit --version
    command -v cargo-spec-lock >/dev/null 2>&1 && cargo-spec-lock --version || true
  "

echo "✅ Isolated runner toolchain ready under ${RUNNER_HOME}"
