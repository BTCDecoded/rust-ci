# rust-ci

Shared **GitHub Actions composite actions** for Rust repositories in the **BTCDecoded** org. The goal is one place to define how we install Rust, normalize CI for crates.io builds, and operate safely on **self-hosted** runners (disk and Cargo caches).

This repository has **no crates**—only reusable workflow building blocks. Workflows reference actions with:

`uses: BTCDecoded/rust-ci/<action-name>@main`

(or a pinned SHA for reproducibility).

## Actions

### `install-rust-toolchain`

Wraps [`dtolnay/rust-toolchain`](https://github.com/dtolnay/rust-toolchain) with an org **default pinned** toolchain when you do not use a repo `rust-toolchain.toml`.

| Input | Role |
| --- | --- |
| `toolchain` | Version string (default **1.88.0**). Ignored if `toolchain-file` is set. |
| `toolchain-file` | Path to `rust-toolchain.toml` or `rust-toolchain`; channel comes from that file. |
| `components` | Extra components (`rustfmt`, `clippy`, …). With `toolchain-file`, comma-separated for dtolnay; otherwise passed to `rustup component add` after the pinned install. |

Use `toolchain-file` when the repo owns the channel; use the default pin when you want org-wide consistency without per-repo files.

### `strip-patch-crates-io`

Removes **`[patch.crates-io]`** sections from `Cargo.toml` and `.cargo/config.toml` under a chosen directory so **CI resolves dependencies from crates.io** instead of local path overrides (typical monorepo / path-dev setup).

| Input | Role |
| --- | --- |
| `working-directory` | Root to search (default `.`). |

Run this **before** `cargo fetch` / `cargo build` in workflows that must behave like downstream crates.io consumers.

### `runner-disk-guard` (self-hosted)

If **root filesystem** use is above a threshold, prunes old entries under a configurable cache root (default **`/tmp/runner-cache`**) so long-lived runners do not fill the disk.

| Input | Role |
| --- | --- |
| `cache-root` | Directory to prune when over threshold. |
| `threshold-percent` | Trigger cleanup when usage exceeds this percent (default **80**). |
| `show-df` | If true, log `df -h` before/after when cleanup runs. |

### `runner-cargo-cache` (self-hosted)

Manages **persistent Cargo/registry/git and optional `target`** caches on the runner: bind environment variables from a cache key, **restore** before builds, **save** after builds, or **prune** old cache directories.

| Input | Role |
| --- | --- |
| `operation` | **`bind-env`** \| **`restore`** \| **`save`** \| **`prune`** (required). |
| `cache-key` | Segment used to isolate cache trees (required for `bind-env`). |
| `cache-root` | Root for cache dirs (default `/tmp/runner-cache`). |
| `include-target` | For `bind-env`, whether to set `TARGET_CACHE_DIR`. |
| `save-target-only` | For `save`, only sync `./target` (no registry/git). |

Typical sequence: `bind-env` → `restore` → build → `save` (and occasional `prune` in maintenance jobs).

## Typical usage

**GitHub-hosted:** `install-rust-toolchain` and often `strip-patch-crates-io` are enough.

**Self-hosted:** add `runner-disk-guard` early in the job, and use `runner-cargo-cache` around the compile steps so repeated builds stay fast without unbounded disk growth.

## Contributing

Changes here affect **every workflow** that pins `@main` (or your tag). Prefer small, backward-compatible input defaults; document new inputs in each action’s `action.yml` and update this README when behavior or defaults change.
