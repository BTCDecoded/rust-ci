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

**Self-hosted runners (shared disk, concurrent jobs):** If you see `rustc: Text file busy` (exit 126 / `ETXTBSY`) during `install-rust-toolchain`, rustup is usually replacing the `~/.cargo/bin` proxies while another job is executing them. This action exports `RUSTUP_PERMIT_COPY_RENAME` and `RUSTUP_NO_SELF_UPDATE` for all steps so file updates use a safer pattern and rustup does not self-update mid-job. If flakes persist, reduce parallelism on that runner (e.g. workflow `concurrency` per runner name, or separate `CARGO_HOME`/`RUSTUP_HOME` per job in isolated environments).

### `strip-patch-crates-io`

Removes **`[patch.crates-io]`** sections from `Cargo.toml` and `.cargo/config.toml` under a chosen directory so **CI resolves dependencies from crates.io** instead of local path overrides (typical monorepo / path-dev setup).

| Input | Role |
| --- | --- |
| `working-directory` | Root to search (default `.`). |

Run this **before** `cargo fetch` / `cargo build` in workflows that must behave like downstream crates.io consumers.

### `runner-disk-guard` (self-hosted)

If **root filesystem (`/`)** *or* the **filesystem containing `cache-root`** is above a threshold, prunes old **`cache-root`** subtrees (default age **7 days**, maxdepth **2**) so long-lived runners do not fill the disk. That includes the common case where **`/tmp` is a small tmpfs**, **`cache-root` defaults to `/tmp/runner-cache`**, and **`/` still has free space**—previously the guard only looked at `/` and would never prune.

| Input | Role |
| --- | --- |
| `cache-root` | Directory to prune when over threshold. |
| `threshold-percent` | Trigger cleanup when **either** measured use exceeds this percent (default **80**). |
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

### `setup-blvm-spec`

Clones the [blvm-spec](https://github.com/BTCDecoded/blvm-spec) (Orange Paper) repository for **spec-lock** verification, mdBook includes, or any job that needs spec markdown on disk.

| Input | Role |
| --- | --- |
| `working-directory` | Repo root for path resolution (default `.`). |
| `target` | Empty (default): clone to **`../blvm-spec`** (sibling of the checked-out repo), matching `cargo-spec-lock verify --spec-path ../blvm-spec/...`. Set to a path **relative to the repo** (e.g. `modules/blvm-spec`) for in-tree checkouts. |
| `repository` | Git URL (default official `blvm-spec` repo). |
| `depth` | Shallow clone depth (default `1`). |

## Typical usage

**GitHub-hosted:** `install-rust-toolchain` and often `strip-patch-crates-io` are enough.

**Self-hosted:** add `runner-disk-guard` early in the job, and use `runner-cargo-cache` around the compile steps so repeated builds stay fast without unbounded disk growth.

## Self-hosted runners: cache location (avoid filling tmpfs `/tmp`)

Default **`cache-root`** is **`/tmp/runner-cache`**. On many Linux setups **`/tmp` is tmpfs (RAM)**. Cargo/registry + `target` caches can grow to tens of GiB and **fill `/tmp` entirely**, breaking anything that writes there (e.g. rustup’s `rustup-init` download). **`/` may still have plenty of space.**

**Do one of the following (recommended: A).**

### A. Symlink the default path to real disk (no workflow edits)

Stop the runner, move data once, then point the default path at disk:

```bash
sudo systemctl stop actions.runner.*.service   # or your runner unit name

sudo mkdir -p /mnt/data/github-runner-cache
# Preserve existing cache if you want warm builds:
sudo rsync -a /tmp/runner-cache/ /mnt/data/github-runner-cache/ 2>/dev/null || true
sudo rm -rf /tmp/runner-cache
sudo ln -s /mnt/data/github-runner-cache /tmp/runner-cache
sudo chown -R YOUR_RUNNER_USER:YOUR_RUNNER_GROUP /mnt/data/github-runner-cache

sudo systemctl start actions.runner.*.service
```

Pick a directory on a **large persistent volume** (here `/mnt/data/...`). Workflows that keep the default **`/tmp/runner-cache`** automatically use disk.

### B. Set `cache-root` (and disk-guard’s `cache-root`) to a disk path

Use the same directory in **`runner-cargo-cache`** and **`runner-disk-guard`** inputs (org **Variables** help). No symlink; every workflow must pass the path (or inherit from a reusable workflow).

### C. Host maintenance

- Cron or a nightly job can run **`runner-cargo-cache`** with **`operation: prune`** (same **`cache-root`**).
- Optionally set **`TMPDIR`** for the runner service to a directory on disk (e.g. **`/var/tmp`**) so rustup and other tools do not depend on free tmpfs space.

## Contributing

Changes here affect **every workflow** that pins `@main` (or your tag). Prefer small, backward-compatible input defaults; document new inputs in each action’s `action.yml` and update this README when behavior or defaults change.
